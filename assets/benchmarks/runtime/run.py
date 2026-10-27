#!/usr/bin/env python3
"""Build and compare the same runtime workloads across four languages."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = Path(__file__).resolve().parent


def checked(command: list[str], timeout: int = 240) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"timed out: {' '.join(command)}") from error
    if result.returncode != 0:
        raise RuntimeError(
            f"failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout: {result.stdout.decode(errors='replace')}\n"
            f"stderr: {result.stderr.decode(errors='replace')}"
        )
    return result


def reference(workload: str, n: int, fixtures: dict[str, Path]) -> bytes:
    checksum = 0
    if workload == "loop":
        state = 1
        for i in range(n):
            state = (state * 17 + (i % 13) + 11) % 1_000_003
            checksum += state % 97
    elif workload == "array":
        for i in range(n):
            checksum += ((i * 17 + 3) % 1_000_003) % 97
    elif workload == "nodes":
        checksum = sum(i % 97 for i in range(n))
    elif workload == "log":
        lines = fixtures["log"].read_bytes().splitlines()
        checksum = sum(line.startswith(b"E") for line in lines) * 97 + len(lines)
    elif workload == "csv":
        lines = fixtures["csv"].read_text().splitlines()
        checksum = sum(int(line.split(",", 1)[1]) for line in lines) + len(lines) * 3
    elif workload == "bytes":
        for byte in fixtures["bytes"].read_bytes():
            checksum = (checksum * 33 + byte) % 1_000_003
    return f"{checksum}\n".encode()


def make_fixtures(work: Path, records: int, byte_count: int) -> dict[str, Path]:
    fixtures = {name: work / f"input-{name}.dat" for name in ("log", "csv", "bytes")}
    with fixtures["log"].open("wb") as output:
        for i in range(records):
            level = "E" if i % 5 == 0 else "I"
            output.write(f"{level}|{i % 1000:04d}|{i % 97:02d}\n".encode())
    with fixtures["csv"].open("wb") as output:
        for i in range(records):
            output.write(f"{i % 1000},{i % 97}\n".encode())
    pattern = bytes((i * 17 + 3) % 256 for i in range(256))
    with fixtures["bytes"].open("wb") as output:
        full, tail = divmod(byte_count, 256)
        output.write(pattern * full + pattern[:tail])
    return fixtures


def cpu_model() -> str:
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor()


def version(command: str) -> str:
    return checked([command, "--version"], 15).stdout.decode(errors="replace").splitlines()[0]


def time_build(command: list[str]) -> float:
    start = time.perf_counter_ns()
    checked(command)
    return (time.perf_counter_ns() - start) / 1_000_000_000


def run_sample(command: list[str], expected: bytes, timeout: int) -> float:
    start = time.perf_counter_ns()
    result = checked(command, timeout)
    elapsed = (time.perf_counter_ns() - start) / 1_000_000_000
    if result.stdout != expected or result.stderr:
        raise RuntimeError(
            f"wrong output: {' '.join(command)}\n"
            f"expected: {expected!r}\nactual: {result.stdout!r}\nstderr: {result.stderr!r}"
        )
    return elapsed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=2_000_000)
    parser.add_argument("--records", type=int, default=100_000, help="log and CSV rows")
    parser.add_argument("--bytes", type=int, default=1_600_000, help="binary file size")
    parser.add_argument("--nodes", type=int, default=20_000, help="linked objects")
    parser.add_argument("--workloads", default="loop,array,log,csv,bytes,nodes",
                        help="comma-separated subset of loop,array,log,csv,bytes,nodes")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--native", type=Path, default=ROOT / "build/self_hosting/hydrogen-stage3")
    parser.add_argument("--sdk", type=Path, default=ROOT / "build/hy")
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--cxx", default="c++")
    parser.add_argument("--rustc", default="rustc")
    parser.add_argument("--include-sdk-c", action="store_true", help="also compare the legacy SDK C output")
    parser.add_argument("--include-interpreter", action="store_true")
    parser.add_argument("--json", type=Path, help="also save raw samples and build metadata")
    args = parser.parse_args()
    if not (1 <= args.iterations <= 20_000_000):
        parser.error("--iterations must be between 1 and 20,000,000")
    if min(args.records, args.bytes, args.nodes) < 1:
        parser.error("--records, --bytes and --nodes must be positive")
    workloads = args.workloads.split(",")
    if not workloads or len(set(workloads)) != len(workloads) or any(
        item not in {"loop", "array", "log", "csv", "bytes", "nodes"} for item in workloads
    ):
        parser.error("--workloads must be a comma-separated subset of loop,array,log,csv,bytes,nodes")
    if args.runs < 1 or args.warmups < 0 or args.timeout < 1:
        parser.error("runs and timeout must be positive; warmups cannot be negative")

    native = args.native.resolve()
    sdk = args.sdk.resolve()
    required_binaries = [native]
    if args.include_sdk_c or args.include_interpreter:
        required_binaries.append(sdk)
    for binary in required_binaries:
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"missing executable: {binary}")
    compilers = {}
    for name, requested in (("C", args.cc), ("C++", args.cxx), ("Rust", args.rustc)):
        resolved = shutil.which(requested)
        if resolved is None:
            parser.error(f"{name} compiler not found: {requested}")
        compilers[name] = resolved

    report = {
        "platform": platform.platform(),
        "cpu": cpu_model(),
        "iterations": args.iterations,
        "records": args.records,
        "bytes": args.bytes,
        "nodes": args.nodes,
        "runs": args.runs,
        "warmups": args.warmups,
        "flags": {"C": "-O2 -std=c11", "C++": "-O2 -std=c++20", "Rust": "-C opt-level=2"},
        "compilers": {name: {"path": path, "version": version(path)} for name, path in compilers.items()},
        "hydrogen": {"native_path": str(native), "native_sha256": hashlib.sha256(native.read_bytes()).hexdigest()},
        "sources": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCE_DIR.glob("workload.*")},
        "build_seconds": {},
        "workloads": {},
    }

    with tempfile.TemporaryDirectory(prefix="hydrogen-runtime-bench-") as temporary:
        work = Path(temporary)
        hy_source = work / "workload.hy"
        shutil.copy2(SOURCE_DIR / "workload.hy", hy_source)
        routes = ["Hydrogen native", "C", "C++", "Rust"]
        if args.include_sdk_c:
            routes.append("Hydrogen SDK C")
            report["flags"]["Hydrogen SDK C"] = "hy build default (-O2)"
        if args.include_sdk_c or args.include_interpreter:
            report["hydrogen"].update({"sdk_path": str(sdk),
                                       "sdk_sha256": hashlib.sha256(sdk.read_bytes()).hexdigest()})
        binaries = {name: work / name.replace(" ", "_").lower() for name in routes}
        build_commands = {
            "Hydrogen native": [str(native), "compile", str(hy_source), "-o", str(binaries["Hydrogen native"])],
            "C": [compilers["C"], "-O2", "-std=c11", str(SOURCE_DIR / "workload.c"), "-o", str(binaries["C"])],
            "C++": [compilers["C++"], "-O2", "-std=c++20", str(SOURCE_DIR / "workload.cpp"), "-o", str(binaries["C++"])],
            "Rust": [compilers["Rust"], "--edition=2021", "-C", "opt-level=2", str(SOURCE_DIR / "workload.rs"), "-o", str(binaries["Rust"])],
        }
        if args.include_sdk_c:
            build_commands["Hydrogen SDK C"] = [str(sdk), "build", str(hy_source), "-o", str(binaries["Hydrogen SDK C"]),
                                                 "--hide-progress", "--hide-spinner", "--hide-log"]
        for name, command in build_commands.items():
            report["build_seconds"][name] = time_build(command)
            binaries[name].chmod(binaries[name].stat().st_mode | 0o111)

        fixtures = make_fixtures(work, args.records, args.bytes)
        report["inputs"] = {name: {"size_bytes": path.stat().st_size,
                                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                            for name, path in fixtures.items()}
        for workload in workloads:
            value = {"loop": args.iterations, "array": args.iterations,
                     "nodes": args.nodes}.get(workload, 0)
            argument = str(value) if value else str(fixtures[workload])
            expected = reference(workload, value, fixtures)
            commands = {name: [str(binary), workload, argument] for name, binary in binaries.items()}
            if args.include_interpreter:
                commands["Hydrogen interpreter"] = [str(sdk), "run", str(hy_source), "--", workload, argument]
            for command in commands.values():
                for _ in range(args.warmups):
                    run_sample(command, expected, args.timeout)
            samples = {name: [] for name in commands}
            rng = random.Random(0)
            for _ in range(args.runs):
                order = list(commands)
                rng.shuffle(order)
                for name in order:
                    samples[name].append(run_sample(commands[name], expected, args.timeout))
            medians = {name: statistics.median(values) for name, values in samples.items()}
            c_median = medians["C"]
            report["workloads"][workload] = {"input": argument if value else workload + " fixture",
                                             "expected_output": expected.decode().strip(),
                                             "samples_seconds": samples, "median_seconds": medians}
            print(f"\n{workload}: {value if value else report['inputs'][workload]['size_bytes']:,} "
                  f"{'items' if value else 'input bytes'}; expected {expected.decode().strip()}")
            print(f"{'route':<22} {'median ms':>12} {'vs C':>12}")
            for name, elapsed in medians.items():
                print(f"{name:<22} {elapsed * 1000:12.3f} {elapsed / c_median:11.2f}x")

    print("\nbuild time (seconds; not included in runtime):")
    for name, elapsed in report["build_seconds"].items():
        print(f"  {name:<20} {elapsed:.3f}")
    if args.json:
        destination = args.json.resolve()
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, indent=2) + "\n")
        print(f"\nraw results: {destination}")


if __name__ == "__main__":
    main()

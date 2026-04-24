#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const target = process.argv[2];
if (!target) {
  console.error("usage: hy-check-json.js <target.hy|target.hyproj>");
  process.exit(1);
}

const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const localHyBinary = path.join(repoRoot, "build", "hy");
const hyBinary = process.env.HYLANG_BIN || (fs.existsSync(localHyBinary) ? localHyBinary : "hy");
const result = spawnSync(hyBinary, ["check", target, "--json"], {
  encoding: "utf8"
});

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

const stdout = result.stdout || "[]";
let diagnostics;
try {
  diagnostics = JSON.parse(stdout);
} catch (error) {
  process.stdout.write(stdout);
  process.stderr.write(result.stderr || "");
  console.error(`Failed to parse hy check JSON: ${error.message}`);
  process.exit(result.status || 1);
}

let hasErrors = false;
for (const diagnostic of diagnostics) {
  const severity = diagnostic.severity || "error";
  if (severity === "error") {
    hasErrors = true;
  }
  const file = diagnostic.file || "<unknown>";
  const line = diagnostic.line || 1;
  const column = diagnostic.column || 1;
  const message = diagnostic.message || "";
  console.log(`${file}(${line},${column}): ${severity} HYLANG: ${message}`);
}

if (result.stderr) {
  process.stderr.write(result.stderr);
}

if (result.status && result.status !== 0) {
  process.exit(result.status);
}

process.exit(hasErrors ? 1 : 0);

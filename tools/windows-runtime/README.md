# Windows x64 managed runtime

`generate.py` combines the shared direct-runtime assembly at
`../native-runtime/runtime.S` with `shim.S`, replacing the Linux syscall
instructions with Win32-backed calls. It writes the checked-in
`WindowsRuntimeEmitter.hy` byte emitter and symbol offsets. The development
regeneration step needs GNU `as`, `objcopy`, `objdump`, and `nm`; compiling
Hydrogen programs later needs none of them.

From the compiler repository root:

```bash
python3 tools/windows-runtime/generate.py
```

The runtime keeps Hydrogen's internal x64 calling convention and object layout.
The shim translates only the system services used by that runtime to documented
Win32 APIs. `WindowsImageBuilder` patches RIP-relative thunk jumps to the PE
import address table and packages managed literals in a separate writable data
section. The output has no Hydrogen runtime DLL dependency.

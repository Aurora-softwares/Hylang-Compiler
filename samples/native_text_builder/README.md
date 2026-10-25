# Native UTF-8 text builder

`TextBuilder.hy` is a reusable native Hydrogen class that appends UTF-8 bytes
to a growing `byte[]`. `ToString()` calls the native
`System.Text.Buffer.FromBytes(byte[], count)` intrinsic to create one immutable
string from the used prefix. Appends copy new bytes once; buffer growth doubles
capacity and copies existing bytes only when needed. The intrinsic rejects a
null array or a count outside `0..bytes.Length` with the native runtime's
existing error messages.

Build and run the example:

```bash
build/self_hosting/hydrogen-stage1 build samples/native_text_builder/NativeTextBuilder.hyproj -o build/native-text-builder
chmod +x build/native-text-builder
build/native-text-builder utf8 0
build/native-text-builder builder 10000
```

The `utf8` mode verifies that `AéZ` remains four UTF-8 bytes. `builder` and
`concat` build the same `abc` sequence and print live managed heap bytes and
the final byte length. The API is currently native only; the example class can
be included as a project source until a packaged standard library exists.

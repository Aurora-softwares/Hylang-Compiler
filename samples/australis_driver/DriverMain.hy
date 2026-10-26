// A minimal boot-time driver. The context is the KernelBootInfo address in
// AUDR ABI v1; returning zero reports successful initialization.
public class DriverMain {
    public static int Run(long context) {
        if (context < 4096) { return 1; }
        return 0;
    }
}

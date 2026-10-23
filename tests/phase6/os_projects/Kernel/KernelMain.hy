public class KernelMain {
    public static int Run(long bootInfo) {
        return 0;
    }
}

// Kernel images require a callable panic-QR entry, even in tiny OS fixtures.
namespace Australis.Kernel.Diagnostics {
    public class PanicQr {
        public static int Render(long bootInfo) {
            return 0;
        }
    }
}

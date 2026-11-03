using Hydrogen.UI;

namespace HydrogenNativeGtk {
    public class Program {
        public static int Main() {
            Window window = new Window("Hydrogen / native GTK4", 720, 420);
            window.SetTextAndButton("Built with Hydrogen - no C or C++ UI source", "Hydrogen");
            window.Show();
            System.Console.WriteLine("HYDROGEN_NATIVE_GTK_READY");
            window.Run();
            return 0;
        }
    }
}

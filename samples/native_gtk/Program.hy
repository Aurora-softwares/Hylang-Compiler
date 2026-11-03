using Hydrogen.UI;

namespace HydrogenNativeGtk {
    public class Program {
        public static int Main(string[] args) {
            Window window = new Window("Hydrogen / native GTK4", 720, 420);
            window.SetTextAndButton("Built with Hydrogen - no C or C++ UI source", "Hydrogen");
            window.Show();
            System.Console.WriteLine("HYDROGEN_NATIVE_GTK_READY");

            if (args.Length > 0 && args[0] == "--self-test-click") {
                window.EmitClickForTests();
                System.Console.WriteLine("HYDROGEN_NATIVE_GTK_SIGNAL_EMITTED");
                if (!window.PollClick()) { return 4; }
                window.SetLabelText("Clicked directly inside Hydrogen");
                System.Console.WriteLine("HYDROGEN_NATIVE_GTK_CLICKED");
                System.Console.WriteLine("HYDROGEN_NATIVE_GTK_BEFORE_CLOSE");
                window.Close();
                System.Console.WriteLine("HYDROGEN_NATIVE_GTK_AFTER_CLOSE");
                window.Release();
                System.Console.WriteLine("HYDROGEN_NATIVE_GTK_AFTER_RELEASE");
                return 0;
            }

            while (window.IsVisible()) {
                if (window.NextEvent()) {
                    window.SetLabelText("Clicked directly inside Hydrogen");
                    System.Console.WriteLine("HYDROGEN_NATIVE_GTK_CLICKED");
                }
            }
            window.Release();
            return 0;
        }
    }
}

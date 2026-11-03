namespace Hydrogen.UI {
    // GTK4 windows and their event loop are written in Hydrogen; the OS
    // toolkit is loaded by the Hydrogen compiler's dynamic ELF linker.
    public class Window {
        private static bool gtkReady = false;
        private long handle;
        private long contentLabel;
        private long actionButton;
        private int[] clickState;
        private bool retained;

        public Window(string title, int width, int height) {
            if (!gtkReady) {
                System.Native.Gtk.Init();
                gtkReady = true;
            }
            handle = System.Native.Gtk.WindowNew();
            System.Native.Gtk.WindowSetTitle(handle, title);
            System.Native.Gtk.WindowSetDefaultSize(handle, width, height);
            clickState = new int[1];
            contentLabel = 0;
            actionButton = 0;
            retained = false;
        }

        public void SetText(string text) {
            contentLabel = System.Native.Gtk.LabelNew(text);
            System.Native.Gtk.WindowSetChild(handle, contentLabel);
        }

        public void SetTextAndButton(string text, string action) {
            long container = System.Native.Gtk.BoxNew(1, 8);
            contentLabel = System.Native.Gtk.LabelNew(text);
            actionButton = System.Native.Gtk.ButtonNew(action);
            System.Native.Gtk.OnClick(actionButton, clickState);
            System.Native.Gtk.BoxAppend(container, contentLabel);
            System.Native.Gtk.BoxAppend(container, actionButton);
            System.Native.Gtk.WindowSetChild(handle, container);
        }

        public void SetLabelText(string text) {
            if (contentLabel != 0) {
                System.Native.Gtk.LabelSetText(contentLabel, text);
            }
        }

        public void Show() {
            if (!retained) {
                System.Native.Gtk.Ref(handle);
                retained = true;
            }
            System.Native.Gtk.WindowPresent(handle);
        }

        public bool IsVisible() {
            return System.Native.Gtk.WindowVisible(handle);
        }

        // The native GTK signal marks a Hydrogen int[] cell. The caller
        // processes the event in Hydrogen on the same GUI thread.
        public bool NextEvent() {
            if (clickState[0] != 0) {
                clickState[0] = 0;
                return true;
            }
            System.Native.Gtk.MainIteration();
            if (clickState[0] != 0) {
                clickState[0] = 0;
                return true;
            }
            return false;
        }

        public void Run() {
            Show();
            while (IsVisible()) {
                NextEvent();
            }
            Release();
        }

        // Deterministically exercise the same GTK callback as a real click.
        public void EmitClickForTests() {
            if (actionButton != 0) {
                System.Native.Gtk.EmitSignal(actionButton, "clicked");
            }
        }

        public void Close() {
            System.Native.Gtk.WindowDestroy(handle);
        }

        public void Release() {
            if (retained) {
                System.Native.Gtk.Unref(handle);
                retained = false;
            }
        }
    }
}

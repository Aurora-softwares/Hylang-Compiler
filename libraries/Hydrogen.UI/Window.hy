namespace Hydrogen.UI {
    // A native Linux GTK4 window managed entirely in Hydrogen.
    // GTK is a system library, not a source-language or launcher dependency.
    public class Window {
        private static bool gtkReady = false;
        private long handle;

        public Window(string title, int width, int height) {
            if (!gtkReady) {
                System.Native.Gtk.Init();
                gtkReady = true;
            }
            handle = System.Native.Gtk.WindowNew();
            System.Native.Gtk.WindowSetTitle(handle, title);
            System.Native.Gtk.WindowSetDefaultSize(handle, width, height);
        }

        public void SetText(string text) {
            System.Native.Gtk.WindowSetChild(handle, System.Native.Gtk.LabelNew(text));
        }

        public void SetTextAndButton(string text, string action) {
            // The first supported layout is a native vertical GTK box.
            // Signal callbacks and the wider HYUI vocabulary are next.
            long container = System.Native.Gtk.BoxNew(1, 8);
            System.Native.Gtk.BoxAppend(container, System.Native.Gtk.LabelNew(text));
            System.Native.Gtk.BoxAppend(container, System.Native.Gtk.ButtonNew(action));
            System.Native.Gtk.WindowSetChild(handle, container);
        }

        public void Show() {
            System.Native.Gtk.WindowPresent(handle);
        }

        public void Run() {
            // Keep a reference across the native close event. The default
            // close handler destroys the window; visibility then becomes false.
            System.Native.Gtk.Ref(handle);
            Show();
            while (System.Native.Gtk.WindowVisible(handle)) {
                System.Native.Gtk.MainIteration();
            }
            System.Native.Gtk.Unref(handle);
        }

        public void Close() {
            System.Native.Gtk.WindowDestroy(handle);
        }
    }
}

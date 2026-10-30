using System;
using System.IO;
using Hydrogen.UI;

namespace HydrogenStudio {
    public class Program {
        public static int Main(string[] args) {
            if (!Application.IsEvent(args)) {
                Application.Open("Studio.hyui");
                return 0;
            }
            string handler = Application.Handler(args);
            if (handler == "ShowControls") { Application.SetValue("pages", 1); }
            if (handler == "ShowWorkspace") { Application.SetValue("pages", 0); }
            if (handler == "About") { Application.SetOpen("about", true); }
            if (handler == "ChooseTemplate") { Application.SetText("selectionText", "Template index: " + Application.Value(args, "templates")); }
            if (handler == "ChooseProject") { Application.SetText("selectionText", "Project index: " + Application.Value(args, "projects")); }
            if (handler == "ChooseChannel") {
                string channel = "Stable";
                if (Application.Value(args, "channel") == "1") { channel = "Preview"; }
                if (Application.Value(args, "channel") == "2") { channel = "Nightly"; }
                Application.SetText("channelText", channel + " channel selected.");
            }
            if (handler == "Confirm") { Application.SetOpen("confirmation", true); }
            if (handler == "Confirmed") {
                if (Application.Value(args, "confirmation") == "0") { Application.SetText("dialogResult", "Confirmed. Your template is ready."); }
                else { Application.SetText("dialogResult", "Cancelled. Your settings are preserved."); }
            }
            if (handler == "Preview") {
                Application.SetText("summary", Summary(args));
            }
            if (handler == "Build") {
                string name = Application.Value(args, "projectName");
                if (name.Length == 0) {
                    Application.SetText("status", "Give your project a name before starting.");
                    return 0;
                }
                Application.SetValue("progress", 0);
                Application.SetText("status", "Preparing " + name + "...");
                Application.SetText("progressText", "0% / Preparing project");
                Application.SetRunning("buildTimer", true);
                Application.SetRunning("activity", true);
                Application.SetEnabled("build", false);
                Application.SetEnabled("cancel", true);
                Application.SetText("summary", Summary(args));
            }
            if (handler == "Tick") {
                int progress = System.Convert.ToInt32(Application.Value(args, "progress")) + 10;
                if (progress > 100) { progress = 100; }
                Application.SetValue("progress", progress);
                Application.SetText("progressText", "" + progress + "% / Creating application plan");
                if (progress == 100) {
                    Stop();
                    Application.SetText("status", "Your application plan is ready. Save it to get started.");
                    Application.SetText("progressText", "100% / Ready to save");
                    Application.SetEnabled("save", true);
                }
            }
            if (handler == "Cancel") {
                Stop();
                Application.SetText("status", "Cancelled. Change the settings and try again.");
                Application.SetText("progressText", "Paused / Your settings are preserved");
            }
            if (handler == "Save") {
                string path = Application.Value(args, "savePath");
                if (path.Length == 0) {
                    Application.SetText("status", "Enter a file path for the application plan.");
                    return 0;
                }
                System.IO.File.WriteAllText(path, Summary(args) + "\n\nNotes: " + Application.Value(args, "notes") + "\n");
                Application.SetText("status", "Saved application plan to " + path);
            }
            return 0;
        }

        private static string Summary(string[] args) {
            string target = "Linux desktop";
            string selection = Application.Value(args, "target");
            if (selection == "1") { target = "Windows / Fluent WinUI 3"; }
            if (selection == "2") { target = "macOS / system controls + glass"; }
            return Application.Value(args, "projectName") + "\n" + target +
                "\nOptimisation: " + Application.Value(args, "quality") + "%" +
                "\nDebug symbols: " + Application.Value(args, "symbols") +
                "\nResponsive layout: enabled";
        }

        private static void Stop() {
            Application.SetRunning("buildTimer", false);
            Application.SetRunning("activity", false);
            Application.SetEnabled("build", true);
            Application.SetEnabled("cancel", false);
        }
    }
}

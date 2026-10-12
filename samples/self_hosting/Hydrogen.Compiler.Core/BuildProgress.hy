namespace Hydrogen.Compiler.Core {
    public class BuildProgress {
        private bool showProgress;
        private bool showSpinner;
        private bool showLog;
        private bool terminal;
        private bool activeLine;
        private int frame;
        private int percent;
        private int lastLoggedPercent;
        private int completedSteps;
        private int totalSteps;
        private string action;
        private string detail;

        public BuildProgress(bool hideProgress, bool hideSpinner, bool hideLog) {
            showProgress = !hideProgress;
            showSpinner = !hideSpinner;
            showLog = !hideLog;
            terminal = System.Console.IsTerminal();
            activeLine = false;
            frame = 0;
            percent = 0;
            lastLoggedPercent = 0;
            completedSteps = 0;
            totalSteps = 0;
            action = "";
            detail = "";
        }

        public void Start(string project, int steps) {
            Stop();
            frame = 0;
            completedSteps = 0;
            totalSteps = steps;
            if (showLog) { System.Console.WriteLine("Building " + project); }
        }

        public void Begin(string message) {
            if (action != "") { Step(action); }
            action = message;
            detail = "";
            percent = 0;
            lastLoggedPercent = 0;
            DrawActive();
        }

        // Progress is measured within the current action, never across the build.
        public void Update(int done, int total, string status) {
            if (action == "") { return; }
            if (total > 0) {
                int measured = done * 100 / total;
                if (measured > 99) { measured = 99; }
                if (measured > percent) { percent = measured; }
            }
            detail = status;
            if (!terminal && showLog && percent >= lastLoggedPercent + 10) {
                System.Console.WriteLine(status + " (" + percent + "%)");
                lastLoggedPercent = percent;
            }
            DrawActive();
        }

        // An action without a known denominator can still report useful work.
        public void Pulse(string status) {
            if (action == "") { return; }
            detail = status;
            if (!terminal && showLog) { System.Console.WriteLine(status); }
            DrawActive();
        }

        // Replace the live line with the action's final result; print it once.
        public void Step(string message) {
            ClearActive();
            if (completedSteps < totalSteps) { completedSteps = completedSteps + 1; }
            if (showProgress) { System.Console.WriteLine("100% " + message); }
            else if (showLog) { System.Console.WriteLine(message); }
            if (terminal && showProgress && totalSteps > 0 && completedSteps == totalSteps) {
                string bar = "[";
                int i = 0;
                while (i < 60) { bar = bar + "#"; i = i + 1; }
                System.Console.WriteLine(bar + "] 100% total");
            }
            action = "";
            detail = "";
            percent = 0;
        }

        public void Stop() {
            ClearActive();
            action = "";
            detail = "";
        }

        public bool ReportsResult() {
            return showProgress || showLog;
        }

        private void ClearActive() {
            if (!terminal || !activeLine) { return; }
            byte[] clear = new byte[5];
            clear[0] = (byte)13;
            clear[1] = (byte)27;
            clear[2] = (byte)91;
            clear[3] = (byte)50;
            clear[4] = (byte)75;
            System.Console.WriteBytes(clear);
            activeLine = false;
        }

        private void DrawActive() {
            if (!terminal || action == "" || (!showProgress && !showSpinner)) { return; }
            ClearActive();
            if (showSpinner) {
                // Braille U+2800..U+28FF, emitted as bytes for the native backend.
                byte[] glyph = new byte[3];
                glyph[0] = (byte)226;
                glyph[1] = (byte)160;
                int[] finalBytes = new int[10];
                finalBytes[0] = 139; finalBytes[1] = 153; finalBytes[2] = 185;
                finalBytes[3] = 184; finalBytes[4] = 188; finalBytes[5] = 180;
                finalBytes[6] = 166; finalBytes[7] = 167; finalBytes[8] = 135;
                finalBytes[9] = 143;
                glyph[2] = (byte)finalBytes[frame % 10];
                System.Console.WriteBytes(glyph);
                System.Console.Write(" ");
                frame = frame + 1;
            }
            if (showProgress) {
                int totalPercent = 0;
                if (totalSteps > 0) { totalPercent = completedSteps * 100 / totalSteps; }
                int filled = totalPercent * 60 / 100;
                string bar = "[";
                int i = 0;
                while (i < 60) {
                    if (i < filled) { bar = bar + "#"; }
                    else { bar = bar + "-"; }
                    i = i + 1;
                }
                System.Console.Write(bar + "] " + totalPercent + "% total | " + percent + "% ");
            }
            System.Console.Write(action);
            if (detail != "") { System.Console.Write(" (" + detail + ")"); }
            activeLine = true;
        }
    }
}

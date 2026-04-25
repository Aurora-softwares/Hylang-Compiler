namespace Hydrogen.Compiler.IR {
    public class IrProgram {
        private string message;
        private int exitCode;

        public IrProgram(string inputMessage, int inputExitCode) {
            message = inputMessage;
            exitCode = inputExitCode;
        }

        public string Message() {
            return message;
        }

        public int ExitCode() {
            return exitCode;
        }

        public string ToDebugText() {
            return "Program.WriteLine(\"" + message + "\") return " + exitCode;
        }
    }
}

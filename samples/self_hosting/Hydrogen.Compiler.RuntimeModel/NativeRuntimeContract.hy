namespace Hydrogen.Compiler.RuntimeModel {
    public class NativeRuntimeContract {
        public string TargetName() {
            return "linux-x64-elf";
        }

        public string ObjectModelVersion() {
            return "phase6c-direct-entrypoint";
        }

        public string Describe() {
            return TargetName() + " " + ObjectModelVersion();
        }
    }
}

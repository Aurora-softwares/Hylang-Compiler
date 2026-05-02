namespace Hydrogen.Compiler.RuntimeModel {
    public class NativeRuntimeContract {
        public string TargetName() {
            return "linux-x64-elf";
        }

        public string ObjectModelVersion() {
            return "phase6b-stage1-skeleton";
        }

        public string Describe() {
            return TargetName() + " " + ObjectModelVersion();
        }
    }
}

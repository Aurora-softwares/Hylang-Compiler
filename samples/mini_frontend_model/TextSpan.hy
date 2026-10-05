namespace MiniFrontendModel {
    public interface ISpanView {
        int Start();
        int Length();
    }

    public struct TextSpan : ISpanView {
        private int start;
        private int length;

        public TextSpan(int inputStart, int inputLength) {
            start = inputStart;
            length = inputLength;
        }

        public int Start() {
            return start;
        }

        public int Length() {
            return length;
        }
    }
}

namespace Hydrogen.Compiler.Syntax {
    public class SyntaxTokenList {
        private SyntaxToken[] items;
        private int count;

        public SyntaxTokenList() {
            items = new SyntaxToken[16];
            count = 0;
        }

        public void Add(SyntaxToken token) {
            if (count >= items.Length) {
                Grow();
            }
            items[count] = token;
            count = count + 1;
        }

        public int Count() {
            return count;
        }

        public SyntaxToken Get(int index) {
            return items[index];
        }

        private void Grow() {
            int newSize = items.Length * 2;
            SyntaxToken[] next = new SyntaxToken[newSize];
            int i = 0;
            while (i < items.Length) {
                next[i] = items[i];
                i = i + 1;
            }
            items = next;
        }
    }
}

namespace Alpha {
    public class Token {
        public int value;
        public Token(int input) { value = input; }
        private int Read() { return value; }
        public int Get() { return Read(); }
    }
    public class Factory {
        public static Token Make() { return new Token(20); }
    }
}

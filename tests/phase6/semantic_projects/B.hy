namespace Beta {
    public class Token {
        public int value;
        public Token(int input) { value = input; }
        public int Get() { return value; }
    }
    public class Factory {
        public static Token Make() { return new Token(22); }
    }
}

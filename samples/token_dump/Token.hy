using System;

namespace TokenDump {
    public class Token {
        public TokenKind Kind;
        public string Lexeme;
        public int Line;
        public int Column;

        public Token(TokenKind kind, string lexeme, int line, int column) {
            Kind = kind;
            Lexeme = lexeme;
            Line = line;
            Column = column;
        }

        public void Print() {
            Console.Write(Line);
            Console.Write(":");
            Console.Write(Column);
            Console.Write(" ");
            Console.Write(Kind);
            Console.Write(" ");
            Console.WriteLine(Lexeme);
        }
    }
}

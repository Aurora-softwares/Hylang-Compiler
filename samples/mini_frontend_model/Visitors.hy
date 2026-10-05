namespace MiniFrontendModel {
    public interface ISyntaxVisitor<T> {
        T VisitLiteral(LiteralExpressionSyntax node);
        T VisitBinary(BinaryExpressionSyntax node);
    }

    public class PrettyPrinter : ISyntaxVisitor<string> {
        public string VisitLiteral(LiteralExpressionSyntax node) {
            return node.Text();
        }

        public string VisitBinary(BinaryExpressionSyntax node) {
            return node.Left().Text() + node.OperatorText() + node.Right().Text();
        }
    }

    public class Box<T> {
        private T value;

        public Box(T input) {
            value = input;
        }

        public T Value() {
            return value;
        }
    }
}

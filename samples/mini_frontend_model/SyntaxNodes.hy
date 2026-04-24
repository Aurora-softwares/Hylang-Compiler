namespace MiniFrontendModel {
    public enum SyntaxKind {
        LiteralExpression,
        BinaryExpression
    }

    public class SyntaxNode {
        protected TextSpan span;

        public SyntaxNode(TextSpan inputSpan) {
            span = inputSpan;
        }

        public TextSpan Span() {
            return span;
        }

        public virtual SyntaxKind Kind() {
            return SyntaxKind.LiteralExpression;
        }

        public string SpanText() {
            return span.Start() + ":" + span.Length();
        }
    }

    public class LiteralExpressionSyntax : SyntaxNode {
        private string text;

        public LiteralExpressionSyntax(TextSpan inputSpan, string inputText) : base(inputSpan) {
            text = inputText;
        }

        public override SyntaxKind Kind() {
            return SyntaxKind.LiteralExpression;
        }

        public string Text() {
            return text;
        }
    }

    public class BinaryExpressionSyntax : SyntaxNode {
        private LiteralExpressionSyntax left;
        private string op;
        private LiteralExpressionSyntax right;

        public BinaryExpressionSyntax(TextSpan inputSpan,
                                      LiteralExpressionSyntax inputLeft,
                                      string inputOp,
                                      LiteralExpressionSyntax inputRight) : base(inputSpan) {
            left = inputLeft;
            op = inputOp;
            right = inputRight;
        }

        public override SyntaxKind Kind() {
            return SyntaxKind.BinaryExpression;
        }

        public SyntaxKind BaseKind() {
            return base.Kind();
        }

        public string Visit(ISyntaxVisitor<string> visitor) {
            return visitor.VisitBinary(this);
        }

        public LiteralExpressionSyntax Left() {
            return left;
        }

        public string OperatorText() {
            return op;
        }

        public LiteralExpressionSyntax Right() {
            return right;
        }
    }
}

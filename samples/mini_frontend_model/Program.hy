using MiniFrontendModel;

public class Program {
    public static void Main(string[] args) {
        TextSpan span = new TextSpan(0, 5);
        LiteralExpressionSyntax left = new LiteralExpressionSyntax(new TextSpan(0, 1), "1");
        LiteralExpressionSyntax right = new LiteralExpressionSyntax(new TextSpan(4, 1), "2");
        BinaryExpressionSyntax root = new BinaryExpressionSyntax(span, left, "+", right);
        SyntaxNode rootNode = root;
        ISyntaxVisitor<string> visitor = new PrettyPrinter();
        Box<SyntaxNode> box = new Box<SyntaxNode>(root);
        ISpanView spanView = span;

        System.Console.Write("Root=");
        System.Console.WriteLine(rootNode.Kind());
        System.Console.Write("Span=");
        System.Console.WriteLine(root.SpanText());
        System.Console.Write("Visit=");
        System.Console.WriteLine(root.Visit(visitor));
        System.Console.Write("Box=");
        System.Console.WriteLine(box.Value().Kind());
        System.Console.Write("SpanView=");
        System.Console.Write(spanView.Start());
        System.Console.Write(":");
        System.Console.WriteLine(spanView.Length());
    }
}

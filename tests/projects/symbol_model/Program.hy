using Compiler.Symbols;

public class Program {
    public static string Describe(Symbol symbol) {
        return symbol.Kind() + ":" + symbol.Depth();
    }

    public static void Main(string[] args) {
        TypeSymbol type = new TypeSymbol("Node");
        MethodSymbol method = new MethodSymbol("Parse", 2);
        Symbol baseType = type;

        System.Console.Write(baseType.Kind());
        System.Console.Write(":");
        System.Console.Write(type.Name());
        System.Console.Write(":");
        System.Console.Write(type.Depth());
        System.Console.Write(":");
        System.Console.Write(Describe(method));
        System.Console.Write(":");
        System.Console.WriteLine(method.ParameterCount());
    }
}

using Services;
public class Program {
    public static int Main() {
        var left = Left.Make();
        var right = Right.Make();
        Alpha.Token[] values = new Alpha.Token[1];
        values[0] = left;
        left.value = values[0].Get();
        int count = 0;
        while (count < 1) { count = count + 1; }
        if (count != 1) { return 90; }
        { int count = 5; if (count != 5) { return 91; } }
        if (count != 1) { return 92; }
        System.Console.WriteLine("project semantics and executable IR ok");
        return left.Get() + right.Get();
    }
}

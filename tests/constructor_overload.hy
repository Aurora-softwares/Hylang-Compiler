public class Box {
    private int value;

    public Box(string text) {
        value = 1;
    }

    public Box(bool enabled) {
        value = 2;
    }

    public int Value() {
        return value;
    }
}

public class Program {
    public static void Main(string[] args) {
        Box first = new Box("demo");
        Box second = new Box(true);
        System.Console.WriteLine(first.Value());
        System.Console.WriteLine(second.Value());
    }
}

public interface IValue {
    int Value();
}

public struct Number : IValue {
    private int value;

    public Number(int input) {
        value = input;
    }

    public int Value() {
        return value;
    }
}

public class Program {
    public static void Main(string[] args) {
        var number = new Number(7);
        IValue value = number;
        System.Console.WriteLine(value.Value());
    }
}

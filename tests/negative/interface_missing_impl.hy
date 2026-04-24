public interface IValue {
    int Value();
}

public class Missing : IValue {
}

public class Program {
    public static void Main(string[] args) {
        IValue value = new Missing();
        System.Console.WriteLine(value.Value());
    }
}

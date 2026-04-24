public class Box<T> {
    public Box(T input) {
    }
}

public class Program {
    public static void Main(string[] args) {
        Box<string, string> value = new Box<string, string>("x");
        System.Console.WriteLine("nope");
    }
}

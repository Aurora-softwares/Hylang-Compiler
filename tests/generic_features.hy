public class Box<T> {
    private T value;

    public Box(T input) {
        value = input;
    }

    public T Value() {
        return value;
    }
}

public class Program {
    public static T Identity<T>(T value) {
        return value;
    }

    public static void Main(string[] args) {
        Box<string> box = new Box<string>("ok");
        string value = box.Value();
        string same = Identity(value);
        System.Console.WriteLine(same);
    }
}

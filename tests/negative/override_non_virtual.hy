public class Base {
    public int Read() {
        return 1;
    }
}

public class Derived : Base {
    public override int Read() {
        return 2;
    }
}

public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine(new Derived().Read());
    }
}

public class Base {
    public int Read() {
        return 1;
    }
}

public class Derived : Base {
    public static int ReadBase() {
        return base.Read();
    }
}

public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine(Derived.ReadBase());
    }
}

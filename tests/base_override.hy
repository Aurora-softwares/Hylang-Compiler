public class Root {
    protected int value;

    public Root(int input) {
        value = input;
    }

    public virtual int Read() {
        return value;
    }
}

public class Child : Root {
    public Child(int input) : base(input + 1) {
    }

    public override int Read() {
        return base.Read() + 1;
    }

    public int BaseRead() {
        return base.Read();
    }
}

public class Program {
    public static void Main(string[] args) {
        Root value = new Child(4);
        Child child = new Child(4);

        System.Console.Write(value.Read());
        System.Console.Write(":");
        System.Console.WriteLine(child.BaseRead());
    }
}

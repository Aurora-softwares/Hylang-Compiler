public class Root {
    public static int Order;

    public Root() {
        Order = Order * 10 + 1;
    }
}

public class Mid : Root {
    public Mid() {
        Order = Order * 10 + 2;
    }
}

public class Leaf : Mid {
    public Leaf() {
        Order = Order * 10 + 3;
    }
}

public class Program {
    public static void Main(string[] args) {
        Leaf leaf = new Leaf();
        System.Console.WriteLine(Root.Order);
    }
}

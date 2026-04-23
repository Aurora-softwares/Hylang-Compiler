public class Root {
    public int Count(int value) {
        return value;
    }
}

public class Leaf : Root {
    public int Count(int value) {
        return value + 1;
    }
}

public class Program {
    public static void Main(string[] args) {
    }
}

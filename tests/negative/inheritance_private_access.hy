public class Root {
    private int secret;

    public Root() {
        secret = 9;
    }
}

public class Leaf : Root {
    public int Read() {
        return secret;
    }
}

public class Program {
    public static void Main(string[] args) {
    }
}

public struct Pair {
    private int left;
    private string label;

    public Pair(int value, string text) {
        left = value;
        label = text;
    }

    public int Left() {
        return left;
    }

    public string Label() {
        return label;
    }
}

public class Node {
    private string name;

    public Node(string value) {
        name = value;
    }

    public string Name() {
        return name;
    }
}

public class Program {
    public static void Main() {
        int[] numbers = new int[5];
        numbers[0] = 7;

        string[] names = new string[3];
        names[1] = "byte";

        Node[] nodes = new Node[4];
        nodes[2] = new Node("ok");

        Pair[] pairs = new Pair[2];
        pairs[0] = new Pair(9, "pair");

        System.Console.Write("Ints=");
        System.Console.WriteLine(numbers[0]);
        System.Console.Write("Strings=");
        System.Console.WriteLine(names[1].Length);
        System.Console.Write("Nodes=");
        System.Console.WriteLine(nodes[2].Name());
        System.Console.Write("Pairs=");
        System.Console.WriteLine(pairs[0].Left());
        System.Console.Write("Len=");
        System.Console.WriteLine(nodes.Length);
    }
}

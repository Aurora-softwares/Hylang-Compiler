public enum Mode { Slow = 17, Fast }
public class DefaultState {
    private int count = 5;
    private string name = "initial";
    public string Describe() { return name + count; }
}
public class Node {
    private int value = 5;
    private string name;
    private Node next;
    public Node(int input, string text) { this.value = input; name = text; }
    public string Describe() { return name + ":" + value; }
    public int Add(int amount) { value = value + amount; return value; }
    public void Link(Node input) { next = input; }
    public Node Next() { return next; }
}
public class Program {
    public static Mode Echo(Mode value) { return value; }
    public static int Main(string[] args) {
        string empty = "";
        string anotherEmpty = "";
        string allocatedEmpty = empty + anotherEmpty;
        if (empty != anotherEmpty || allocatedEmpty != empty) { return 86; }
        if (empty == "x" || empty == null || null == allocatedEmpty) { return 87; }
        DefaultState initial = new DefaultState();
        if (initial.Describe() != "initial5") { return 96; }
        Mode mode = Mode.Fast;
        if ((int)Echo(mode) != 18) { return 97; }
        int loop = 0;
        int sum = 0;
        while (loop < 5) {
            loop = loop + 1;
            if (loop == 3) { continue; }
            if (loop == 4) { break; }
            sum = sum + loop;
        }
        if (sum != 3) { return 98; }
        Node first = new Node(7, "node");
        Node second = new Node(9, "tail");
        first.Link(second);
        if (first.Add(3) != 10) { return 90; }
        System.Console.WriteLine(first.Describe());
        System.Console.WriteLine(first.Next().Describe());
        string text = "ab" + "cd";
        if (text.Length != 4 || text[2] != "c" || text != "abcd") { return 91; }
        string[] names = new string[3];
        names[1] = text;
        Node[] nodes = new Node[2];
        nodes[0] = first;
        if (names[1] != "abcd" || nodes[0].Add(1) != 11) { return 92; }
        System.Console.WriteLine(args.Length);
        System.Console.WriteLine(args[0]);
        Node untouched = new Node(1, "default");
        if (untouched.Describe() != "default:1") { return 93; }
        if (first == second || first.Next() != second) { return 94; }
        bool[] flags = new bool[2];
        flags[0] = true;
        if (!flags[0] || flags[1]) { return 95; }
        System.Runtime.GC.Collect();
        System.Console.WriteLine(first.Describe());
        return 42;
    }
}

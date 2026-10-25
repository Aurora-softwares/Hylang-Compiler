public class Node { public int value; public Node next; }
public class Program {
    public static int Make(int n) {
        Node head = null;
        int i = 0;
        while (i < n) {
            Node item = new Node();
            item.value = i;
            item.next = head;
            head = item;
            i = i + 1;
        }
        return i;
    }
    public static int Main(string[] args) {
        int n = System.Convert.ToInt32(args[1]);
        int count = Make(n);
        if (args[0] == "collect") { System.Runtime.GC.Collect(); }
        System.Console.WriteLine(count);
        System.Console.WriteLine(System.Runtime.GC.GetAllocatedBytes());
        return 0;
    }
}

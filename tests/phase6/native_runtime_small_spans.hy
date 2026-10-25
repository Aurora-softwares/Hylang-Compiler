public class Link {
    public int value;
    public Link next;
    public Link(int input, Link tail) { value = input; next = tail; }
}

public class Program {
    public static int Main() {
        Link head = null;
        int i = 0;
        while (i < 12000) {
            head = new Link(i, head);
            i = i + 1;
        }
        // Twelve thousand small objects must occupy shared pages, not one
        // mapped page each. Include runtime metadata in the generous limit.
        if (System.Runtime.GC.GetAllocatedBytes() > 2097152) { return 91; }
        System.Runtime.GC.Collect();
        Link current = head;
        int expected = 11999;
        while (current != null) {
            if (current.value != expected) { return 92; }
            expected = expected - 1;
            current = current.next;
        }
        if (expected != -1) { return 93; }
        head = null;
        current = null;
        System.Runtime.GC.Collect();
        if (System.Runtime.GC.GetAllocatedBytes() > 262144) { return 94; }
        System.Console.WriteLine("small spans ok");
        return 42;
    }
}

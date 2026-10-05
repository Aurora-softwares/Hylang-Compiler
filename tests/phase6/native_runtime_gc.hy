public class Link {
    public int value;
    public Link next;
    public Link(int input, Link tail) { value = input; next = tail; }
}

public class Program {
    public static int[] FreshPages() { return new int[2048]; }
    public static int CollectValue() { System.Runtime.GC.Collect(); return 77; }
    public static int Main() {
        // Collection also works before the first allocation and on an empty heap.
        System.Runtime.GC.Collect();
        // The assignment keeps an interior pointer in a later allocation page
        // alive while evaluating a right-hand side that forces collection.
        FreshPages()[1500] = CollectValue();
        int[] pages = new int[2048];
        pages[0] = 11;
        pages[1024] = 22;
        pages[2047] = 33;
        Link head = null;
        int i = 0;
        while (i < 350) {
            head = new Link(i, head);
            i = i + 1;
        }
        i = 0;
        while (i < 1000) {
            Link garbage = new Link(-1, null);
            i = i + 1;
        }
        System.Runtime.GC.Collect();
        if (pages[0] != 11 || pages[1024] != 22 || pages[2047] != 33) { return 94; }
        int seen = 0;
        while (head != null) {
            if (head.value != 349 - seen) { return 90; }
            head = head.next;
            seen = seen + 1;
        }
        if (seen != 350) { return 91; }
        // Children allocated after their parents exercise deep tracing without
        // depending on allocation-list order or repeated whole-heap passes.
        Link root = new Link(0, null);
        Link tail = root;
        i = 1;
        while (i < 2500) {
            Link child = new Link(i, null);
            tail.next = child;
            tail = child;
            i = i + 1;
        }
        System.Runtime.GC.Collect();
        i = 0;
        while (root != null) {
            if (root.value != i) { return 95; }
            root = root.next;
            i = i + 1;
        }
        if (i != 2500) { return 96; }
        tail = null;
        System.Runtime.GC.Collect();
        if (System.Runtime.GC.GetAllocatedBytes() > 524288) { return 92; }
        Link first = new Link(1, null);
        Link second = new Link(2, first);
        first.next = second;
        System.Runtime.GC.Collect();
        if (first.next.next != first || second.next.value != 1) { return 93; }
        System.Console.WriteLine("heap graphs and cycles ok");
        return 42;
    }
}

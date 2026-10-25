public class Box {
    public Box next;
    public string name;
    public int number;
    public Box Link(string value) { name = value; return this; }
}

public class Program {
    private static int receivers;
    private static int arguments;
    private static int indices;

    private static Box Receiver(Box value) { receivers = receivers + 1; return value; }
    private static string Argument() {
        arguments = arguments + 1;
        System.Runtime.GC.Collect();
        return "linked";
    }
    private static int Index() { indices = indices + 1; return 0; }

    public static int Main() {
        Box none = null;
        Box item = new Box();
        item.next = new Box();
        item.name = "ready";
        Box missingField = Receiver(none)?.next;
        if (missingField != null || receivers != 1) { return 11; }
        Box foundField = Receiver(item)?.next;
        if (foundField != item.next || receivers != 2) { return 12; }
        Box missingCall = Receiver(none)?.Link(Argument());
        if (missingCall != null || receivers != 3 || arguments != 0) { return 13; }
        Box foundCall = Receiver(item)?.Link(Argument());
        if (foundCall != item || receivers != 4 || arguments != 1 || item.name != "linked") { return 14; }
        Box ephemeral = Receiver(new Box())?.Link(Argument());
        if (ephemeral == null || ephemeral.name != "linked" || receivers != 5 || arguments != 2) { return 20; }
        Box[] empty = null;
        Box[] values = new Box[1];
        values[0] = item;
        Box missingIndex = empty?[Index()];
        if (missingIndex != null || indices != 0) { return 15; }
        Box foundIndex = values?[Index()];
        if (foundIndex != item || indices != 1) { return 16; }
        string absent = null;
        string missingChar = absent?[Index()];
        if (missingChar != null || indices != 1) { return 17; }
        string firstChar = "hello"?[Index()];
        if (firstChar != "h" || indices != 2) { return 18; }
        Box chained = none?.next?.next;
        if (chained != null) { return 19; }
        return 42;
    }
}

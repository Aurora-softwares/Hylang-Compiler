public class Program {
    private static int order;
    private static int[] Source() {
        order = order * 10 + 1;
        int[] values = new int[4];
        values[0] = 3; values[1] = 5; values[2] = 7; values[3] = 9;
        return values;
    }
    private static int Start() { order = order * 10 + 2; return 1; }
    private static int End() { order = order * 10 + 3; return 3; }

    public static int Main() {
        int[] part = Source()[Start()..End()];
        if (order != 123 || part.Length != 2 || part[0] != 5 || part[1] != 7) { return 11; }
        part[0] = 12;
        if (part[0] != 12) { return 12; }

        byte[] bytes = new byte[3];
        bytes[0] = 10; bytes[1] = 20; bytes[2] = 30;
        byte[] bytePart = bytes[1..3];
        bytes[1] = 99;
        if (bytePart.Length != 2 || bytePart[0] != 20 || bytePart[1] != 30) { return 13; }

        string[] names = new string[2];
        names[0] = "a"; names[1] = "b";
        string[] namePart = names[0..1];
        names[0] = "c";
        if (namePart.Length != 1 || namePart[0] != "a") { return 14; }

        string text = "éx";
        if (text[0..2] != "é" || text[2..3] != "x" || text[3..3] != "") { return 15; }
        if (text[0..text.Length] != text) { return 16; }
        int[] empty = part[2..2];
        if (empty.Length != 0) { return 17; }
        return 42;
    }
}

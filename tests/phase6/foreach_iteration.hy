public class Program {
    private static int collections;

    private static int[] Values() {
        collections = collections + 1;
        int[] values = new int[4];
        values[0] = 1;
        values[1] = 2;
        values[2] = 3;
        values[3] = 4;
        return values;
    }

    public static int Main() {
        int total = 0;
        int[] values = Values();
        foreach (int value in values) {
            if (value == 1) { values[1] = 8; }
            if (value == 3) { continue; }
            if (value == 4) { break; }
            total = total + value;
        }
        if (total != 9 || collections != 1) { return 11; }

        int seen = 0;
        foreach (var value in Values()) { seen = seen + value; }
        if (seen != 10 || collections != 2) { return 12; }

        string word = "abc";
        string joined = "";
        foreach (string letter in word) { joined = joined + letter; }
        if (joined != word) { return 13; }

        int[] pair = new int[2];
        pair[0] = 2;
        pair[1] = 3;
        int nested = 0;
        foreach (int outer in pair) {
            foreach (int inner in pair) { nested = nested + outer * inner; }
        }
        if (nested != 25) { return 15; }

        int[] empty = new int[0];
        foreach (int value in empty) { return 16; }
        return 42;
    }
}

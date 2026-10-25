using System.Collections;

public class Program {
    private static int collections;

    private static List<int> Create() {
        collections = collections + 1;
        List<int> result = new List<int>();
        result.Add(1);
        result.Add(2);
        result.Add(3);
        return result;
    }

    public static int Main() {
        List<int> numbers = Create();
        int total = 0;
        foreach (int value in numbers) {
            if (value == 1) { numbers.Set(1, 8); }
            if (value == 8) { numbers.Add(4); }
            total = total + value;
        }
        if (total != 16 || numbers.Count() != 4 || collections != 1) { return 11; }
        int second = 0;
        foreach (var value in Create()) { second = second + value; }
        if (second != 6 || collections != 2) { return 12; }
        return 42;
    }
}

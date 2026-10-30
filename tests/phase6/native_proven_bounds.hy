public class Program {
    public static int Main() {
        byte[] bytes = new byte[4];
        int i = 0;
        while (i < bytes.Length) { bytes[i] = (byte)(i + 1); i = i + 1; }
        int sum = 0;
        i = 0;
        while (i < bytes.Length) { sum = sum + bytes[i]; i = i + 1; }

        int n = 4;
        int[] numbers = new int[n];
        i = 0;
        while (i < n) { numbers[i] = i + 1; i = i + 1; }
        i = 0;
        while (i < n) { sum = sum + numbers[i]; i = i + 1; }

        for (int j = 0; j < bytes.Length; j = j + 1) { sum = sum + bytes[j]; }
        if (sum != 30) { return 1; }
        string text = "E\nI\nE\n";
        int matches = 0;
        i = 0;
        while (i < text.Length) {
            string ch = text[i];
            if (ch == "E") { matches = matches + 1; }
            if (ch == "\n") { sum = sum + 1; }
            i = i + 1;
        }
        if (matches != 2 || sum != 33) { return 2; }
        int[] values = new int[6];
        i = 0;
        while (i < values.Length) {
            values[i] = (i * 17 + 3) % 1000003;
            i = i + 1;
        }
        int total = 5;
        i = 0;
        while (i < values.Length) {
            total = total + (values[i] % 97);
            i = i + 1;
        }
        if (total != 278) { return 3; }
        int empty = 0;
        int unchanged = 11;
        i = 0;
        while (i < empty) { unchanged = unchanged + 1; i = i + 1; }
        if (unchanged != 11 || i != 0) { return 4; }
        int state = 1;
        int aggregate = 0;
        int count = 6;
        i = 0;
        while (i < count) {
            state = (state * 17 + (i % 13) + 11) % 1000003;
            aggregate = aggregate + (state % 97);
            i = i + 1;
        }
        if (state != 826314 || aggregate != 263) { return 5; }
        System.Console.WriteLine("proven bounds ok");
        return 42;
    }
}

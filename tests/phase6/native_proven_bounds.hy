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
        System.Console.WriteLine("proven bounds ok");
        return 42;
    }
}

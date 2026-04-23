public class Program {
    public static void Main(string[] args) {
        int count = 0;
        for (int i = 0; i < 6; i = i + 1) {
            if (i % 2 == 1) {
                count = count + 1;
            }
        }

        System.Console.WriteLine(count);
    }
}

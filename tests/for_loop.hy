public class Program {
    public static void Main(string[] args) {
        int sum = 0;
        for (int i = 0; i < 6; i = i + 1) {
            if (i == 1) {
                continue;
            }
            if (i == 5) {
                break;
            }
            sum = sum + i;
        }

        System.Console.WriteLine(sum);
    }
}

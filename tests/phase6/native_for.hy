public class Program {
    public static int Main(string[] args) {
        int sum = 0;
        for (int i = 0; i < 6; i = i + 1) {
            if (i == 2) {
                continue;
            }
            sum = sum + i;
            if (i == 4) {
                break;
            }
        }
        System.Console.WriteLine(sum);
        return sum;
    }
}

public class Program {
    public static int Main(string[] args) {
        int n = System.Convert.ToInt32(args[0]);
        int a = 1;
        int b = 3;
        int c = 5;
        int i = 0;
        while (i < n) {
            a = a + b;
            b = b ^ c;
            c = c * a;
            a = a & c;
            b = b | a;
            i = i + 1;
        }
        System.Console.WriteLine(a + b + c);
        return 0;
    }
}

public class Program {
    public static int Sum(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
        return a + b + c + d + e + f + g + h + i;
    }

    public static int Main() {
        int a = 1;
        int b = 2;
        int c = 3;
        int d = 4;
        int e = 5;
        int f = 6;
        int g = 7;
        int h = 8;
        int i = 9;
        i = i + 1;
        System.Console.WriteLine(Sum(a, b, c, d, e, f, g, h, i));
        return 0;
    }
}

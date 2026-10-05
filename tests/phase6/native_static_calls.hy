public class Program {
    public static int Main(string[] args) {
        int saved = 17;
        Announce();
        int result = Pack(Identity(1), Identity(2), Identity(3), Identity(4), Identity(5), Factorial(3), Identity(7), Identity(8));
        if (result != 204 || saved != 17) { return 90; }
        if (Factorial(5) != 120 || Fibonacci(8) != 21) { return 91; }
        if (!IsEven(12) || IsEven(11)) { return 92; }
        if (IdentityBool(false) && UnexpectedCall()) { return 93; }
        if (!(IdentityBool(true) || UnexpectedCall())) { return 94; }
        if (Quotient(-17, 5) != -3 || Remainder(-17, 5) != -2) { return 95; }
        if (SumTo(5) != 15) { return 96; }
        if (SumTo(saved) != 153 || saved != 17) { return 100; }
        int first = 0;
        if (Pack(first = first + 1, first = first + 1, first = first + 1, first = first + 1, first = first + 1, first = first + 1, first = first + 1, first = first + 1) != 204) { return 97; }
        {
            int saved = 99;
            if (Identity(saved) != 99) { return 98; }
        }
        if (saved != 17) { return 99; }
        System.Console.WriteLine("static calls and recursion ok");
        return 42;
    }

    public static void Announce() {
        System.Console.WriteLine("helper returned to caller");
        return;
        System.Console.WriteLine("unreachable helper output");
    }

    public static int Pack(int a, int b, int c, int d, int e, int f, int g, int h) {
        return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8;
    }

    public static int Identity(int value) { return value; }
    public static bool IdentityBool(bool value) { return value; }
    public static int Quotient(int a, int b) { return a / b; }
    public static int Remainder(int a, int b) { return a % b; }

    public static int Factorial(int n) {
        if (n <= 1) { return 1; }
        return n * Factorial(n - 1);
    }

    public static int Fibonacci(int n) {
        if (n <= 1) { return n; }
        return Fibonacci(n - 1) + Fibonacci(n - 2);
    }

    public static bool IsEven(int n) {
        if (n == 0) { return true; }
        return IsOdd(n - 1);
    }

    public static bool IsOdd(int n) {
        if (n == 0) { return false; }
        return IsEven(n - 1);
    }

    public static int SumTo(int n) {
        int sum = 0;
        while (n > 0) {
            sum = sum + n;
            n = n - 1;
        }
        return sum;
    }

    public static bool UnexpectedCall() {
        System.Console.WriteLine("short circuit failed");
        return true;
    }
}

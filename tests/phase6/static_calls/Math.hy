namespace NativeMath {
    public class Calculator {
        public static int Add(int left, int right) { return left + right; }
        public static int Factorial(int n) {
            if (n <= 1) { return 1; }
            return n * Factorial(n - 1);
        }
    }
}

namespace OtherMath {
    public class Calculator {
        public static int Value() { return 18; }
    }
}

using NativeMath;

namespace NativeApp {
    public class Program {
        public static int Main(string[] args) {
            int result = Calculator.Add(Calculator.Factorial(4), OtherMath.Calculator.Value());
            if (result != 42) { return 99; }
            System.Console.WriteLine("project static calls ok");
            return result;
        }
    }
}

namespace Demo {
    public enum Left {
        One
    }

    public enum Right {
        One
    }

    public class Program {
        public static void Main(string[] args) {
            bool same = Left.One == Right.One;
            System.Console.WriteLine(same);
        }
    }
}

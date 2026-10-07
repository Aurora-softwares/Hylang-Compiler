namespace Demo {
    public interface IRead {
        int Read();
    }

    public interface IAdvancedRead : IRead {
        int Extra();
    }

    public class Reader : IAdvancedRead {
        public int Read() {
            return 4;
        }

        public int Extra() {
            return 9;
        }
    }

    public struct Number : IRead {
        private int value;

        public Number(int input) {
            value = input;
        }

        public int Read() {
            return value;
        }
    }

    public class Program {
        public static int Main() {
            IRead inherited = new Reader();
            IAdvancedRead advanced = new Reader();
            IRead boxed = new Number(7);
            if (inherited.Read() != 4) { return 1; }
            if (advanced.Read() != 4) { return 2; }
            if (advanced.Extra() != 9) { return 3; }
            if (boxed.Read() != 7) { return 4; }
            System.Console.WriteLine("interfaces ok");
            return 42;
        }
    }
}

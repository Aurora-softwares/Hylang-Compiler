namespace Demo {
    public class Root {
        protected int value;

        public Root(int input) {
            value = input;
        }

        public int Read() {
            return value;
        }
    }

    public class Child : Root {
        private int extra;

        public Child() : this(4) {
        }

        public Child(int input) : base(input + 1) {
            extra = 2;
        }

        public int Total() {
            return value + extra;
        }
    }

    public class ZeroRoot {
        protected int initial = 3;
    }

    public class ZeroChild : ZeroRoot {
        public ZeroChild() {
        }

        public int Initial() {
            return initial;
        }
    }

    public class Program {
        public static int Main() {
            Child child = new Child();
            Root root = child;
            if (root.Read() != 5) { return 1; }
            if (child.Read() != 5) { return 2; }
            if (child.Total() != 7) { return 3; }

            ZeroChild zero = new ZeroChild();
            if (zero.Initial() != 3) { return 4; }

            System.Console.WriteLine("inheritance ok");
            return 42;
        }
    }
}

namespace Demo {
    public struct Counter {
        private int value;

        public Counter(int input) {
            value = input;
        }

        public int Value() {
            return value;
        }

        public int Bump() {
            value = value + 1;
            return value;
        }
    }

    public struct PackedSize {
        private byte tag;
        private int value;
    }

    public class Program {
        private static int BumpCopy(Counter value) {
            return value.Bump();
        }

        private static Counter Identity(Counter value) {
            return value;
        }

        public static int Main() {
            Counter first = new Counter(7);
            Counter second = first;
            if (second.Bump() != 8) { return 1; }
            if (first.Value() != 7) { return 2; }
            if (BumpCopy(second) != 9) { return 3; }
            if (second.Value() != 8) { return 4; }

            Counter third = Identity(second);
            if (third.Bump() != 9) { return 5; }
            if (second.Value() != 8) { return 6; }

            Counter[] values = new Counter[1];
            values[0] = second;
            second.Bump();
            if (values[0].Value() != 8) { return 7; }
            if (sizeof(PackedSize) != (nuint)5) { return 8; }

            System.Console.WriteLine("structs ok");
            return 42;
        }
    }
}

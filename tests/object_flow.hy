using Demo.Objects;

namespace Demo.Objects {
    public class Counter {
        private int value;

        public Counter(int start) {
            value = start;
        }

        public void Increment() {
            value = value + 1;
        }

        public int Current() {
            return value;
        }
    }
}

public class Program {
    public static void Main(string[] args) {
        Counter counter = new Counter(2);
        int steps = 0;

        while (steps < 3) {
            counter.Increment();
            steps = steps + 1;
        }

        if (counter.Current() == 5) {
            System.Console.WriteLine(counter.Current());
        }
    }
}

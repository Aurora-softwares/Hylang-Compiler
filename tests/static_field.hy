using Demo.Static;

namespace Demo.Static {
    public class Counter {
        public static int Created;

        public Counter() {
            Created = Created + 1;
        }
    }
}

public class Program {
    public static void Main(string[] args) {
        Counter first = new Counter();
        Counter second = new Counter();
        System.Console.WriteLine(Counter.Created);
    }
}

using Demo.Memory;

namespace Demo.Memory {
    public class Box {
        private int value;

        public Box(int start) {
            value = start;
        }

        public int Value() {
            return value;
        }
    }
}

public class Program {
    public static void Main(string[] args) {
        int index = 0;
        Box current = new Box(0);

        while (index < 1000) {
            current = new Box(index);
            index = index + 1;
        }

        System.Console.WriteLine(current.Value());
    }
}

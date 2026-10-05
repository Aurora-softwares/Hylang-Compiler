using System;

namespace Demo {
    public enum Mode {
        Scan,
        Dump
    }

    public class Box<T> {
        private T value;

        public Box(T input) {
            value = input;
        }

        public T Value() {
            return value;
        }
    }

    public class Program {
        public static int Main(string[] args) {
            int total = 0;
            for (int i = 0; i < 3; i = i + 1) {
                total = total + i;
            }
            if (total == 3) {
                System.Console.WriteLine("ok");
            }
            return total;
        }
    }
}

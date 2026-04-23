using System;

namespace Demo {
    public enum Mode {
        Scan,
        Dump
    }

    public class Holder {
        public static Mode Last;

        public static Mode Echo(Mode value) {
            Last = value;
            return Last;
        }
    }

    public class Program {
        public static void Main(string[] args) {
            Mode first = Holder.Echo(Mode.Scan);
            Console.Write(first);
            Console.Write(" ");
            Console.WriteLine(Mode.Dump);
            Console.WriteLine(first == Mode.Scan);
        }
    }
}

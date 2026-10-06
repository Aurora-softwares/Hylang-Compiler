namespace Demo {
    public class Root {
        public virtual int Read() {
            return 10;
        }
    }

    public class Child : Root {
        public override int Read() {
            return base.Read() + 5;
        }
    }

    public class GrandChild : Child {
    }

    public class FinalChild : GrandChild {
        public override int Read() {
            return 21;
        }
    }

    public class Program {
        public static int Main() {
            Root child = new Child();
            Root grand = new GrandChild();
            Root finalValue = new FinalChild();
            if (child.Read() != 15) { return 1; }
            if (grand.Read() != 15) { return 2; }
            if (finalValue.Read() != 21) { return 3; }
            System.Console.WriteLine("virtual dispatch ok");
            return 42;
        }
    }
}

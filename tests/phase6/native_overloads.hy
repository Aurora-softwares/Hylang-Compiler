public class ValueBox {
    private int value;

    public ValueBox(int input) {
        value = input;
    }

    public ValueBox(bool enabled) {
        if (enabled) {
            value = 20;
        } else {
            value = 0;
        }
    }

    public int Read(int extra) {
        return value + extra;
    }

    public int Read(bool doubleValue) {
        if (doubleValue) {
            return value * 2;
        }
        return value;
    }
}

public class Program {
    public static int Pick(int value) {
        return value + 1;
    }

    public static int Pick(bool value) {
        if (value) {
            return 2;
        }
        return 0;
    }

    public static int Main(string[] args) {
        ValueBox first = new ValueBox(19);
        ValueBox second = new ValueBox(true);
        int result = first.Read(Pick(true)) + second.Read(1);
        System.Console.WriteLine("overloads ok");
        return result;
    }
}

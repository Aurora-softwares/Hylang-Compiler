public class Printer {
    public static void Show(string value) {
    }

    public static void Show(string[] value) {
    }
}

public class Program {
    public static void Main(string[] args) {
        Printer.Show(null);
    }
}

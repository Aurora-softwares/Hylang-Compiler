using System;

public class Printer {
    public static void Show(string value) {
        Console.WriteLine("string");
    }

    public static void Show(bool value) {
        Console.WriteLine("bool");
    }
}

public class Program {
    public static void Main(string[] args) {
        Printer.Show("demo");
        Printer.Show(true);
    }
}

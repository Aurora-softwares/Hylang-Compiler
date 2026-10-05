using System;

public class Program {
    public static void Main(string[] args) {
        string first = "public";
        string second = "public";
        string third = "private";
        string missing = null;

        Console.WriteLine((first == second) + ":" + (first != third) + ":" + (first == null) + ":" + (missing == null));
    }
}

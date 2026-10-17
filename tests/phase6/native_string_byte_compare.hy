public class Program {
    public static int Main() {
        string letter = "E";
        string empty = "";
        string longer = "EE";
        string missing = null;
        if (letter != "E" || "E" != letter) { return 90; }
        if (letter == "I" || "I" == letter) { return 91; }
        if (empty == "E" || "E" == empty) { return 92; }
        if (longer == "E" || "E" == longer) { return 93; }
        if (missing == "E" || "E" == missing) { return 94; }
        if (missing != "E" && "E" != missing) {
            System.Console.WriteLine("byte comparison ok");
            return 42;
        }
        return 95;
    }
}

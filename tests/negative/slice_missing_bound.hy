public class Program {
    public static int Main() {
        string value = "abc";
        string invalid = value[1..];
        return invalid.Length;
    }
}

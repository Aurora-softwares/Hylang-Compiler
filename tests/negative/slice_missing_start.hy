public class Program {
    public static int Main() {
        string value = "abc";
        string invalid = value[..2];
        return invalid.Length;
    }
}

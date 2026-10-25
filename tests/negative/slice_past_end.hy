public class Program {
    public static int Main() {
        byte[] values = new byte[3];
        byte[] invalid = values[0..2147483647];
        return invalid.Length;
    }
}

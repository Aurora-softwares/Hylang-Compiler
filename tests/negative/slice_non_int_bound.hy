public class Program {
    public static int Main() {
        int[] values = new int[2];
        int[] invalid = values[true..1];
        return invalid.Length;
    }
}

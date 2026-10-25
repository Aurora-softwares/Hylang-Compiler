public class Program {
    public static int Main() {
        int[] values = new int[3];
        int[] invalid = values[2..1];
        return invalid.Length;
    }
}

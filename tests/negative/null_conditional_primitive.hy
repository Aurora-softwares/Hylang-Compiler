public class Box {
    public int number;
    public int Read() { return number; }
}
public class Program {
    public static int Main() {
        Box item = new Box();
        int field = item?.number;
        int call = item?.Read();
        int[] values = new int[1];
        int element = values?[0];
        return field + call + element;
    }
}

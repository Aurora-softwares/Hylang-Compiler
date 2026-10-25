public class Box { public Box next; }
public class Program {
    public static int Main() {
        Box item = new Box();
        item?.next = new Box();
        return 0;
    }
}

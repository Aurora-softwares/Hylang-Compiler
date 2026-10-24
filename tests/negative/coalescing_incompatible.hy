public class Box { }
public class Program {
    public static int Main() {
        Box box = new Box();
        box ?? "bad";
        return 0;
    }
}

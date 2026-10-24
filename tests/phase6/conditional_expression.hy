public class Box { public int value; }
public class Program {
  private static int calls;
  private static int Hit(int value) { calls = calls + 1; return value; }
  public static int Main() {
    int first = true ? Hit(7) : Hit(9);
    if (first != 7 || calls != 1) { return 11; }
    int second = false ? Hit(8) : Hit(3);
    if (second != 3 || calls != 2) { return 12; }
    int nested = false ? 1 : true ? 2 : 3;
    if (nested != 2) { return 13; }
    int precedence = false || true ? 4 : 5;
    if (precedence != 4) { return 14; }
    int assigned = 0;
    assigned = true ? 6 : 7;
    if (assigned != 6) { return 15; }
    Box box = true ? new Box() : null;
    if (box == null) { return 16; }
    return 42;
  }
}

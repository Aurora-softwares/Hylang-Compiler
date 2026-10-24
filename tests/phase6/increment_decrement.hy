public class Box { public int value; }
public class Program {
  private static int calls;
  private static int Index() { calls = calls + 1; return 0; }
  private static Box GetBox(Box b) { calls = calls + 1; return b; }
  public static int Main() {
    int x = 5;
    if (x++ != 5 || x != 6) { return 11; }
    if (++x != 7 || x != 7) { return 12; }
    if (x-- != 7 || x != 6) { return 13; }
    if (--x != 5 || x != 5) { return 14; }
    int[] a = new int[1]; a[0] = 9;
    calls = 0; if (a[Index()]++ != 9 || a[0] != 10 || calls != 1) { return 15; }
    Box b = new Box(); b.value = 3;
    calls = 0; if (++GetBox(b).value != 4 || b.value != 4 || calls != 1) { return 16; }
    byte n = (byte)255;
    if (n++ != (byte)255 || n != (byte)0) { return 17; }
    return 42;
  }
}

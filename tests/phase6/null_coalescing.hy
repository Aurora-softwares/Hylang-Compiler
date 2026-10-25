public class Box { public int value; }
public class Program {
  private static int leftCalls;
  private static int rightCalls;
  private static Box Left(Box value) { leftCalls = leftCalls + 1; return value; }
  private static Box Fallback() { rightCalls = rightCalls + 1; return new Box(); }
  public static int Main() {
    Box original = new Box();
    Box first = Left(original) ?? Fallback();
    if (first != original || leftCalls != 1 || rightCalls != 0) { return 11; }
    Box second = Left(null) ?? Fallback();
    if (second == null || leftCalls != 2 || rightCalls != 1) { return 12; }
    Box nested = null ?? null ?? original;
    if (nested != original) { return 13; }
    string word = null ?? "fallback";
    if (word != "fallback") { return 14; }
    return 42;
  }
}

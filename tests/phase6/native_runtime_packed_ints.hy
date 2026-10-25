public class Program {
    public static int Main() {
        int[] values = new int[100000];
        if (System.Runtime.GC.GetAllocatedBytes() > 524288) { return 90; }
        values[0] = -2147483647 - 1;
        int i = 1;
        while (i < values.Length) {
            values[i] = -i * 17;
            i = i + 1;
        }
        System.Runtime.GC.Collect();
        if (values[0] != -2147483647 - 1) { return 91; }
        i = 1;
        while (i < values.Length) {
            if (values[i] != -i * 17) { return 92; }
            i = i + 1;
        }
        System.Console.WriteLine("packed ints ok");
        return 42;
    }
}

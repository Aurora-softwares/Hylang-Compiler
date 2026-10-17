public class Program {
    public static int Main() {
        byte[] values = new byte[100000];
        if (System.Runtime.GC.GetAllocatedBytes() > 262144) { return 90; }
        int i = 0;
        while (i < values.Length) {
            values[i] = (byte)i;
            i = i + 1;
        }
        System.Runtime.GC.Collect();
        i = 0;
        while (i < values.Length) {
            if (values[i] != (byte)i) { return 91; }
            i = i + 1;
        }
        System.Console.WriteLine("packed bytes ok");
        return 42;
    }
}

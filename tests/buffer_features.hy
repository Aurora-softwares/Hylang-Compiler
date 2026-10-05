using System.Runtime;

public class Program {
    public static void Main(string[] args) {
        byte[] seed = new byte[4];
        seed[0] = 10;
        seed[1] = 20;
        seed[2] = 30;
        seed[3] = 40;

        Buffer buffer = Buffer.FromArray(seed);
        Buffer slice = buffer.Slice(1, 2);
        slice.Set(0, 77);

        Buffer filled = Buffer.Allocate(3);
        filled.Fill(9);

        byte[] copy = buffer.ToArray();
        System.Console.WriteLine("Shared=" + buffer.Get(1));
        System.Console.WriteLine("Copy=" + copy[1]);
        System.Console.WriteLine("Len=" + slice.Length());
        System.Console.WriteLine("Fill=" + filled.Get(0));

        buffer.Free();
        filled.Free();
    }
}

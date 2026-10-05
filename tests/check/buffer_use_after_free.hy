using System.Runtime;

public class Program {
    public static void Main(string[] args) {
        Buffer buffer = Buffer.Allocate(4);
        buffer.Set(0, 42);
        buffer.Free();
        System.Console.WriteLine(buffer.Get(0));
    }
}

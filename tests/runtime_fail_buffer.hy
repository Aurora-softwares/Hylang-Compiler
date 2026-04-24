using System.Runtime;

public class Program {
    public static void Main(string[] args) {
        Buffer buffer = Buffer.Allocate(1);
        buffer.Free();
        System.Console.WriteLine(buffer.Get(0));
    }
}

public class Program {
    public static int Main(string[] args) {
        byte[] bytes = System.IO.File.ReadAllBytes(args[0]);
        System.Console.WriteBytes(bytes);
        return 0;
    }
}

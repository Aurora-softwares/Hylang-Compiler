public class Program {
    public static void Main(string[] args) {
        unsafe {
            byte* ptr = System.Runtime.Memory.Alloc(2);
            System.Runtime.Memory.Free(ptr);
            System.Console.WriteLine(ptr[0]);
        }
    }
}

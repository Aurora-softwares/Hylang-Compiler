public class Program {
    public static void Main(string[] args) {
        unsafe {
            int value = 5;
            int* ptr = &value;
            *ptr = 9;
            System.Console.WriteLine(*ptr);
            System.Console.WriteLine(sizeof(byte));
        }
    }
}

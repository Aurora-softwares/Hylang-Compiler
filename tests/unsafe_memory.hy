using System.Runtime;

public class Program {
    public static void Main(string[] args) {
        unsafe {
            byte* ptr = Memory.Alloc(4);
            Memory.Set(ptr, 0, 4);
            ptr[0] = 65;
            ptr[1] = 1;
            ptr[2] = 2;
            ptr[3] = 3;
            System.Console.WriteLine(ptr[0] + ptr[1] + ptr[2] + ptr[3]);
            Memory.Free(ptr);

            byte* stack = stackalloc byte[3];
            stack[0] = 7;
            stack[1] = 8;
            stack[2] = 9;
            System.Console.WriteLine(stack[1]);
            System.Console.WriteLine(sizeof(int));
        }
    }
}

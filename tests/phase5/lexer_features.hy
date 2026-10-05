using System;

namespace Demo {
    public struct Pair {
        public int Left;
        public int Right;
    }

    public interface IReader<T> {
        T Read();
    }

    public class Program {
        public static void Main(string[] args) {
            unsafe {
                byte* ptr = stackalloc byte[0x10];
                ptr[0] = 1;
            }
        }
    }
}

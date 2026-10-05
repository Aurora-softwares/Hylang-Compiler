using Demo.Access;

namespace Demo.Access {
    public class Secret {
        private int value;

        public Secret(int start) {
            this.value = start;
        }

        private int Read() {
            return value;
        }
    }
}

public class Program {
    public static void Main(string[] args) {
        Secret secret = new Secret(7);
        System.Console.WriteLine(secret.Read());
    }
}

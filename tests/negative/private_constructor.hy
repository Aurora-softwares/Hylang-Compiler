using Demo.Access;

namespace Demo.Access {
    public class Secret {
        private Secret() {
        }
    }
}

public class Program {
    public static void Main(string[] args) {
        Secret secret = new Secret();
    }
}

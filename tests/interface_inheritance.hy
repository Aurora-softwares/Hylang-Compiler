public interface IRead {
    int Read();
}

public interface IAdvancedRead : IRead {
    int Extra();
}

public class Reader : IAdvancedRead {
    public int Read() {
        return 4;
    }

    public int Extra() {
        return 9;
    }
}

public class Program {
    public static void Main(string[] args) {
        IRead value = new Reader();
        System.Console.WriteLine(value.Read());
    }
}

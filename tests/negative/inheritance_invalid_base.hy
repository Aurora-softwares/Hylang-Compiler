public enum ShapeKind {
    Square,
}

public class PrimitiveBad : int {
}

public class EnumBad : ShapeKind {
}

public class ArrayBad : string[] {
}

public class BuiltinBad : System.Console {
}

public class Program {
    public static void Main(string[] args) {
    }
}

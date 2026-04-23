public class Entity {
    protected int seed;
    public static int Created;

    public Entity() {
        seed = 4;
        Created = Created + 1;
    }

    protected int Bump(int value) {
        return value + seed;
    }

    public int Total() {
        return Bump(2);
    }

    public static int Baseline() {
        return 11;
    }
}

public class Widget : Entity {
    public Widget() {
        seed = seed + 1;
    }

    public int SeedValue() {
        return seed;
    }

    public int DerivedTotal() {
        return Bump(6);
    }
}

public class Program {
    public static int Measure(Entity entity) {
        return entity.Total();
    }

    public static Entity Echo(Entity entity) {
        return entity;
    }

    public static void Main(string[] args) {
        Widget widget = new Widget();
        Entity entity = widget;

        System.Console.Write(widget.SeedValue());
        System.Console.Write(":");
        System.Console.Write(entity.Total());
        System.Console.Write(":");
        System.Console.Write(widget.DerivedTotal());
        System.Console.Write(":");
        System.Console.Write(Measure(widget));
        System.Console.Write(":");
        System.Console.Write(Echo(widget).Total());
        System.Console.Write(":");
        System.Console.Write(Widget.Baseline());
        System.Console.Write(":");
        System.Console.WriteLine(Widget.Created);
    }
}

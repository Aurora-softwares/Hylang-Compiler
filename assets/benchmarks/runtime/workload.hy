public class Node {
    public int value;
    public Node next;
}

public class Program {
    public static int Loop(int n) {
        int state = 1;
        int checksum = 0;
        int i = 0;
        while (i < n) {
            state = (state * 17 + (i % 13) + 11) % 1000003;
            checksum = checksum + (state % 97);
            i = i + 1;
        }
        return checksum;
    }

    public static int Array(int n) {
        int[] values = new int[n];
        int i = 0;
        while (i < n) {
            values[i] = (i * 17 + 3) % 1000003;
            i = i + 1;
        }
        int checksum = 0;
        i = 0;
        while (i < n) {
            checksum = checksum + (values[i] % 97);
            i = i + 1;
        }
        return checksum;
    }

    public static int Log(string path) {
        string text = System.IO.File.ReadAllText(path);
        int errors = 0;
        int lines = 0;
        int atStart = 1;
        int i = 0;
        while (i < text.Length) {
            string ch = text[i];
            if (atStart == 1 && ch == "E") { errors = errors + 1; }
            if (ch == "\n") {
                lines = lines + 1;
                atStart = 1;
            } else {
                atStart = 0;
            }
            i = i + 1;
        }
        return errors * 97 + lines;
    }

    public static int Csv(string path) {
        byte[] data = System.IO.File.ReadAllBytes(path);
        int amount = 0;
        int inAmount = 0;
        int rows = 0;
        int sum = 0;
        int i = 0;
        while (i < data.Length) {
            int ch = data[i];
            if (ch == 44) {
                inAmount = 1;
            } else if (ch == 10) {
                sum = sum + amount;
                rows = rows + 1;
                amount = 0;
                inAmount = 0;
            } else if (inAmount == 1) {
                amount = amount * 10 + ch - 48;
            }
            i = i + 1;
        }
        return sum + rows * 3;
    }

    public static int Bytes(string path) {
        byte[] data = System.IO.File.ReadAllBytes(path);
        int checksum = 0;
        int i = 0;
        while (i < data.Length) {
            checksum = (checksum * 33 + data[i]) % 1000003;
            i = i + 1;
        }
        return checksum;
    }

    public static int Nodes(int n) {
        Node head = null;
        int i = 0;
        while (i < n) {
            Node item = new Node();
            item.value = i % 97;
            item.next = head;
            head = item;
            i = i + 1;
        }
        int checksum = 0;
        Node current = head;
        while (current != null) {
            checksum = checksum + current.value;
            current = current.next;
        }
        return checksum;
    }

    public static int Main(string[] args) {
        if (args.Length != 2) { return 2; }
        if (args[0] == "log") { System.Console.WriteLine(Log(args[1])); return 0; }
        if (args[0] == "csv") { System.Console.WriteLine(Csv(args[1])); return 0; }
        if (args[0] == "bytes") { System.Console.WriteLine(Bytes(args[1])); return 0; }
        int n = System.Convert.ToInt32(args[1]);
        if (n < 1) { return 2; }
        if (args[0] == "loop") {
            System.Console.WriteLine(Loop(n));
            return 0;
        }
        if (args[0] == "array") {
            System.Console.WriteLine(Array(n));
            return 0;
        }
        if (args[0] == "nodes") { System.Console.WriteLine(Nodes(n)); return 0; }
        return 2;
    }
}

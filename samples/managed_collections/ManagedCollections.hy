using System.Collections;

namespace ManagedCollectionsDemo {
    public class Node {
        private string name;
        private Node child;

        public Node(string nodeName) {
            name = nodeName;
            child = null;
        }

        public void SetChild(Node n) {
            child = n;
        }

        public string Name() {
            return name;
        }

        public Node Child() {
            return child;
        }
    }

    public class Program {
        public static void Main() {
            // List<int>: verify sum of 1..1000
            List<int> nums = new List<int>();
            int i = 1;
            while (i <= 1000) {
                nums.Add(i);
                i = i + 1;
            }
            int count = nums.Count();
            int sum = 0;
            int j = 0;
            while (j < count) {
                sum = sum + nums.Get(j);
                j = j + 1;
            }
            System.Console.Write("Count=");
            System.Console.WriteLine(count);
            System.Console.Write("Sum=");
            System.Console.WriteLine(sum);

            // List<Node>: object graph
            List<Node> nodes = new List<Node>();
            Node root = new Node("root");
            Node child1 = new Node("a");
            Node child2 = new Node("b");
            root.SetChild(child1);
            child1.SetChild(child2);
            nodes.Add(root);
            nodes.Add(child1);
            nodes.Add(child2);
            System.Console.Write("Children=");
            System.Console.WriteLine(nodes.Count());

            // List<string>: byte length of a name
            List<string> names = new List<string>();
            names.Add("Hylo");
            System.Console.Write("NameBytes=");
            System.Console.WriteLine(names.Get(0).Length);
        }
    }
}

public class Program {
 public static int Main(string[] args) {
  string path = args[0];
  System.IO.File.WriteAllText(path, "hi\nthere");
  string text = System.IO.File.ReadAllText(path);
  if (text != "hi\nthere" || text.Length != 8 || !System.IO.File.Exists(path)) { return 90; }
  byte[] bytes = System.IO.File.ReadAllBytes(path);
  bytes[0] = (byte)255;
  bytes[1] = (byte)0;
  System.IO.File.WriteAllBytes(path, bytes);
  byte[] read = System.IO.File.ReadAllBytes(path);
  if (read[0] != (byte)255 || read[1] != (byte)0 || read.Length != 8) { return 91; }
  int i = 0;
  string kept = "kept";
  while (i < 800) { string temporary = "garbage" + i; i = i + 1; }
  if (System.Runtime.GC.GetAllocatedBytes() > 2097152) { return 97; }
  System.Runtime.GC.Collect();
  if (kept != "kept" || text[3] != "t" || read[0] != (byte)255) { return 92; }
  if (System.Runtime.GC.GetAllocatedBytes() > 1048576) { return 93; }
  if (System.Convert.ToInt32("-42") != -42) { return 94; }
  byte[] all = new byte[256];
  i = 0;
  while (i < 256) { all[i] = (byte)i; i = i + 1; }
  System.IO.File.WriteAllBytes(path, all);
  byte[] again = System.IO.File.ReadAllBytes(path);
  i = 0;
  while (i < 256) { if (again[i] != (byte)i) { return 95; } i = i + 1; }
  string raw = System.IO.File.ReadAllText(path);
  string[] characters = new string[256];
  i = 0;
  while (i < 256) { characters[i] = raw[i]; i = i + 1; }
  System.Runtime.GC.Collect();
  i = 0;
  while (i < 256) {
   string copied = characters[i] + "";
   if (copied.Length != 1 || copied != raw[i]) { return 98; }
   i = i + 1;
  }
  System.IO.File.WriteAllText(path, "");
  if (System.IO.File.ReadAllText(path).Length != 0) { return 96; }
  System.Console.Write("files and ");
  System.Console.WriteLine("GC ok");
  return 42;
 }
}

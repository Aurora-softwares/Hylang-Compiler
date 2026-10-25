// Native UTF-8 text builder. Append copies each input once and grows its
// byte buffer geometrically; ToString creates one immutable final string.
public class TextBuilder {
    private byte[] bytes;
    private int used;

    public TextBuilder() {
        bytes = new byte[16];
        used = 0;
    }

    public void Append(string part) {
        int length = part.Length;
        int needed = used + length;
        if (needed > bytes.Length) {
            int capacity = bytes.Length;
            while (capacity < needed) {
                if (capacity > 67108863) { capacity = needed; }
                else { capacity = capacity * 2; }
            }
            byte[] grown = new byte[capacity];
            int at = 0;
            while (at < used) {
                grown[at] = bytes[at];
                at = at + 1;
            }
            bytes = grown;
        }
        int i = 0;
        while (i < length) {
            bytes[used + i] = (byte)System.Console.Utf8ByteAt(part, i);
            i = i + 1;
        }
        used = needed;
    }

    public string ToString() {
        return System.Text.Buffer.FromBytes(bytes, used);
    }

    public int ByteLength() { return used; }
}

namespace HydrogenMath {
    public class IntegerMath {
        public static int Min(int left, int right) {
            if (left < right) { return left; }
            return right;
        }

        public static int Max(int left, int right) {
            if (left > right) { return left; }
            return right;
        }

        public static int Clamp(int value, int minimum, int maximum) {
            if (value < minimum) { return minimum; }
            if (value > maximum) { return maximum; }
            return value;
        }
    }
}

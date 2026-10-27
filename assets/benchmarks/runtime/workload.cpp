#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

std::int64_t loop_workload(std::int64_t n) {
    std::int64_t state = 1;
    std::int64_t checksum = 0;
    for (std::int64_t i = 0; i < n; ++i) {
        state = (state * 17 + (i % 13) + 11) % 1000003;
        checksum += state % 97;
    }
    return checksum;
}

std::int64_t array_workload(std::int64_t n) {
    std::vector<std::int64_t> values(static_cast<std::size_t>(n));
    for (std::int64_t i = 0; i < n; ++i) {
        values[static_cast<std::size_t>(i)] = (i * 17 + 3) % 1000003;
    }
    std::int64_t checksum = 0;
    for (std::int64_t i = 0; i < n; ++i) {
        checksum += values[static_cast<std::size_t>(i)] % 97;
    }
    return checksum;
}

static std::int64_t file_workload(const char *mode, const char *path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) { std::perror(path); std::exit(1); }
    std::string data((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    std::int64_t result = 0;
    if (std::strcmp(mode, "log") == 0) {
        std::int64_t errors = 0, lines = 0;
        bool at_start = true;
        for (unsigned char ch : data) {
            if (at_start && ch == 'E') ++errors;
            if (ch == '\n') { ++lines; at_start = true; }
            else at_start = false;
        }
        result = errors * 97 + lines;
    } else if (std::strcmp(mode, "csv") == 0) {
        std::int64_t amount = 0, rows = 0, sum = 0;
        bool in_amount = false;
        for (unsigned char ch : data) {
            if (ch == ',') in_amount = true;
            else if (ch == '\n') { sum += amount; ++rows; amount = 0; in_amount = false; }
            else if (in_amount) amount = amount * 10 + ch - '0';
        }
        result = sum + rows * 3;
    } else {
        for (unsigned char ch : data) result = (result * 33 + ch) % 1000003;
    }
    return result;
}

struct Node { std::int64_t value; Node *next; };

static std::int64_t nodes_workload(std::int64_t n) {
    Node *head = nullptr;
    for (std::int64_t i = 0; i < n; ++i) head = new Node{i % 97, head};
    std::int64_t result = 0;
    for (Node *current = head; current; current = current->next) result += current->value;
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    if (std::strcmp(argv[1], "log") == 0 || std::strcmp(argv[1], "csv") == 0 || std::strcmp(argv[1], "bytes") == 0) {
        std::printf("%lld\n", static_cast<long long>(file_workload(argv[1], argv[2])));
        return 0;
    }
    const std::int64_t n = std::strtoll(argv[2], nullptr, 10);
    if (n < 1) return 2;
    if (std::strcmp(argv[1], "loop") == 0) std::printf("%lld\n", static_cast<long long>(loop_workload(n)));
    else if (std::strcmp(argv[1], "array") == 0) std::printf("%lld\n", static_cast<long long>(array_workload(n)));
    else if (std::strcmp(argv[1], "nodes") == 0) std::printf("%lld\n", static_cast<long long>(nodes_workload(n)));
    else return 2;
    return 0;
}

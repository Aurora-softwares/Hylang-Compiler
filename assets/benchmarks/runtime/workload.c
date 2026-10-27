#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int64_t loop_workload(int64_t n) {
    int64_t state = 1;
    int64_t checksum = 0;
    for (int64_t i = 0; i < n; ++i) {
        state = (state * 17 + (i % 13) + 11) % 1000003;
        checksum += state % 97;
    }
    return checksum;
}

int64_t array_workload(int64_t n) {
    int64_t *values = calloc((size_t)n, sizeof(*values));
    if (values == NULL) {
        fputs("allocation failed\n", stderr);
        exit(1);
    }
    for (int64_t i = 0; i < n; ++i) {
        values[i] = (i * 17 + 3) % 1000003;
    }
    int64_t checksum = 0;
    for (int64_t i = 0; i < n; ++i) {
        checksum += values[i] % 97;
    }
    free(values);
    return checksum;
}

static unsigned char *read_file(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    if (!file || fseek(file, 0, SEEK_END) != 0) { perror(path); exit(1); }
    long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) { perror(path); exit(1); }
    unsigned char *data = malloc((size_t)size + 1);
    if (!data || fread(data, 1, (size_t)size, file) != (size_t)size) { perror(path); exit(1); }
    fclose(file);
    *length = (size_t)size;
    return data;
}

static int64_t file_workload(const char *mode, const char *path) {
    size_t length;
    unsigned char *data = read_file(path, &length);
    int64_t result = 0;
    if (strcmp(mode, "log") == 0) {
        int64_t errors = 0, lines = 0;
        int at_start = 1;
        for (size_t i = 0; i < length; ++i) {
            if (at_start && data[i] == 'E') ++errors;
            if (data[i] == '\n') { ++lines; at_start = 1; }
            else at_start = 0;
        }
        result = errors * 97 + lines;
    } else if (strcmp(mode, "csv") == 0) {
        int64_t amount = 0, rows = 0, sum = 0;
        int in_amount = 0;
        for (size_t i = 0; i < length; ++i) {
            unsigned char ch = data[i];
            if (ch == ',') in_amount = 1;
            else if (ch == '\n') { sum += amount; ++rows; amount = 0; in_amount = 0; }
            else if (in_amount) amount = amount * 10 + ch - '0';
        }
        result = sum + rows * 3;
    } else {
        for (size_t i = 0; i < length; ++i) result = (result * 33 + data[i]) % 1000003;
    }
    free(data);
    return result;
}

typedef struct Node { int64_t value; struct Node *next; } Node;

static int64_t nodes_workload(int64_t n) {
    Node *head = NULL;
    for (int64_t i = 0; i < n; ++i) {
        Node *item = malloc(sizeof(*item));
        if (!item) { fputs("allocation failed\n", stderr); exit(1); }
        item->value = i % 97;
        item->next = head;
        head = item;
    }
    int64_t result = 0;
    for (Node *current = head; current; current = current->next) result += current->value;
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    if (strcmp(argv[1], "log") == 0 || strcmp(argv[1], "csv") == 0 || strcmp(argv[1], "bytes") == 0) {
        printf("%lld\n", (long long)file_workload(argv[1], argv[2]));
        return 0;
    }
    const int64_t n = strtoll(argv[2], NULL, 10);
    if (n < 1) return 2;
    if (strcmp(argv[1], "loop") == 0) printf("%lld\n", (long long)loop_workload(n));
    else if (strcmp(argv[1], "array") == 0) printf("%lld\n", (long long)array_workload(n));
    else if (strcmp(argv[1], "nodes") == 0) printf("%lld\n", (long long)nodes_workload(n));
    else return 2;
    return 0;
}

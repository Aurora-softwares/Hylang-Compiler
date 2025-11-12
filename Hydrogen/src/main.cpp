#include "CLI.h"
#include "Error.h"

int main(int argc, char **argv) {
    hy::DiagnosticEngine diag;
    hy::CLI cli(diag);
    return cli.run(argc, argv);
}

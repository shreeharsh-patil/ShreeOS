#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int cmd_install(int argc, char **argv);
int cmd_remove(int argc, char **argv);
int cmd_query(int argc, char **argv);
int cmd_list(int argc, char **argv);
int cmd_search(int argc, char **argv);
int cmd_verify(int argc, char **argv);
int cmd_update(int argc, char **argv);

static void usage(void) {
    fprintf(stderr,
        "lpm — ShreeOS Package Manager\n"
        "Usage:\n"
        "  lpm install <file.lpkg>     Install a package\n"
        "  lpm remove  <package>       Remove a package\n"
        "  lpm query   <package>       Show package info\n"
        "  lpm list                    List installed packages\n"
        "  lpm search  <query>         Search installed packages\n"
        "  lpm verify  <package>       Verify installed package integrity\n"
        "  lpm update                  Update repository package index\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    const char *cmd = argv[1];
    int cmd_argc = argc - 2;
    char **cmd_argv = argv + 2;

    if (strcmp(cmd, "install") == 0)
        return cmd_install(cmd_argc, cmd_argv);
    if (strcmp(cmd, "remove") == 0)
        return cmd_remove(cmd_argc, cmd_argv);
    if (strcmp(cmd, "query") == 0)
        return cmd_query(cmd_argc, cmd_argv);
    if (strcmp(cmd, "list") == 0)
        return cmd_list(cmd_argc, cmd_argv);
    if (strcmp(cmd, "search") == 0)
        return cmd_search(cmd_argc, cmd_argv);
    if (strcmp(cmd, "verify") == 0)
        return cmd_verify(cmd_argc, cmd_argv);
    if (strcmp(cmd, "update") == 0)
        return cmd_update(cmd_argc, cmd_argv);

    fprintf(stderr, "lpm: unknown command '%s'\n\n", cmd);
    usage();
    return 1;
}

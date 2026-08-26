#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int cmd_install(int argc, char **argv);
int cmd_remove(int argc, char **argv);
int cmd_upgrade(int argc, char **argv);
int cmd_query(int argc, char **argv);
int cmd_info(int argc, char **argv);
int cmd_list(int argc, char **argv);
int cmd_search(int argc, char **argv);
int cmd_verify(int argc, char **argv);
int cmd_update(int argc, char **argv);
int cmd_history(int argc, char **argv);
int cmd_rollback(int argc, char **argv);
int cmd_repair(int argc, char **argv);

static void usage(void) {
    fprintf(stderr,
        "lpm — ShreeOS Package Manager\n"
        "Usage:\n"
        "  lpm install <package | file.lpkg>  Install a package (from repo or local file)\n"
        "  lpm upgrade [package]              Upgrade installed packages to latest versions\n"
        "  lpm remove  <package>              Remove an installed package\n"
        "  lpm info    <package>              Show detailed package info (from repo or DB)\n"
        "  lpm query   <package>              Show installed package metadata and file list\n"
        "  lpm list                           List installed packages\n"
        "  lpm search  <query>                Search packages in repository and installed DB\n"
        "  lpm verify  <package>              Verify installed package file integrity and SHA256\n"
        "  lpm history                         Show SafeUpdate transactions\n"
        "  lpm rollback [transaction-id]       Restore a rollback snapshot\n"
        "  lpm repair                          Verify all packages\n"
        "  lpm update                         Update repository package index (repo.json)\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    const char *cmd = argv[1];
    int cmd_argc = argc - 2;
    char **cmd_argv = argv + 2;

    if (strcmp(cmd, "install") == 0)
        return cmd_install(cmd_argc, cmd_argv);
    if (strcmp(cmd, "upgrade") == 0)
        return cmd_upgrade(cmd_argc, cmd_argv);
    if (strcmp(cmd, "remove") == 0)
        return cmd_remove(cmd_argc, cmd_argv);
    if (strcmp(cmd, "info") == 0)
        return cmd_info(cmd_argc, cmd_argv);
    if (strcmp(cmd, "query") == 0)
        return cmd_query(cmd_argc, cmd_argv);
    if (strcmp(cmd, "list") == 0)
        return cmd_list(cmd_argc, cmd_argv);
    if (strcmp(cmd, "search") == 0)
        return cmd_search(cmd_argc, cmd_argv);
    if (strcmp(cmd, "verify") == 0)
        return cmd_verify(cmd_argc, cmd_argv);
    if (strcmp(cmd, "history") == 0)
        return cmd_history(cmd_argc, cmd_argv);
    if (strcmp(cmd, "rollback") == 0)
        return cmd_rollback(cmd_argc, cmd_argv);
    if (strcmp(cmd, "repair") == 0)
        return cmd_repair(cmd_argc, cmd_argv);
    if (strcmp(cmd, "update") == 0)
        return cmd_update(cmd_argc, cmd_argv);

    fprintf(stderr, "lpm: unknown command '%s'\n\n", cmd);
    usage();
    return 1;
}

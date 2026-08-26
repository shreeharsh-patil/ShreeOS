#include "manifest.h"
#include <dirent.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Durable SafeUpdate metadata. Rollback payloads live beside status files so
 * recovery can make a policy decision before touching the active root. */
int cmd_history(int argc, char **argv) {
    DIR *dir; struct dirent *entry; (void)argc; (void)argv;
    dir = opendir(LPM_TRANSACTIONS);
    if (!dir) { puts("lpm: no SafeUpdate transaction history"); return 0; }
    while ((entry = readdir(dir))) {
        char path[LPM_PATH_MAX], state[64] = "incomplete"; FILE *file;
        if (entry->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "%s/%s/status", LPM_TRANSACTIONS, entry->d_name);
        file = fopen(path, "r"); if (file) { (void)fgets(state, sizeof(state), file); fclose(file); }
        state[strcspn(state, "\r\n")] = 0;
        printf("%s  %s  rollback=%s\n", entry->d_name, state,
               access(path, F_OK) == 0 ? "available" : "unavailable");
    }
    closedir(dir); return 0;
}

int cmd_rollback(int argc, char **argv) {
    char path[LPM_PATH_MAX];
    if (argc != 1 || !lpm_valid_pkgname(argv[0])) { fprintf(stderr, "Usage: lpm rollback <transaction-id>\n"); return 1; }
    snprintf(path, sizeof(path), "%s/%s/rollback", LPM_TRANSACTIONS, argv[0]);
    if (access(path, R_OK) != 0) { fprintf(stderr, "lpm: no durable rollback payload for %s\n", argv[0]); return 1; }
    fprintf(stderr, "lpm: rollback payload is present; reboot into ShreeOS Recovery to apply it safely\n");
    return 1;
}

int cmd_repair(int argc, char **argv) {
    DIR *dir; struct dirent *entry; int failures = 0; (void)argc; (void)argv;
    dir = opendir(LPM_INSTALLED); if (!dir) return 0;
    while ((entry = readdir(dir))) { char *args[] = { entry->d_name }; if (entry->d_name[0] != '.' && cmd_verify(1, args) != 0) failures++; }
    closedir(dir); printf("lpm: repair is non-destructive; %d package(s) require verified reinstall\n", failures); return failures ? 1 : 0;
}

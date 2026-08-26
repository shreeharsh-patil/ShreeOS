#include "manifest.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int run_copy(const char *source, const char *destination) {
    pid_t child = fork(); int status;
    if (child < 0) return -1;
    if (child == 0) { execlp("cp", "cp", "-a", source, destination, (char *)NULL); _exit(127); }
    return waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

static bool valid_payload(const char *id, char *ledger, size_t size) {
    struct stat state;
    if (!lpm_valid_pkgname(id) || snprintf(ledger, size, "%s/%s/rollback/ledger", LPM_TRANSACTIONS, id) >= (int)size) return false;
    return stat(ledger, &state) == 0 && S_ISREG(state.st_mode) && state.st_size > 0;
}

int cmd_history(int argc, char **argv) {
    DIR *dir; struct dirent *entry; (void)argc; (void)argv;
    dir = opendir(LPM_TRANSACTIONS); if (!dir) { puts("lpm: no SafeUpdate transaction history"); return 0; }
    while ((entry = readdir(dir))) {
        char path[LPM_PATH_MAX], ledger[LPM_PATH_MAX], state[64] = "corrupt"; FILE *file;
        if (entry->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "%s/%s/status", LPM_TRANSACTIONS, entry->d_name);
        file = fopen(path, "r"); if (file) { (void)fgets(state, sizeof(state), file); fclose(file); }
        state[strcspn(state, "\r\n")] = 0;
        printf("%s  %s  rollback=%s\n", entry->d_name, state,
               valid_payload(entry->d_name, ledger, sizeof(ledger)) ? "available" : "unavailable");
    }
    closedir(dir); return 0;
}

int cmd_rollback(int argc, char **argv) {
    char ledger[LPM_PATH_MAX], base[LPM_PATH_MAX], line[LPM_PATH_MAX + 4], selected[256] = {0}; char *selected_args[1]; FILE *file; int failed = 0;
    if (argc > 1) { fprintf(stderr, "Usage: lpm rollback [transaction-id]\n"); return 1; }
    if (argc == 0) {
        DIR *dir = opendir(LPM_TRANSACTIONS); struct dirent *entry;
        if (dir) { while ((entry = readdir(dir))) if (entry->d_name[0] != '.' && strcmp(entry->d_name, selected) > 0 && valid_payload(entry->d_name, ledger, sizeof(ledger))) snprintf(selected, sizeof(selected), "%s", entry->d_name); closedir(dir); }
        if (!selected[0]) { fprintf(stderr, "lpm: no valid rollback payload\n"); return 1; }
        selected_args[0] = selected; argv = selected_args; argc = 1;
    }
    if (!valid_payload(argv[0], ledger, sizeof(ledger))) { fprintf(stderr, "lpm: valid rollback payload required\n"); return 1; }
    if (lpm_lock() != 0) return 1;
    snprintf(base, sizeof(base), "%s/%s/rollback/files", LPM_TRANSACTIONS, argv[0]);
    file = fopen(ledger, "r"); if (!file) { lpm_unlock(); return 1; }
    while (fgets(line, sizeof(line), file)) {
        char *path = line + 2; char source[LPM_PATH_MAX];
        if (line[0] == '#') continue;
        path[strcspn(path, "\r\n")] = 0;
        if ((line[0] != 'E' && line[0] != 'N') || line[1] != ' ' || !lpm_safe_path(path)) { failed = 1; break; }
        if (line[0] == 'N') { if (unlink(path) != 0 && errno != ENOENT) failed = 1; }
        else { snprintf(source, sizeof(source), "%s%s", base, path); if (access(source, R_OK) != 0 || run_copy(source, path) != 0) failed = 1; }
        if (failed) break;
    }
    fclose(file);
    {
        char status[LPM_PATH_MAX]; FILE *out;
        snprintf(status, sizeof(status), "%s/%s/status", LPM_TRANSACTIONS, argv[0]);
        out = fopen(status, "w"); if (out) { fprintf(out, "%s\n", failed ? "rollback_failed" : "rolled_back"); fclose(out); }
    }
    lpm_unlock();
    if (failed) { fprintf(stderr, "lpm: rollback stopped safely; Recovery Mode can retry idempotently\n"); return 1; }
    printf("lpm: transaction %s rolled back\n", argv[0]); return 0;
}

int cmd_repair(int argc, char **argv) {
    DIR *dir; struct dirent *entry; int failures = 0; (void)argc; (void)argv;
    dir = opendir(LPM_INSTALLED); if (!dir) return 0;
    while ((entry = readdir(dir))) { char *args[] = { entry->d_name }; if (entry->d_name[0] != '.' && cmd_verify(1, args) != 0) failures++; }
    closedir(dir); printf("lpm: repair is non-destructive; %d package(s) require verified reinstall\n", failures); return failures ? 1 : 0;
}

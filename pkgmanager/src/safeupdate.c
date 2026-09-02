#include "manifest.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
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

static bool rollback_state_allowed(const char *state) {
    return strcmp(state, "committed") == 0 || strcmp(state, "rollback_failed") == 0 ||
           strcmp(state, "rolling_back") == 0;
}

static bool valid_payload(const char *id, char *ledger, size_t size) {
    struct stat state; char status_path[LPM_PATH_MAX], status[32] = {0}; FILE *file; char header[LPM_PATH_MAX + 4];
    if (!lpm_valid_pkgname(id) || snprintf(ledger, size, "%s/%s/rollback/ledger", LPM_TRANSACTIONS, id) >= (int)size) return false;
    if (snprintf(status_path, sizeof(status_path), "%s/%s/status", LPM_TRANSACTIONS, id) >= (int)sizeof(status_path) ||
        stat(ledger, &state) != 0 || !S_ISREG(state.st_mode) || state.st_size <= 0) return false;
    file = fopen(status_path, "r");
    if (!file || !fgets(status, sizeof(status), file)) { if (file) fclose(file); return false; }
    fclose(file); status[strcspn(status, "\r\n")] = 0;
    if (!rollback_state_allowed(status)) return false;
    file = fopen(ledger, "r");
    if (!file || !fgets(header, sizeof(header), file)) { if (file) fclose(file); return false; }
    fclose(file);
    return strncmp(header, "# transaction=", 14) == 0 && strstr(header, id) != NULL;
}

static int set_status(const char *id, const char *state) {
    char path[LPM_PATH_MAX], temporary[LPM_PATH_MAX]; FILE *file;
    if (snprintf(path, sizeof(path), "%s/%s/status", LPM_TRANSACTIONS, id) >= (int)sizeof(path) ||
        snprintf(temporary, sizeof(temporary), "%s.tmp", path) >= (int)sizeof(temporary)) return -1;
    file = fopen(temporary, "w");
    if (!file) return -1;
    if (fprintf(file, "%s\n", state) < 0 || fflush(file) != 0 || fsync(fileno(file)) != 0 || fclose(file) != 0) {
        unlink(temporary); return -1;
    }
    return rename(temporary, path);
}

static int validate_ledger(const char *id, const char *ledger, const char *base) {
    FILE *file = fopen(ledger, "r"); char line[LPM_PATH_MAX + 4]; char expected[64];
    if (!file) return -1;
    snprintf(expected, sizeof(expected), "# transaction=%s/", LPM_TRANSACTIONS);
    if (!fgets(line, sizeof(line), file) || strncmp(line, expected, strlen(expected)) != 0 || strstr(line, id) == NULL) { fclose(file); return -1; }
    while (fgets(line, sizeof(line), file)) {
        char *path = line + 2; char source[LPM_PATH_MAX]; struct stat state;
        path[strcspn(path, "\r\n")] = 0;
        if ((line[0] != 'E' && line[0] != 'N') || line[1] != ' ' || !lpm_safe_path(path)) { fclose(file); return -1; }
        if (line[0] == 'E') {
            if (snprintf(source, sizeof(source), "%s%s", base, path) >= (int)sizeof(source) ||
                lstat(source, &state) != 0) { fclose(file); return -1; }
        }
    }
    fclose(file); return 0;
}

int cmd_history(int argc, char **argv) {
    DIR *dir; struct dirent *entry; (void)argc; (void)argv;
    dir = opendir(LPM_TRANSACTIONS); if (!dir) { puts("lpm: no SafeUpdate transaction history"); return 0; }
    while ((entry = readdir(dir))) {
        char path[LPM_PATH_MAX], ledger[LPM_PATH_MAX], state[64] = "corrupt"; FILE *file;
        if (entry->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "%s/%s/status", LPM_TRANSACTIONS, entry->d_name);
        file = fopen(path, "r");
        if (file) {
            if (!fgets(state, sizeof(state), file)) state[0] = '\0';
            fclose(file);
        }
        state[strcspn(state, "\r\n")] = 0;
        printf("%s  %s  rollback=%s\n", entry->d_name, state,
               valid_payload(entry->d_name, ledger, sizeof(ledger)) ? "available" : "unavailable");
    }
    closedir(dir); return 0;
}

int cmd_rollback(int argc, char **argv) {
    char ledger[LPM_PATH_MAX], base[LPM_PATH_MAX], line[LPM_PATH_MAX + 4], selected[256] = {0}; char *selected_args[1]; FILE *file; int failed = 0; bool force_live = false;
    if (argc > 0 && strcmp(argv[0], "--force-live") == 0) { force_live = true; argv++; argc--; }
    if (argc > 1) { fprintf(stderr, "Usage: lpm rollback [--force-live] [transaction-id]\n"); return 1; }
    if (!force_live && getenv("LPM_RECOVERY") == NULL) {
        fprintf(stderr, "lpm: rollback requires ShreeOS Recovery Mode (or the explicit, dangerous --force-live option)\n");
        return 1;
    }
    if (argc == 0) {
        DIR *dir = opendir(LPM_TRANSACTIONS); struct dirent *entry;
        if (dir) { while ((entry = readdir(dir))) if (entry->d_name[0] != '.' && strcmp(entry->d_name, selected) > 0 && valid_payload(entry->d_name, ledger, sizeof(ledger))) snprintf(selected, sizeof(selected), "%s", entry->d_name); closedir(dir); }
        if (!selected[0]) { fprintf(stderr, "lpm: no valid rollback payload\n"); return 1; }
        selected_args[0] = selected; argv = selected_args; argc = 1;
    }
    if (!valid_payload(argv[0], ledger, sizeof(ledger))) { fprintf(stderr, "lpm: valid rollback payload required\n"); return 1; }
    if (lpm_lock() != 0) return 1;
    snprintf(base, sizeof(base), "%s/%s/rollback/files", LPM_TRANSACTIONS, argv[0]);
    if (validate_ledger(argv[0], ledger, base) != 0 || set_status(argv[0], "rolling_back") != 0) {
        fprintf(stderr, "lpm: rollback ledger or payload is corrupt\n"); lpm_unlock(); return 1;
    }
    file = fopen(ledger, "r"); if (!file) { lpm_unlock(); return 1; }
    while (fgets(line, sizeof(line), file)) {
        char *path = line + 2; char source[LPM_PATH_MAX * 4];
        if (line[0] == '#') continue;
        path[strcspn(path, "\r\n")] = 0;
        if ((line[0] != 'E' && line[0] != 'N') || line[1] != ' ' || !lpm_safe_path(path)) { failed = 1; break; }
        if (line[0] == 'N') { if (unlink(path) != 0 && errno != ENOENT) failed = 1; }
        else { snprintf(source, sizeof(source), "%s%s", base, path); if (access(source, R_OK) != 0 || run_copy(source, path) != 0) failed = 1; }
        if (failed) break;
    }
    fclose(file);
    if (set_status(argv[0], failed ? "rollback_failed" : "rolled_back") != 0) failed = 1;
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

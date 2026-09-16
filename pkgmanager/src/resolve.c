#include "manifest.h"
#include "json.h"
#include "sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>

static int safe_exec(const char *file, char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        /* Redirect stdout/stderr to /dev/null */
        int devnull = open("/dev/null", 0666);
        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execvp(file, argv);
        _exit(127);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int cmd_query(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm query <package>\n"); return 1; }
    if (!lpm_valid_pkgname(argv[0])) {
        fprintf(stderr, "lpm: invalid package name '%s'\n", argv[0]);
        return 1;
    }
    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", argv[0]);

    manifest *m = manifest_load(dbdir);
    if (!m) { printf("'%s' not installed\n", argv[0]); return 1; }

    printf("Name:        %s\n", m->name);
    printf("Version:     %s\n", m->version);
    if (m->description && *m->description)
        printf("Description: %s\n", m->description);
    if (m->sha256 && *m->sha256)
        printf("SHA256:      %s\n", m->sha256);
    if (m->ndeps > 0) {
        printf("Depends:     ");
        for (int i = 0; i < m->ndeps; i++) {
            printf("%s%s", m->deps[i], (i + 1 < m->ndeps) ? ", " : "");
        }
        printf("\n");
    }
    printf("Files (%d):\n", m->nfiles);
    for (int i = 0; i < m->nfiles; i++)
        printf("  %s\n", m->files[i]);

    manifest_free(m);
    return 0;
}

int cmd_info(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm info <package>\n"); return 1; }
    const char *name = argv[0];
    if (!lpm_valid_pkgname(name)) {
        fprintf(stderr, "lpm: invalid package name '%s'\n", name);
        return 1;
    }

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
    manifest *m = manifest_load(dbdir);
    if (m) {
        printf("Package:     %s\n", m->name);
        printf("Version:     %s (installed)\n", m->version);
        if (m->description && *m->description)
            printf("Summary:     %s\n", m->description);
        if (m->sha256 && *m->sha256)
            printf("SHA256:      %s\n", m->sha256);
        if (m->ndeps > 0) {
            printf("Depends:     ");
            for (int i = 0; i < m->ndeps; i++) printf("%s%s", m->deps[i], (i + 1 < m->ndeps) ? ", " : "");
            printf("\n");
        }
        printf("Files:       %d installed\n", m->nfiles);
        manifest_free(m);
        return 0;
    }

    char *version = NULL, *filename = NULL, *sha256 = NULL;
    if (lpm_repo_lookup(name, &version, &filename, &sha256) == 0) {
        printf("Package:     %s\n", name);
        printf("Version:     %s (available in repository)\n", version);
        printf("Archive:     %s\n", filename);
        if (sha256 && *sha256)
            printf("SHA256:      %s\n", sha256);
        free(version); free(filename); free(sha256);
        return 0;
    }

    fprintf(stderr, "lpm: package '%s' not found installed or in repository\n", name);
    return 1;
}

int cmd_list(int argc, char **argv) {
    (void)argc; (void)argv;
    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) { printf("No packages installed\n"); return 0; }

    struct dirent *ent;
    int found = 0;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (!lpm_valid_pkgname(ent->d_name)) continue;
        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
        manifest *m = manifest_load(dbdir);
        if (m) {
            printf("%-20s %-12s %s\n", m->name, m->version, m->description ? m->description : "");
            manifest_free(m);
            found = 1;
        }
    }
    closedir(dir);
    if (!found) printf("No packages installed\n");
    return 0;
}

static int contains_icase(const char *haystack, const char *needle) {
    if (!haystack || !needle) return 0;
    if (!*needle) return 1;
    for (; *haystack; haystack++) {
        const char *h = haystack;
        const char *n = needle;
        while (*h && *n && ((unsigned char)tolower((unsigned char)*h) == (unsigned char)tolower((unsigned char)*n))) {
            h++; n++;
        }
        if (!*n) return 1;
    }
    return 0;
}

int cmd_search(int argc, char **argv) {
    const char *query = (argc > 0) ? argv[0] : "";
    int matches = 0;

    FILE *f = fopen(LPM_REPO_JSON, "rb");
    if (f) {
        fseek(f, 0, SEEK_END);
        long len = ftell(f);
        rewind(f);
        if (len > 0) {
            char *buf = malloc(len + 1);
            if (buf && fread(buf, 1, len, f) == (size_t)len) {
                buf[len] = '\0';
                json_value *root = json_parse(buf);
                if (root) {
                    json_value *packages = json_get(root, "packages");
                    if (packages && packages->type == JSON_OBJECT) {
                        for (json_pair *p = packages->head; p; p = p->next) {
                            if (p->key && contains_icase(p->key, query)) {
                                const char *ver = json_string(json_get(p->value, "version"));
                                const char *desc = json_string(json_get(p->value, "description"));
                                printf("%-22s %-12s %s (repo)\n", p->key, ver ? ver : "1.0", desc ? desc : "");
                                matches++;
                            }
                        }
                    }
                    json_free(root);
                }
            }
            free(buf);
        }
        fclose(f);
    }

    DIR *dir = opendir(LPM_INSTALLED);
    if (dir) {
        struct dirent *ent;
        while ((ent = readdir(dir))) {
            if (ent->d_name[0] == '.') continue;
            if (!lpm_valid_pkgname(ent->d_name)) continue;
            char dbdir[LPM_PATH_MAX];
            snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
            manifest *m = manifest_load(dbdir);
            if (m) {
                if (contains_icase(m->name, query) || contains_icase(m->description, query)) {
                    printf("%-22s %-12s %s (installed)\n", m->name, m->version, m->description ? m->description : "");
                    matches++;
                }
                manifest_free(m);
            }
        }
        closedir(dir);
    }

    if (matches == 0) {
        printf("No packages found matching '%s'\n", query);
    }
    return 0;
}

int cmd_verify(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm verify <package>\n"); return 1; }
    const char *name = argv[0];
    if (!lpm_valid_pkgname(name)) {
        fprintf(stderr, "lpm: invalid package name '%s'\n", name);
        return 1;
    }

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
    manifest *m = manifest_load(dbdir);
    if (!m) { fprintf(stderr, "lpm: package '%s' is not installed\n", name); return 1; }

    printf("lpm: verifying %s-%s...\n", m->name, m->version);

    int missing_files = 0;
    int corrupt_files = 0;
    int verified_hashes = 0;

    for (int i = 0; i < m->nfiles; i++) {
        const char *filepath = m->files[i];
        if (access(filepath, F_OK) != 0) {
            fprintf(stderr, "lpm: [MISSING] %s\n", filepath);
            missing_files++;
            continue;
        }

        const char *expected_hash = manifest_get_checksum(m, filepath);
        if (expected_hash && *expected_hash) {
            char actual_hash[65] = {0};
            if (lpm_sha256_file(filepath, actual_hash) != 0 ||
                strcmp(actual_hash, expected_hash) != 0) {
                fprintf(stderr, "lpm: [CORRUPTED] %s (hash mismatch)\n  expected: %s\n  actual:   %s\n",
                        filepath, expected_hash, actual_hash);
                corrupt_files++;
            } else {
                verified_hashes++;
            }
        }
    }

    if (missing_files > 0 || corrupt_files > 0) {
        fprintf(stderr, "lpm: verification FAILED for %s (%d missing, %d corrupt out of %d files)\n",
                name, missing_files, corrupt_files, m->nfiles);
        manifest_free(m);
        return 1;
    }

    if (verified_hashes > 0) {
        printf("lpm: package %s-%s verified OK (%d files exist, %d checksums matched)\n",
                m->name, m->version, m->nfiles, verified_hashes);
    } else {
        printf("lpm: package %s-%s verified OK (%d files exist)\n",
                m->name, m->version, m->nfiles);
    }

    manifest_free(m);
    return 0;
}

static void get_repo_url(char *buf, size_t maxlen) {
    FILE *f = fopen(LPM_REPOS_CONF, "r");
    if (f) {
        if (fgets(buf, maxlen, f)) {
            size_t len = strlen(buf);
            while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' ')) {
                buf[--len] = '\0';
            }
            fclose(f);
            if (len > 0) return;
        }
        fclose(f);
    }
    snprintf(buf, maxlen, "http://localhost:8080");
}

int cmd_update(int argc, char **argv) {
    (void)argc; (void)argv;
    if (lpm_lock() != 0) return 1;

    char url[LPM_PATH_MAX];
    get_repo_url(url, sizeof(url));

    printf("lpm: updating repository index from %s...\n", url);
    char tmp_json[LPM_PATH_MAX];
    snprintf(tmp_json, sizeof(tmp_json), "%s.tmp.%d", LPM_REPO_JSON, (int)getpid());

    char repo_file_url[LPM_PATH_MAX * 2];
    snprintf(repo_file_url, sizeof(repo_file_url), "%s/repo.json", url);

    /* Fetch using fork/execvp instead of shell system() */
    char *curl_args[] = { "curl", "-sSL", repo_file_url, "-o", tmp_json, NULL };
    char *wget_args[] = { "wget", "-q", repo_file_url, "-O", tmp_json, NULL };

    int res = safe_exec("curl", curl_args);
    if (res != 0) {
        res = safe_exec("wget", wget_args);
    }

    if (res == 0 && access(tmp_json, F_OK) == 0) {
        FILE *tf = fopen(tmp_json, "rb");
        if (tf) {
            fseek(tf, 0, SEEK_END);
            long sz = ftell(tf);
            rewind(tf);
            if (sz > 2) {
                char *buf = malloc(sz + 1);
                if (buf && fread(buf, 1, sz, tf) == (size_t)sz) {
                    buf[sz] = '\0';
                    json_value *root = json_parse(buf);
                    if (root) {
                        json_value *packages = json_get(root, "packages");
                        if (packages && packages->type == JSON_OBJECT) {
                            fclose(tf);
                            free(buf);
                            json_free(root);
                            rename(tmp_json, LPM_REPO_JSON);
                            printf("lpm: repository index updated successfully\n");
                            lpm_unlock();
                            return 0;
                        }
                        json_free(root);
                    }
                }
                free(buf);
            }
            fclose(tf);
        }
    }

    unlink(tmp_json);
    fprintf(stderr, "lpm: failed to update repository index from %s (invalid metadata or network error)\n", url);
    lpm_unlock();
    return 1;
}

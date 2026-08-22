#include "manifest.h"
#include "sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <ctype.h>
#include <unistd.h>

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
    if (argc < 1) { fprintf(stderr, "Usage: lpm search <query>\n"); return 1; }
    const char *query = argv[0];

    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) { printf("No packages found matching '%s'\n", query); return 0; }

    struct dirent *ent;
    int matches = 0;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (!lpm_valid_pkgname(ent->d_name)) continue;
        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
        manifest *m = manifest_load(dbdir);
        if (m) {
            if (contains_icase(m->name, query) || contains_icase(m->description, query)) {
                printf("%-20s %-12s %s\n", m->name, m->version, m->description ? m->description : "");
                matches++;
            }
            manifest_free(m);
        }
    }
    closedir(dir);
    if (matches == 0) printf("No packages found matching '%s'\n", query);
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

        /* Check per-file SHA-256 hash if available in checksum table */
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
    char url[LPM_PATH_MAX];
    get_repo_url(url, sizeof(url));

    printf("lpm: updating repository index from %s...\n", url);
    char cmd[LPM_PATH_MAX * 4 + 256];
    snprintf(cmd, sizeof(cmd), "curl -sSL \"%s/repo.json\" -o \"%s\" 2>/dev/null || wget -q \"%s/repo.json\" -O \"%s\"",
             url, LPM_REPO_JSON, url, LPM_REPO_JSON);

    int res = system(cmd);
    if (res == 0 && access(LPM_REPO_JSON, F_OK) == 0) {
        printf("lpm: repository index updated successfully\n");
        return 0;
    } else {
        fprintf(stderr, "lpm: failed to update repository index from %s\n", url);
        return 1;
    }
}

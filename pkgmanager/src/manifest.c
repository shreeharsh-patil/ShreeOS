#include "manifest.h"
#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

static int mkdir_p(const char *path) {
#ifdef _WIN32
    return _mkdir(path);
#else
    return mkdir(path, 0755);
#endif
}

static char *strdup_safe(const char *s) {
    return s ? strdup(s) : strdup("");
}

/* Emit one JSON string without ever treating package metadata as format text. */
static int json_write_string(FILE *f, const char *value) {
    const unsigned char *p = (const unsigned char *)(value ? value : "");
    if (fputc('"', f) == EOF) return -1;
    for (; *p; ++p) {
        switch (*p) {
            case '"': if (fputs("\\\"", f) == EOF) return -1; break;
            case '\\': if (fputs("\\\\", f) == EOF) return -1; break;
            case '\b': if (fputs("\\b", f) == EOF) return -1; break;
            case '\f': if (fputs("\\f", f) == EOF) return -1; break;
            case '\n': if (fputs("\\n", f) == EOF) return -1; break;
            case '\r': if (fputs("\\r", f) == EOF) return -1; break;
            case '\t': if (fputs("\\t", f) == EOF) return -1; break;
            default:
                if (*p < 0x20) { if (fprintf(f, "\\u%04x", *p) < 0) return -1; }
                else if (fputc(*p, f) == EOF) return -1;
        }
    }
    return fputc('"', f) == EOF ? -1 : 0;
}

static void fill_str_array(const json_value *arr, char ***out, int *n) {
    *n = 0;
    *out = NULL;
    if (!arr || arr->type != JSON_ARRAY) return;
    *n = json_array_len(arr);
    *out = calloc(*n + 1, sizeof(char *));
    if (!*out) return;
    for (int i = 0; i < *n; i++) {
        const char *s = json_array_str(arr, i);
        (*out)[i] = s ? strdup(s) : strdup("");
    }
}

static void fill_checksums(const json_value *obj, checksum_entry **out, int *n) {
    *n = 0;
    *out = NULL;
    if (!obj || obj->type != JSON_OBJECT) return;

    int count = 0;
    for (json_pair *p = obj->head; p; p = p->next) {
        if (p->key && p->value && p->value->type == JSON_STRING) {
            count++;
        }
    }
    if (count == 0) return;

    *out = calloc(count, sizeof(checksum_entry));
    if (!*out) return;

    int idx = 0;
    for (json_pair *p = obj->head; p; p = p->next) {
        if (p->key && p->value && p->value->type == JSON_STRING) {
            (*out)[idx].path = strdup_safe(p->key);
            (*out)[idx].sha256 = strdup_safe(p->value->string);
            idx++;
        }
    }
    *n = idx;
}

manifest *manifest_parse(const char *json_str) {
    json_value *root = json_parse(json_str);
    if (!root) return NULL;

    manifest *m = calloc(1, sizeof(manifest));
    if (!m) { json_free(root); return NULL; }
    m->name        = strdup_safe(json_string(json_get(root, "name")));
    m->version     = strdup_safe(json_string(json_get(root, "version")));
    m->description = strdup_safe(json_string(json_get(root, "description")));
    m->sha256      = strdup_safe(json_string(json_get(root, "sha256")));
    fill_str_array(json_get(root, "dependencies"), &m->deps, &m->ndeps);
    fill_str_array(json_get(root, "files"),        &m->files, &m->nfiles);
    fill_checksums(json_get(root, "checksums"),    &m->checksums, &m->nchecksums);

    json_free(root);
    return m;
}

void manifest_free(manifest *m) {
    if (!m) return;
    free(m->name);
    free(m->version);
    free(m->description);
    free(m->sha256);
    if (m->deps) { for (int i = 0; i < m->ndeps; i++) free(m->deps[i]); free(m->deps); }
    if (m->files) { for (int i = 0; i < m->nfiles; i++) free(m->files[i]); free(m->files); }
    if (m->checksums) {
        for (int i = 0; i < m->nchecksums; i++) {
            free(m->checksums[i].path);
            free(m->checksums[i].sha256);
        }
        free(m->checksums);
    }
    free(m);
}

const char *manifest_get_checksum(const manifest *m, const char *file_path) {
    if (!m || !m->checksums || !file_path) return NULL;
    for (int i = 0; i < m->nchecksums; i++) {
        if (strcmp(m->checksums[i].path, file_path) == 0) {
            return m->checksums[i].sha256;
        }
    }
    return NULL;
}

int manifest_save(const manifest *m, const char *dir) {
    char path[LPM_PATH_MAX], temporary[LPM_PATH_MAX];
    snprintf(path, sizeof(path), "%s/manifest.json", dir);
    if (mkdir_p(dir) != 0 && errno != EEXIST) return -1;
    if (snprintf(temporary, sizeof(temporary), "%s.tmp", path) >= (int)sizeof(temporary)) return -1;

    FILE *f = fopen(temporary, "wb");
    if (!f) return -1;
#ifndef _WIN32
    if (fchmod(fileno(f), 0644) != 0) goto fail;
#endif

    if (fputs("{\n  \"name\": ", f) == EOF || json_write_string(f, m->name) || fputs(",\n  \"version\": ", f) == EOF || json_write_string(f, m->version)) goto fail;
    if (m->description && *m->description) {
        if (fputs(",\n  \"description\": ", f) == EOF || json_write_string(f, m->description)) goto fail;
    }
    if (m->sha256 && *m->sha256) {
        if (fputs(",\n  \"sha256\": ", f) == EOF || json_write_string(f, m->sha256)) goto fail;
    }
    if (fputs(",\n", f) == EOF) goto fail;
    fprintf(f, "  \"dependencies\": [");
    for (int i = 0; i < m->ndeps; i++) {
        if (i > 0) fprintf(f, ", ");
        if (json_write_string(f, m->deps[i])) goto fail;
    }
    fprintf(f, "],\n");
    fprintf(f, "  \"files\": [");
    for (int i = 0; i < m->nfiles; i++) {
        if (i > 0) fprintf(f, ", ");
        if (json_write_string(f, m->files[i])) goto fail;
    }
    fprintf(f, "],\n");
    fprintf(f, "  \"checksums\": {\n");
    for (int i = 0; i < m->nchecksums; i++) {
        if (fputs("    ", f) == EOF || json_write_string(f, m->checksums[i].path) ||
            fputs(": ", f) == EOF || json_write_string(f, m->checksums[i].sha256) ||
            fprintf(f, "%s\n", (i + 1 < m->nchecksums) ? "," : "") < 0) goto fail;
    }
    fprintf(f, "  }\n}\n");

    if (fflush(f) != 0) goto fail;
#ifndef _WIN32
    if (fsync(fileno(f)) != 0) goto fail;
#endif
    if (fclose(f) != 0) { unlink(temporary); return -1; }
    if (rename(temporary, path) != 0) { unlink(temporary); return -1; }
#ifndef _WIN32
    {
        int directory_fd = open(dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (directory_fd < 0) return -1;
        if (fsync(directory_fd) != 0) { close(directory_fd); return -1; }
        close(directory_fd);
    }
#endif
    return 0;
fail:
    fclose(f);
    unlink(temporary);
    return -1;
}

int manifest_check_deps(const manifest *m, char ***missing_out, int *nmissing_out) {
    if (!missing_out || !nmissing_out) return -1;
    *missing_out = NULL;
    *nmissing_out = 0;
    if (!m || m->ndeps <= 0) return 0;

    char **missing = calloc(m->ndeps, sizeof(char *));
    if (!missing) return -1;
    int count = 0;

    for (int i = 0; i < m->ndeps; i++) {
        /* Dep could be "foo" or "foo >= 1.0" */
        char dep_name[128];
        const char *space = strchr(m->deps[i], ' ');
        if (space) {
            size_t n = space - m->deps[i];
            if (n >= sizeof(dep_name)) n = sizeof(dep_name) - 1;
            strncpy(dep_name, m->deps[i], n);
            dep_name[n] = '\0';
        } else {
            strncpy(dep_name, m->deps[i], sizeof(dep_name) - 1);
            dep_name[sizeof(dep_name) - 1] = '\0';
        }

        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", dep_name);
        manifest *dep_m = manifest_load(dbdir);
        if (!dep_m) {
            missing[count++] = strdup(m->deps[i]);
        } else {
            manifest_free(dep_m);
        }
    }

    *missing_out = missing;
    *nmissing_out = count;
    return count;
}

manifest *manifest_load(const char *dir) {
    char path[LPM_PATH_MAX];
    snprintf(path, sizeof(path), "%s/manifest.json", dir);
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    if (len < 0) { fclose(f); return NULL; }
    char *buf = malloc(len + 1);
    if (!buf) { fclose(f); return NULL; }
    if (fread(buf, 1, len, f) != (size_t)len) {
        free(buf); fclose(f); return NULL;
    }
    buf[len] = '\0';
    fclose(f);

    manifest *m = manifest_parse(buf);
    free(buf);
    return m;
}

/* Package name validation: [a-zA-Z0-9][a-zA-Z0-9._-]* */
bool lpm_valid_pkgname(const char *name) {
    if (!name || !*name) return false;
    if (!((name[0] >= 'a' && name[0] <= 'z') ||
          (name[0] >= 'A' && name[0] <= 'Z') ||
          (name[0] >= '0' && name[0] <= '9')))
        return false;
    for (const char *p = name + 1; *p; p++) {
        if (!((*p >= 'a' && *p <= 'z') ||
              (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') ||
              *p == '.' || *p == '_' || *p == '-'))
            return false;
    }
    return true;
}

/* Safe path check: no /../ components and starts with a safe prefix */
bool lpm_safe_path(const char *path) {
    static const char *const allowed[] = { "/bin/", "/sbin/", "/lib/", "/lib64/", "/usr/", "/etc/", "/opt/", "/var/", "/boot/" };
    bool prefix_ok = false;
    if (!path || !*path) return false;
    /* Must start with / */
    if (path[0] != '/') return false;
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); ++i) {
        if (strncmp(path, allowed[i], strlen(allowed[i])) == 0) { prefix_ok = true; break; }
    }
    if (!prefix_ok || strcmp(path, "/var/lib/lpm") == 0 || strncmp(path, "/var/lib/lpm/", 13) == 0 ||
        strcmp(path, "/var/cache/lpm") == 0 || strncmp(path, "/var/cache/lpm/", 15) == 0 ||
        strcmp(path, "/var/run/lpm") == 0 || strncmp(path, "/var/run/lpm/", 13) == 0) return false;
    /* Walk through path, reject lexical ambiguity and traversal. */
    const char *p = path;
    while (*p) {
        /* Check for /../ */
        if (*p == '/' && p[1] == '.' && p[2] == '.' && (p[3] == '/' || p[3] == '\0'))
            return false;
        /* Also reject /.. at end */
        if (p[0] == '.' && p[1] == '.' && (p[2] == '/' || p[2] == '\0'))
            return false;
        if (*p == '/' && (p[1] == '/' || (p[1] == '.' && (p[2] == '/' || p[2] == '\0')))) return false;
        p++;
    }
    return true;
}

/* Semantic / lexical version comparison */
int lpm_version_cmp(const char *v1, const char *v2) {
    if (!v1 && !v2) return 0;
    if (!v1) return -1;
    if (!v2) return 1;

    const char *p1 = v1;
    const char *p2 = v2;

    while (*p1 || *p2) {
        /* If both have digits, compare numerically */
        if (isdigit((unsigned char)*p1) && isdigit((unsigned char)*p2)) {
            unsigned long n1 = strtoul(p1, (char **)&p1, 10);
            unsigned long n2 = strtoul(p2, (char **)&p2, 10);
            if (n1 < n2) return -1;
            if (n1 > n2) return 1;
        } else {
            /* Compare non-digit separator or pre-release char */
            if (*p1 != *p2) {
                return (int)((unsigned char)*p1) - (int)((unsigned char)*p2);
            }
            if (*p1) p1++;
            if (*p2) p2++;
        }
    }
    return 0;
}

bool lpm_is_lpkg_file(const char *path) {
    if (!path) return false;
    size_t len = strlen(path);
    if (len >= 5 && strcmp(path + len - 5, ".lpkg") == 0) return true;
    if (len >= 7 && strcmp(path + len - 7, ".tar.gz") == 0) return true;
    return false;
}

int lpm_repo_lookup(const char *pkgname, char **out_version, char **out_filename, char **out_sha256) {
    if (out_version) *out_version = NULL;
    if (out_filename) *out_filename = NULL;
    if (out_sha256) *out_sha256 = NULL;

    FILE *f = fopen(LPM_REPO_JSON, "rb");
    if (!f) return -1;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    if (len < 0) { fclose(f); return -1; }
    char *buf = malloc(len + 1);
    if (!buf) { fclose(f); return -1; }
    if (fread(buf, 1, len, f) != (size_t)len) {
        free(buf); fclose(f); return -1;
    }
    buf[len] = '\0';
    fclose(f);

    json_value *root = json_parse(buf);
    free(buf);
    if (!root) return -1;

    json_value *packages = json_get(root, "packages");
    if (!packages || packages->type != JSON_OBJECT) {
        json_free(root);
        return -1;
    }

    json_value *pkg_obj = json_get(packages, pkgname);
    if (!pkg_obj || pkg_obj->type != JSON_OBJECT) {
        json_free(root);
        return -1;
    }

    const char *ver = json_string(json_get(pkg_obj, "version"));
    const char *fn = json_string(json_get(pkg_obj, "filename"));
    const char *sha = json_string(json_get(pkg_obj, "sha256"));

    if (out_version) *out_version = ver ? strdup(ver) : strdup("0.0");
    if (out_filename) *out_filename = fn ? strdup(fn) : strdup("");
    if (out_sha256) *out_sha256 = sha ? strdup(sha) : strdup("");

    json_free(root);
    return 0;
}

#include <fcntl.h>
#include <dirent.h>

#ifndef _WIN32
#include <sys/file.h>
#endif

#ifndef _WIN32
static int lock_fd = -1;
#endif

int lpm_lock(void) {
#ifndef _WIN32
    mkdir_p(LPM_DB);
    lock_fd = open(LPM_LOCK_FILE, O_RDWR | O_CREAT, 0600);
    if (lock_fd < 0) {
        fprintf(stderr, "lpm: error: cannot create or open transaction lock %s: %s\n",
                LPM_LOCK_FILE, strerror(errno));
        return -1;
    }
    if (flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "lpm: error: another package manager transaction is currently running.\n");
        close(lock_fd);
        lock_fd = -1;
        return -1;
    }
#endif
    return 0;
}

void lpm_unlock(void) {
#ifndef _WIN32
    if (lock_fd >= 0) {
        flock(lock_fd, LOCK_UN);
        close(lock_fd);
        lock_fd = -1;
    }
#endif
}

int lpm_check_file_conflicts(const manifest *m) {
    if (!m || !m->name) return 0;
    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) return 0;

    struct dirent *ent;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (strcmp(ent->d_name, m->name) == 0) continue; /* Same package upgrade */

        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
        manifest *other = manifest_load(dbdir);
        if (!other) continue;

        for (int i = 0; i < m->nfiles; i++) {
            for (int j = 0; j < other->nfiles; j++) {
                if (strcmp(m->files[i], other->files[j]) == 0) {
                    fprintf(stderr, "lpm: file conflict: '%s' is already owned by package '%s'\n",
                            m->files[i], other->name);
                    manifest_free(other);
                    closedir(dir);
                    return -1;
                }
            }
        }
        manifest_free(other);
    }
    closedir(dir);
    return 0;
}

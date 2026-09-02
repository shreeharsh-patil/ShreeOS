#include "manifest.h"
#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <dirent.h>
#include <signal.h>

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
    char tmp[LPM_PATH_MAX];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (len == 0) return 0;
    if (tmp[len - 1] == '/') tmp[len - 1] = 0;

    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return (mkdir(tmp, 0755) == 0 || errno == EEXIST) ? 0 : -1;
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
    fill_str_array(json_get(root, "conflicts"),    &m->conflicts, &m->nconflicts);
    fill_str_array(json_get(root, "provides"),     &m->provides,  &m->nprovides);
    fill_str_array(json_get(root, "replaces"),     &m->replaces,  &m->nreplaces);
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
    if (m->conflicts) { for (int i = 0; i < m->nconflicts; i++) free(m->conflicts[i]); free(m->conflicts); }
    if (m->provides) { for (int i = 0; i < m->nprovides; i++) free(m->provides[i]); free(m->provides); }
    if (m->replaces) { for (int i = 0; i < m->nreplaces; i++) free(m->replaces[i]); free(m->replaces); }
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
    if (snprintf(temporary, sizeof(temporary), "%s.tmp.%d", path, (int)getpid()) >= (int)sizeof(temporary)) return -1;

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
    if (m->nconflicts > 0) {
        fprintf(f, "  \"conflicts\": [");
        for (int i = 0; i < m->nconflicts; i++) {
            if (i > 0) fprintf(f, ", ");
            if (json_write_string(f, m->conflicts[i])) goto fail;
        }
        fprintf(f, "],\n");
    }
    if (m->nprovides > 0) {
        fprintf(f, "  \"provides\": [");
        for (int i = 0; i < m->nprovides; i++) {
            if (i > 0) fprintf(f, ", ");
            if (json_write_string(f, m->provides[i])) goto fail;
        }
        fprintf(f, "],\n");
    }
    if (m->nreplaces > 0) {
        fprintf(f, "  \"replaces\": [");
        for (int i = 0; i < m->nreplaces; i++) {
            if (i > 0) fprintf(f, ", ");
            if (json_write_string(f, m->replaces[i])) goto fail;
        }
        fprintf(f, "],\n");
    }
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

bool lpm_parse_dep_spec(const char *dep_spec, char *name_out, size_t name_sz,
                        char *op_out, size_t op_sz, char *ver_out, size_t ver_sz) {
    if (!dep_spec || !*dep_spec) return false;
    name_out[0] = '\0';
    op_out[0] = '\0';
    ver_out[0] = '\0';

    const char *p = dep_spec;
    while (*p == ' ' || *p == '\t') p++;

    size_t ni = 0;
    while (*p && (isalnum((unsigned char)*p) || *p == '.' || *p == '_' || *p == '-')) {
        if (ni + 1 < name_sz) name_out[ni++] = *p;
        p++;
    }
    name_out[ni] = '\0';
    if (ni == 0) return false;

    while (*p == ' ' || *p == '\t') p++;
    if (!*p) return true;

    size_t oi = 0;
    while (*p == '>' || *p == '<' || *p == '=' || *p == '!') {
        if (oi + 1 < op_sz) op_out[oi++] = *p;
        p++;
    }
    op_out[oi] = '\0';

    while (*p == ' ' || *p == '\t') p++;

    size_t vi = 0;
    while (*p && *p != ' ' && *p != '\t' && *p != ')') {
        if (vi + 1 < ver_sz) ver_out[vi++] = *p;
        p++;
    }
    ver_out[vi] = '\0';

    return true;
}

bool lpm_version_matches(const char *installed_ver, const char *op, const char *req_ver) {
    if (!op || !*op || !req_ver || !*req_ver) return true;
    if (!installed_ver || !*installed_ver) return false;

    int cmp = lpm_version_cmp(installed_ver, req_ver);
    if (strcmp(op, ">=") == 0) return cmp >= 0;
    if (strcmp(op, "<=") == 0) return cmp <= 0;
    if (strcmp(op, ">") == 0)  return cmp > 0;
    if (strcmp(op, "<") == 0)  return cmp < 0;
    if (strcmp(op, "=") == 0 || strcmp(op, "==") == 0) return cmp == 0;
    if (strcmp(op, "!=") == 0) return cmp != 0;
    return false;
}

bool lpm_is_provided(const char *cap_name, char *provider_name_out, size_t provider_sz) {
    if (!cap_name || !*cap_name) return false;
    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) return false;

    struct dirent *ent;
    bool found = false;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), "%s/%s", LPM_INSTALLED, ent->d_name);
        manifest *other = manifest_load(dbdir);
        if (!other) continue;

        for (int i = 0; i < other->nprovides; i++) {
            if (strcmp(other->provides[i], cap_name) == 0) {
                found = true;
                if (provider_name_out && provider_sz > 0) {
                    strncpy(provider_name_out, other->name, provider_sz - 1);
                    provider_name_out[provider_sz - 1] = '\0';
                }
                manifest_free(other);
                goto done;
            }
        }
        manifest_free(other);
    }
done:
    closedir(dir);
    return found;
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
        char dep_name[128] = {0};
        char op[16] = {0};
        char req_ver[64] = {0};

        if (!lpm_parse_dep_spec(m->deps[i], dep_name, sizeof(dep_name),
                                op, sizeof(op), req_ver, sizeof(req_ver))) {
            missing[count++] = strdup(m->deps[i]);
            continue;
        }

        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", dep_name);
        manifest *dep_m = manifest_load(dbdir);

        if (dep_m) {
            if (!lpm_version_matches(dep_m->version, op, req_ver)) {
                missing[count++] = strdup(m->deps[i]);
            }
            manifest_free(dep_m);
        } else {
            /* Check if provided by another installed package */
            if (!lpm_is_provided(dep_name, NULL, 0)) {
                missing[count++] = strdup(m->deps[i]);
            }
        }
    }

    *missing_out = missing;
    *nmissing_out = count;
    return count;
}

int lpm_check_conflicts(const manifest *m, char *conflict_reason, size_t reason_sz) {
    if (!m || !m->name) return 0;
    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) return 0;

    struct dirent *ent;
    int conflict_found = 0;

    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (strcmp(ent->d_name, m->name) == 0) continue;

        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), "%s/%s", LPM_INSTALLED, ent->d_name);
        manifest *other = manifest_load(dbdir);
        if (!other) continue;

        for (int i = 0; i < m->nconflicts; i++) {
            if (strcmp(m->conflicts[i], other->name) == 0) {
                if (conflict_reason && reason_sz > 0) {
                    snprintf(conflict_reason, reason_sz, "package '%s' conflicts with installed package '%s'", m->name, other->name);
                }
                conflict_found = 1;
                manifest_free(other);
                goto done;
            }
            for (int p = 0; p < other->nprovides; p++) {
                if (strcmp(m->conflicts[i], other->provides[p]) == 0) {
                    if (conflict_reason && reason_sz > 0) {
                        snprintf(conflict_reason, reason_sz, "package '%s' conflicts with capability '%s' (provided by '%s')", m->name, other->provides[p], other->name);
                    }
                    conflict_found = 1;
                    manifest_free(other);
                    goto done;
                }
            }
        }

        for (int i = 0; i < other->nconflicts; i++) {
            if (strcmp(other->conflicts[i], m->name) == 0) {
                if (conflict_reason && reason_sz > 0) {
                    snprintf(conflict_reason, reason_sz, "installed package '%s' conflicts with '%s'", other->name, m->name);
                }
                conflict_found = 1;
                manifest_free(other);
                goto done;
            }
            for (int p = 0; p < m->nprovides; p++) {
                if (strcmp(other->conflicts[i], m->provides[p]) == 0) {
                    if (conflict_reason && reason_sz > 0) {
                        snprintf(conflict_reason, reason_sz, "installed package '%s' conflicts with capability '%s' (provided by '%s')", other->name, m->provides[p], m->name);
                    }
                    conflict_found = 1;
                    manifest_free(other);
                    goto done;
                }
            }
        }

        manifest_free(other);
    }
done:
    closedir(dir);
    return conflict_found;
}

int lpm_find_dependents(const char *pkgname, char ***deps_out, int *ndeps_out) {
    if (!deps_out || !ndeps_out || !pkgname || !*pkgname) return -1;
    *deps_out = NULL;
    *ndeps_out = 0;

    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) return 0;

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), "%s/%s", LPM_INSTALLED, pkgname);
    manifest *target = manifest_load(dbdir);

    char **result = NULL;
    int count = 0;

    struct dirent *ent;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (strcmp(ent->d_name, pkgname) == 0) continue;

        char other_dir[LPM_PATH_MAX];
        snprintf(other_dir, sizeof(other_dir), "%s/%s", LPM_INSTALLED, ent->d_name);
        manifest *other = manifest_load(other_dir);
        if (!other) continue;

        bool depends = false;
        for (int i = 0; i < other->ndeps; i++) {
            char dep_name[128];
            char op[16];
            char ver[64];
            lpm_parse_dep_spec(other->deps[i], dep_name, sizeof(dep_name), op, sizeof(op), ver, sizeof(ver));

            if (strcmp(dep_name, pkgname) == 0) {
                depends = true;
                break;
            }
            if (target) {
                for (int p = 0; p < target->nprovides; p++) {
                    if (strcmp(dep_name, target->provides[p]) == 0) {
                        depends = true;
                        break;
                    }
                }
            }
            if (depends) break;
        }

        if (depends) {
            char **new_res = realloc(result, (count + 1) * sizeof(char *));
            if (new_res) {
                result = new_res;
                result[count++] = strdup(other->name);
            }
        }
        manifest_free(other);
    }
    closedir(dir);
    if (target) manifest_free(target);

    *deps_out = result;
    *ndeps_out = count;
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

static const char *get_lock_file(char *buf, size_t buf_sz) {
    const char *env = getenv("LPM_LOCK_FILE");
    if (env && *env) return env;
    const char *db = getenv("LPM_DB_DIR");
    if (db && *db) {
        snprintf(buf, buf_sz, "%s/lock", db);
        return buf;
    }
    return LPM_LOCK_FILE;
}

int lpm_lock(void) {
#ifndef _WIN32
    char lock_path_buf[LPM_PATH_MAX];
    const char *lock_file = get_lock_file(lock_path_buf, sizeof(lock_path_buf));

    char dir_buf[LPM_PATH_MAX];
    snprintf(dir_buf, sizeof(dir_buf), "%s", lock_file);
    char *slash = strrchr(dir_buf, '/');
    if (slash) {
        *slash = '\0';
        mkdir_p(dir_buf);
    }

    for (int attempt = 0; attempt < 30; attempt++) {
        lock_fd = open(lock_file, O_RDWR | O_CREAT, 0600);
        if (lock_fd < 0) {
            fprintf(stderr, "lpm: error: cannot create or open transaction lock %s: %s\n",
                    lock_file, strerror(errno));
            return -1;
        }

        if (flock(lock_fd, LOCK_EX | LOCK_NB) == 0) {
            /* Lock acquired: record PID */
            if (ftruncate(lock_fd, 0) == 0) {
                char pid_str[32];
                snprintf(pid_str, sizeof(pid_str), "%d\n", (int)getpid());
                ssize_t w = write(lock_fd, pid_str, strlen(pid_str));
                (void)w;
                fsync(lock_fd);
            }
            return 0;
        }

        /* Check if process holding lock is still alive */
        char pid_buf[32] = {0};
        pid_t holder_pid = 0;
        ssize_t r = pread(lock_fd, pid_buf, sizeof(pid_buf) - 1, 0);
        if (r > 0) {
            holder_pid = (pid_t)atoi(pid_buf);
        }

        if (holder_pid > 0 && kill(holder_pid, 0) == -1 && errno == ESRCH) {
            fprintf(stderr, "lpm: notice: reclaiming stale lock from defunct process PID %d\n", (int)holder_pid);
            unlink(lock_file);
            close(lock_fd);
            lock_fd = -1;
            usleep(50000);
            continue;
        }

        close(lock_fd);
        lock_fd = -1;
        if (attempt == 0 && holder_pid > 0) {
            fprintf(stderr, "lpm: waiting for package transaction lock held by PID %d...\n", (int)holder_pid);
        }
        usleep(100000); /* 100ms */
    }

    fprintf(stderr, "lpm: error: another package manager transaction is currently running.\n");
    return -1;
#else
    return 0;
#endif
}

void lpm_unlock(void) {
#ifndef _WIN32
    if (lock_fd >= 0) {
        if (ftruncate(lock_fd, 0) != 0) { /* ignore */ }
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

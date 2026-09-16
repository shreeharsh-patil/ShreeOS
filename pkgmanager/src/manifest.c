#include "manifest.h"
#include "json.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
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

static void fill_str_array(const json_value *arr, char ***out, int *n) {
    *n = 0;
    *out = NULL;
    if (!arr || arr->type != JSON_ARRAY) return;
    *n = json_array_len(arr);
    *out = calloc(*n + 1, sizeof(char *));
    for (int i = 0; i < *n; i++) {
        const char *s = json_array_str(arr, i);
        (*out)[i] = s ? strdup(s) : strdup("");
    }
}

manifest *manifest_parse(const char *json_str) {
    json_value *root = json_parse(json_str);
    if (!root) return NULL;

    manifest *m = calloc(1, sizeof(manifest));
    m->name        = strdup_safe(json_string(json_get(root, "name")));
    m->version     = strdup_safe(json_string(json_get(root, "version")));
    m->description = strdup_safe(json_string(json_get(root, "description")));
    fill_str_array(json_get(root, "dependencies"), &m->deps, &m->ndeps);
    fill_str_array(json_get(root, "files"),        &m->files, &m->nfiles);

    json_free(root);
    return m;
}

void manifest_free(manifest *m) {
    if (!m) return;
    free(m->name);
    free(m->version);
    free(m->description);
    if (m->deps) { for (int i = 0; i < m->ndeps; i++) free(m->deps[i]); free(m->deps); }
    if (m->files) { for (int i = 0; i < m->nfiles; i++) free(m->files[i]); free(m->files); }
    free(m);
}

int manifest_save(const manifest *m, const char *dir) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/manifest.json", dir);
    mkdir_p(dir);

    FILE *f = fopen(path, "w");
    if (!f) return -1;

    fprintf(f, "{\n");
    fprintf(f, "  \"name\": \"%s\",\n", m->name);
    fprintf(f, "  \"version\": \"%s\",\n", m->version);
    if (m->description && *m->description)
        fprintf(f, "  \"description\": \"%s\",\n", m->description);
    fprintf(f, "  \"files\": [");
    for (int i = 0; i < m->nfiles; i++) {
        if (i > 0) fprintf(f, ",");
        fprintf(f, "\"%s\"", m->files[i]);
    }
    fprintf(f, "]\n}\n");

    fclose(f);
    return 0;
}

manifest *manifest_load(const char *dir) {
    char path[4096];
    snprintf(path, sizeof(path), "%s/manifest.json", dir);
    FILE *f = fopen(path, "r");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    char *buf = malloc(len + 1);
    fread(buf, 1, len, f);
    buf[len] = '\0';
    fclose(f);

    manifest *m = manifest_parse(buf);
    free(buf);
    return m;
}

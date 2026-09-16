#ifndef LPM_MANIFEST_H
#define LPM_MANIFEST_H

#include <stdbool.h>

#define LPM_DB "/var/lib/lpm"
#define LPM_INSTALLED LPM_DB "/installed"

/* Path buffer size: Linux PATH_MAX = 4096, ensure we match target */
#ifndef LPM_PATH_MAX
#define LPM_PATH_MAX 4096
#endif

typedef struct {
    char *name;
    char *version;
    char *description;
    int ndeps;
    char **deps;
    int nfiles;
    char **files;
} manifest;

manifest *manifest_parse(const char *json_str);
void       manifest_free(manifest *m);
int        manifest_save(const manifest *m, const char *path);
manifest *manifest_load(const char *path);

/*
 * Validate a package name for safety.
 * Package names must match [a-zA-Z0-9][a-zA-Z0-9._-]*
 * Returns true if valid, false if rejected.
 */
bool lpm_valid_pkgname(const char *name);

/*
 * Check if a file path is within the allowed install prefix.
 * Rejects paths containing /../ or that don't start with a safe prefix.
 * Returns true if safe to remove.
 */
bool lpm_safe_path(const char *path);

#endif

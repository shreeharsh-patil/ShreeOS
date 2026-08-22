#ifndef LPM_MANIFEST_H
#define LPM_MANIFEST_H

#include <stdbool.h>
#include <stddef.h>

#define LPM_DB "/var/lib/lpm"
#define LPM_INSTALLED LPM_DB "/installed"
#define LPM_REPO_JSON LPM_DB "/repo.json"
#define LPM_REPOS_CONF "/etc/lpm/repos.conf"
#define LPM_CACHE_DIR "/var/cache/lpm/pkg"

/* Path buffer size: Linux PATH_MAX = 4096, ensure we match target */
#ifndef LPM_PATH_MAX
#define LPM_PATH_MAX 4096
#endif

typedef struct {
    char *path;
    char *sha256;
} checksum_entry;

typedef struct {
    char *name;
    char *version;
    char *description;
    char *sha256;
    int ndeps;
    char **deps;
    int nfiles;
    char **files;
    int nchecksums;
    checksum_entry *checksums;
} manifest;

manifest *manifest_parse(const char *json_str);
void       manifest_free(manifest *m);
int        manifest_save(const manifest *m, const char *dir);
manifest *manifest_load(const char *dir);
int        manifest_check_deps(const manifest *m, char ***missing_out, int *nmissing_out);
const char *manifest_get_checksum(const manifest *m, const char *file_path);

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

/*
 * Semantic version comparison.
 * Returns:
 *   < 0 if v1 < v2
 *     0 if v1 == v2
 *   > 0 if v1 > v2
 */
int lpm_version_cmp(const char *v1, const char *v2);

/*
 * Checks whether a path string points to an .lpkg archive file.
 */
bool lpm_is_lpkg_file(const char *path);

/*
 * Look up a package in /var/lib/lpm/repo.json
 * Fills heap-allocated strings for out_version, out_filename, out_sha256 (caller frees).
 * Returns 0 on success, -1 if not found.
 */
int lpm_repo_lookup(const char *pkgname, char **out_version, char **out_filename, char **out_sha256);

#endif

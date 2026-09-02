#ifndef LPM_MANIFEST_H
#define LPM_MANIFEST_H

#include <stdbool.h>
#include <stddef.h>

#define LPM_DB "/var/lib/lpm"
#define LPM_INSTALLED LPM_DB "/installed"
#define LPM_REPO_JSON LPM_DB "/repo.json"
#define LPM_REPOS_CONF "/etc/lpm/repos.conf"
#define LPM_CACHE_DIR "/var/cache/lpm/pkg"
#define LPM_LOCK_FILE LPM_DB "/lock"
#define LPM_TRANSACTIONS LPM_DB "/transactions"

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
    int nconflicts;
    char **conflicts;
    int nprovides;
    char **provides;
    int nreplaces;
    char **replaces;
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

/* Version constraint parsing & matching */
bool lpm_parse_dep_spec(const char *dep_spec, char *name_out, size_t name_sz,
                        char *op_out, size_t op_sz, char *ver_out, size_t ver_sz);
bool lpm_version_matches(const char *installed_ver, const char *op, const char *req_ver);

/* Virtual package capability check */
bool lpm_is_provided(const char *cap_name, char *provider_name_out, size_t provider_sz);

/* Package conflicts check */
int lpm_check_conflicts(const manifest *m, char *conflict_reason, size_t reason_sz);

/* Dependency-aware removal: find installed packages that depend on pkgname */
int lpm_find_dependents(const char *pkgname, char ***deps_out, int *ndeps_out);

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

/*
 * Exclusive process locking around package mutations
 */
int lpm_lock(void);
void lpm_unlock(void);

/*
 * File conflict detection across installed package database
 */
int lpm_check_file_conflicts(const manifest *m);

/* Command declarations */
int cmd_install(int argc, char **argv);
int cmd_remove(int argc, char **argv);
int cmd_upgrade(int argc, char **argv);
int cmd_query(int argc, char **argv);
int cmd_list(int argc, char **argv);
int cmd_search(int argc, char **argv);
int cmd_verify(int argc, char **argv);
int cmd_update(int argc, char **argv);
int cmd_info(int argc, char **argv);
int cmd_history(int argc, char **argv);
int cmd_rollback(int argc, char **argv);
int cmd_repair(int argc, char **argv);

#endif

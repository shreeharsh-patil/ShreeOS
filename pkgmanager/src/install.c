#include "manifest.h"
#include "sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>

static int mkdir_p(const char *path) {
    char tmp[LPM_PATH_MAX];
    char *p = NULL;
    size_t len;

    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    if (tmp[len - 1] == '/') tmp[len - 1] = 0;
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return mkdir(tmp, 0755);
}

static int safe_exec(const char *file, char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
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

static int download_package(const char *pkgname, char *out_path, size_t maxlen, char *expected_sha, size_t sha_len) {
    char *version = NULL, *filename = NULL, *sha256 = NULL;
    if (lpm_repo_lookup(pkgname, &version, &filename, &sha256) != 0) {
        fprintf(stderr, "lpm: package '%s' not found in repository index\n", pkgname);
        return -1;
    }

    if (!sha256 || !*sha256) {
        fprintf(stderr, "lpm: security error: missing expected SHA256 checksum in repository metadata for '%s'\n", pkgname);
        free(version); free(filename); free(sha256);
        return -1;
    }

    strncpy(expected_sha, sha256, sha_len - 1);
    expected_sha[sha_len - 1] = '\0';

    char repo_url[LPM_PATH_MAX];
    get_repo_url(repo_url, sizeof(repo_url));

    mkdir_p(LPM_CACHE_DIR);
    const char *basename_fn = strrchr(filename, '/');
    basename_fn = basename_fn ? basename_fn + 1 : filename;
    snprintf(out_path, maxlen, "%s/%s", LPM_CACHE_DIR, basename_fn);

    char pkg_download_url[LPM_PATH_MAX * 2];
    snprintf(pkg_download_url, sizeof(pkg_download_url), "%s/%s", repo_url, filename);

    printf("lpm: downloading %s from %s...\n", pkgname, pkg_download_url);

    char *curl_args[] = { "curl", "-sSL", pkg_download_url, "-o", out_path, NULL };
    char *wget_args[] = { "wget", "-q", pkg_download_url, "-O", out_path, NULL };

    int res = safe_exec("curl", curl_args);
    if (res != 0) {
        res = safe_exec("wget", wget_args);
    }

    free(version);
    free(filename);
    free(sha256);

    if (res != 0 || access(out_path, F_OK) != 0) {
        fprintf(stderr, "lpm: failed to download package '%s'\n", pkgname);
        return -1;
    }
    return 0;
}

/* Validate all archive member paths before extracting */
static int validate_archive_members(const char *lpkg_path) {
    int pipefd[2];
    if (pipe(pipefd) != 0) return -1;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]); close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        int devnull = open("/dev/null", 0666);
        if (devnull >= 0) dup2(devnull, STDERR_FILENO);
        close(pipefd[1]);
        execlp("tar", "tar", "-ztf", lpkg_path, (char *)NULL);
        _exit(127);
    }

    close(pipefd[1]);
    FILE *stream = fdopen(pipefd[0], "r");
    if (!stream) {
        close(pipefd[0]);
        waitpid(pid, NULL, 0);
        return -1;
    }

    char line[LPM_PATH_MAX];
    int valid = 1;

    while (fgets(line, sizeof(line), stream)) {
        size_t len = strlen(line);
        if (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
        if (len == 0) continue;

        /* Reject absolute paths */
        if (line[0] == '/') {
            fprintf(stderr, "lpm: security error: archive member has absolute path '%s'\n", line);
            valid = 0;
            break;
        }

        /* Reject directory traversal */
        if (strstr(line, "..") != NULL) {
            fprintf(stderr, "lpm: security error: archive member contains directory traversal '%s'\n", line);
            valid = 0;
            break;
        }
    }

    fclose(stream);
    int status;
    waitpid(pid, &status, 0);
    return (valid && WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : -1;
}

static int copy_file(const char *src, const char *dst) {
    char *args[] = { "cp", "-a", (char *)src, (char *)dst, NULL };
    return safe_exec("cp", args);
}

static int remove_tree(const char *path) {
    char *args[] = { "rm", "-rf", (char *)path, NULL };
    return safe_exec("rm", args);
}

int cmd_install(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm install <package-name | file.lpkg>\n"); return 1; }
    if (lpm_lock() != 0) return 1;

    char lpkg_path[LPM_PATH_MAX];
    char expected_sha[65] = {0};

    if (!lpm_is_lpkg_file(argv[0])) {
        if (!lpm_valid_pkgname(argv[0])) {
            fprintf(stderr, "lpm: invalid package name '%s'\n", argv[0]);
            lpm_unlock();
            return 1;
        }
        if (download_package(argv[0], lpkg_path, sizeof(lpkg_path), expected_sha, sizeof(expected_sha)) != 0) {
            lpm_unlock();
            return 1;
        }
    } else {
        strncpy(lpkg_path, argv[0], sizeof(lpkg_path) - 1);
        lpkg_path[sizeof(lpkg_path) - 1] = '\0';
    }

    /* 1. Fail closed on archive checksum if expected SHA is defined */
    if (expected_sha[0] != '\0') {
        char actual_sha[65] = {0};
        if (lpm_sha256_file(lpkg_path, actual_sha) != 0 || strcmp(expected_sha, actual_sha) != 0) {
            fprintf(stderr, "lpm: FATAL: SHA256 mismatch for %s\n  expected: %s\n  got:      %s\n",
                    lpkg_path, expected_sha, actual_sha);
            lpm_unlock();
            return 1;
        }
        printf("lpm: package archive integrity verified (SHA256: %.12s...)\n", actual_sha);
    }

    /* 2. Validate archive members before extraction */
    if (validate_archive_members(lpkg_path) != 0) {
        fprintf(stderr, "lpm: security violation in archive structure: %s\n", lpkg_path);
        lpm_unlock();
        return 1;
    }

    char tmpdir[] = "/tmp/lpm-stage-XXXXXX";
    if (!mkdtemp(tmpdir)) { perror("mkdtemp"); lpm_unlock(); return 1; }

    int ret = 0;
    manifest *m = NULL;
    manifest *old_m = NULL;
    int files_backed_up = 0;
    char transaction_dir[LPM_PATH_MAX] = {0};
    char transaction_status[LPM_PATH_MAX] = {0};
    char rollback_ledger[LPM_PATH_MAX] = {0};

    /* 3. Extract manifest.json */
    char manifest_extract_dir[LPM_PATH_MAX];
    snprintf(manifest_extract_dir, sizeof(manifest_extract_dir), "%s", tmpdir);
    char *tar_manifest_args[] = { "tar", "-xzf", lpkg_path, "-C", manifest_extract_dir, "manifest.json", NULL };
    if (safe_exec("tar", tar_manifest_args) != 0) {
        fprintf(stderr, "lpm: no valid manifest.json found in %s\n", lpkg_path);
        ret = 1;
        goto cleanup;
    }

    m = manifest_load(tmpdir);
    if (!m || !m->name || !*m->name) {
        fprintf(stderr, "lpm: invalid manifest in %s\n", lpkg_path);
        ret = 1;
        goto cleanup;
    }

    if (!lpm_valid_pkgname(m->name)) {
        fprintf(stderr, "lpm: manifest has invalid package name '%s'\n", m->name);
        ret = 1;
        goto cleanup;
    }

    /* 4. Check dependencies */
    char **missing_deps = NULL;
    int nmissing = 0;
    if (manifest_check_deps(m, &missing_deps, &nmissing) > 0) {
        fprintf(stderr, "lpm: error: missing dependencies for %s:\n", m->name);
        for (int i = 0; i < nmissing; i++) {
            fprintf(stderr, "  - %s\n", missing_deps[i]);
            free(missing_deps[i]);
        }
        free(missing_deps);
        ret = 1;
        goto cleanup;
    }

    /* 5. Validate file paths in manifest */
    for (int i = 0; i < m->nfiles; i++) {
        if (!lpm_safe_path(m->files[i])) {
            fprintf(stderr, "lpm: security violation: unsafe path '%s' in package\n", m->files[i]);
            ret = 1;
            goto cleanup;
        }
    }

    /* 6. Detect file ownership conflicts */
    if (lpm_check_file_conflicts(m) != 0) {
        fprintf(stderr, "lpm: transaction aborted: file conflict with installed package\n");
        ret = 1;
        goto cleanup;
    }

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", m->name);
    old_m = manifest_load(dbdir);

    printf("lpm: preparing transaction for %s-%s\n", m->name, m->version);

    /* 7. Extract payload into staging area */
    char stage_root[LPM_PATH_MAX];
    snprintf(stage_root, sizeof(stage_root), "%s/root", tmpdir);
    mkdir_p(stage_root);

    char *tar_payload_args[] = { "tar", "-xzf", lpkg_path, "-C", stage_root, "--exclude=manifest.json", NULL };
    if (safe_exec("tar", tar_payload_args) != 0) {
        fprintf(stderr, "lpm: failed to extract payload into staging area\n");
        ret = 1;
        goto cleanup;
    }

    /* 8. Verify per-file checksums in staging */
    if (m->nchecksums > 0) {
        int checksum_mismatches = 0;
        for (int i = 0; i < m->nchecksums; i++) {
            char file_in_stage[LPM_PATH_MAX];
            snprintf(file_in_stage, sizeof(file_in_stage), "%s/root%s", tmpdir, m->checksums[i].path);
            char file_sha[65] = {0};
            if (lpm_sha256_file(file_in_stage, file_sha) != 0 ||
                strcmp(file_sha, m->checksums[i].sha256) != 0) {
                fprintf(stderr, "lpm: checksum mismatch for staged file %s\n", m->checksums[i].path);
                checksum_mismatches++;
            }
        }
        if (checksum_mismatches > 0) {
            fprintf(stderr, "lpm: %d file checksum mismatch(es) in payload. Aborting transaction.\n", checksum_mismatches);
            ret = 1;
            goto cleanup;
        }
        printf("lpm: verified %d per-file checksum(s)\n", m->nchecksums);
    }

    /* 9. Prepare Rollback Backups for existing files */
    char backup_dir[LPM_PATH_MAX];
    snprintf(transaction_dir, sizeof(transaction_dir), "%s/%ld-%ld", LPM_TRANSACTIONS,
             (long)time(NULL), (long)getpid());
    snprintf(transaction_status, sizeof(transaction_status), "%s/status", transaction_dir);
    snprintf(rollback_ledger, sizeof(rollback_ledger), "%s/rollback/ledger", transaction_dir);
    snprintf(backup_dir, sizeof(backup_dir), "%s/rollback/files", transaction_dir);
    if (mkdir_p(backup_dir) != 0 && errno != EEXIST) { ret = 1; goto cleanup; }
    {
        FILE *status = fopen(transaction_status, "w");
        FILE *packages = NULL;
        if (!status) { ret = 1; goto cleanup; }
        fprintf(status, "prepared\n"); fclose(status);
        packages = fopen(rollback_ledger, "w");
        if (!packages) { ret = 1; goto cleanup; }
        fprintf(packages, "# transaction=%s package=%s old=%s new=%s\n", transaction_dir,
                m->name, old_m && old_m->version ? old_m->version : "none", m->version);
        fclose(packages);
    }

    int *file_existed = calloc(m->nfiles, sizeof(int));
    if (!file_existed) { ret = 1; goto cleanup; }

    for (int i = 0; i < m->nfiles; i++) {
        FILE *ledger = fopen(rollback_ledger, "a");
        if (!ledger) { ret = 1; goto cleanup; }
        if (access(m->files[i], F_OK) == 0) {
            file_existed[i] = 1;
            char backup_file[LPM_PATH_MAX];
            snprintf(backup_file, sizeof(backup_file), "%s%s", backup_dir, m->files[i]);
            char *last_slash = strrchr(backup_file, '/');
            if (last_slash) {
                *last_slash = '\0';
                mkdir_p(backup_file);
                *last_slash = '/';
            }
            if (copy_file(m->files[i], backup_file) != 0) { fclose(ledger); ret = 1; goto cleanup; }
            fprintf(ledger, "E %s\n", m->files[i]);
            files_backed_up++;
        } else {
            fprintf(ledger, "N %s\n", m->files[i]);
        }
        fclose(ledger);
    }

    /* 10. Atomic Commit: Copy staged files to root */
    printf("lpm: committing %s-%s to system root\n", m->name, m->version);
    char stage_source[LPM_PATH_MAX];
    snprintf(stage_source, sizeof(stage_source), "%s/root/.", tmpdir);
    char *commit_args[] = { "cp", "-a", stage_source, "/", NULL };

    if (safe_exec("cp", commit_args) != 0) {
        fprintf(stderr, "lpm: transaction failed during commit to rootfs. Rolling back...\n");
        /* Rollback: restore backed up files and remove newly added files */
        for (int i = 0; i < m->nfiles; i++) {
            if (file_existed[i]) {
                char backup_file[LPM_PATH_MAX];
                snprintf(backup_file, sizeof(backup_file), "%s%s", backup_dir, m->files[i]);
                copy_file(backup_file, m->files[i]);
            } else {
                unlink(m->files[i]);
            }
        }
        free(file_existed);
        ret = 1;
        goto cleanup;
    }

    /* 11. Update installed database */
    mkdir_p(LPM_INSTALLED);
    mkdir_p(dbdir);
    if (manifest_save(m, dbdir) != 0) {
        fprintf(stderr, "lpm: failed to write installed database entry. Rolling back...\n");
        for (int i = 0; i < m->nfiles; i++) {
            if (file_existed[i]) {
                char backup_file[LPM_PATH_MAX];
                snprintf(backup_file, sizeof(backup_file), "%s%s", backup_dir, m->files[i]);
                copy_file(backup_file, m->files[i]);
            } else {
                unlink(m->files[i]);
            }
        }
        free(file_existed);
        ret = 1;
        goto cleanup;
    }
    free(file_existed);

    /* 12. Cleanup obsolete files from previous package version */
    if (old_m) {
        for (int i = 0; i < old_m->nfiles; i++) {
            bool still_present = false;
            for (int j = 0; j < m->nfiles; j++) {
                if (strcmp(old_m->files[i], m->files[j]) == 0) {
                    still_present = true;
                    break;
                }
            }
            if (!still_present) {
                unlink(old_m->files[i]);
            }
        }
    }

    printf("lpm: successfully installed %s-%s (%d files)\n", m->name, m->version, m->nfiles);
    {
        FILE *status = fopen(transaction_status, "w");
        if (status) { fprintf(status, "committed\n"); fclose(status); }
    }

cleanup:
    if (old_m) manifest_free(old_m);
    if (m) manifest_free(m);
    remove_tree(tmpdir);
    lpm_unlock();
    return ret;
}

int cmd_remove(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm remove <package>\n"); return 1; }
    const char *name = argv[0];

    if (!lpm_valid_pkgname(name)) {
        fprintf(stderr, "lpm: invalid package name '%s'\n", name);
        return 1;
    }
    if (lpm_lock() != 0) return 1;

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
    manifest *m = manifest_load(dbdir);
    if (!m) { fprintf(stderr, "lpm: '%s' not installed\n", name); lpm_unlock(); return 1; }

    /* Remove package files */
    for (int i = m->nfiles - 1; i >= 0; i--) {
        if (!lpm_safe_path(m->files[i])) {
            fprintf(stderr, "lpm: warning: skipping unsafe path '%s' in %s\n", m->files[i], m->name);
            continue;
        }
        if (unlink(m->files[i]) != 0 && errno != ENOENT)
            fprintf(stderr, "lpm: warning: could not remove %s\n", m->files[i]);
    }

    char mp[LPM_PATH_MAX + 32];
    snprintf(mp, sizeof(mp), "%s/manifest.json", dbdir);
    unlink(mp);
    rmdir(dbdir);

    printf("lpm: removed %s-%s\n", m->name, m->version);
    manifest_free(m);
    lpm_unlock();
    return 0;
}

int cmd_upgrade(int argc, char **argv) {
    if (access(LPM_REPO_JSON, F_OK) != 0) {
        fprintf(stderr, "lpm: no repository index found. Run 'lpm update' first.\n");
        return 1;
    }
    if (lpm_lock() != 0) return 1;

    if (argc >= 1) {
        const char *name = argv[0];
        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
        manifest *cur = manifest_load(dbdir);
        if (!cur) {
            printf("lpm: package '%s' is not installed. Installing...\n", name);
            char *pkg_args[] = { (char *)name };
            lpm_unlock();
            return cmd_install(1, pkg_args);
        }

        char *repo_ver = NULL, *filename = NULL, *sha256 = NULL;
        if (lpm_repo_lookup(name, &repo_ver, &filename, &sha256) != 0) {
            printf("lpm: '%s' is up to date (not in repository index)\n", name);
            manifest_free(cur);
            lpm_unlock();
            return 0;
        }

        if (lpm_version_cmp(cur->version, repo_ver) < 0) {
            printf("lpm: upgrading %s (%s -> %s)\n", name, cur->version, repo_ver);
            manifest_free(cur);
            free(repo_ver); free(filename); free(sha256);
            char *pkg_args[] = { (char *)name };
            lpm_unlock();
            return cmd_install(1, pkg_args);
        } else {
            printf("lpm: %s-%s is already up to date\n", cur->name, cur->version);
            manifest_free(cur);
            free(repo_ver); free(filename); free(sha256);
            lpm_unlock();
            return 0;
        }
    }

    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) { printf("lpm: no packages installed\n"); lpm_unlock(); return 0; }

    struct dirent *ent;
    int upgraded_count = 0;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        if (!lpm_valid_pkgname(ent->d_name)) continue;

        char dbdir[LPM_PATH_MAX];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
        manifest *cur = manifest_load(dbdir);
        if (!cur) continue;

        char *repo_ver = NULL, *filename = NULL, *sha256 = NULL;
        if (lpm_repo_lookup(ent->d_name, &repo_ver, &filename, &sha256) == 0) {
            if (lpm_version_cmp(cur->version, repo_ver) < 0) {
                printf("lpm: upgrade available for %s: %s -> %s\n", ent->d_name, cur->version, repo_ver);
                char *pkg_args[] = { ent->d_name };
                lpm_unlock();
                if (cmd_install(1, pkg_args) == 0) {
                    upgraded_count++;
                }
                if (lpm_lock() != 0) break;
            }
            free(repo_ver); free(filename); free(sha256);
        }
        manifest_free(cur);
    }
    closedir(dir);
    lpm_unlock();

    if (upgraded_count == 0) {
        printf("lpm: all packages are up to date\n");
    } else {
        printf("lpm: upgraded %d package(s)\n", upgraded_count);
    }
    return 0;
}

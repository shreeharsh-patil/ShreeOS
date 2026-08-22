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

static char *shell_escape(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *esc = malloc(len * 4 + 3);
    if (!esc) return NULL;
    char *p = esc;
    *p++ = '\'';
    for (const char *src = s; *src; src++) {
        if (*src == '\'') {
            *p++ = '\'';
            *p++ = '\\';
            *p++ = '\'';
            *p++ = '\'';
        } else {
            *p++ = *src;
        }
    }
    *p++ = '\'';
    *p = '\0';
    return esc;
}

static int run(const char *fmt, ...) {
    char buf[4096];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    return system(buf);
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

    printf("lpm: downloading %s from %s/%s...\n", pkgname, repo_url, filename);
    char cmd[LPM_PATH_MAX * 4];
    snprintf(cmd, sizeof(cmd),
             "curl -sSL \"%s/%s\" -o \"%s\" 2>/dev/null || wget -q \"%s/%s\" -O \"%s\"",
             repo_url, filename, out_path, repo_url, filename, out_path);

    int res = system(cmd);
    free(version);
    free(filename);
    free(sha256);

    if (res != 0 || access(out_path, F_OK) != 0) {
        fprintf(stderr, "lpm: failed to download package '%s'\n", pkgname);
        return -1;
    }
    return 0;
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

    /* 1. Fail closed on archive checksum */
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

    char *lpkg_esc = shell_escape(lpkg_path);
    if (!lpkg_esc) { fprintf(stderr, "lpm: memory error\n"); lpm_unlock(); return 1; }

    char tmpdir[] = "/tmp/lpm-stage-XXXXXX";
    if (!mkdtemp(tmpdir)) { perror("mkdtemp"); free(lpkg_esc); lpm_unlock(); return 1; }
    char *tmpdir_esc = shell_escape(tmpdir);
    if (!tmpdir_esc) { free(lpkg_esc); lpm_unlock(); return 1; }

    int ret = 0;
    char *cmd = NULL;
    size_t cmdlen;
    manifest *m = NULL;
    manifest *old_m = NULL;

    /* 2. Extract manifest */
    cmdlen = strlen(tmpdir_esc) + strlen(lpkg_esc) + 128;
    cmd = malloc(cmdlen);
    if (!cmd) { ret = 1; goto cleanup; }
    snprintf(cmd, cmdlen, "cd %s && tar -xzf %s manifest.json 2>/dev/null", tmpdir_esc, lpkg_esc);
    if (run("%s", cmd) != 0) {
        fprintf(stderr, "lpm: no manifest.json found in %s\n", lpkg_path);
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

    /* 3. Check dependencies */
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

    /* 4. Validate file paths in manifest */
    for (int i = 0; i < m->nfiles; i++) {
        if (!lpm_safe_path(m->files[i])) {
            fprintf(stderr, "lpm: security violation: unsafe path '%s' in package\n", m->files[i]);
            ret = 1;
            goto cleanup;
        }
    }

    /* 5. Detect file ownership conflicts */
    if (lpm_check_file_conflicts(m) != 0) {
        fprintf(stderr, "lpm: transaction aborted: file conflict with installed package\n");
        ret = 1;
        goto cleanup;
    }

    /* Check if upgrading existing package and preserve old manifest for cleanup */
    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", m->name);
    old_m = manifest_load(dbdir);

    printf("lpm: preparing transaction for %s-%s\n", m->name, m->version);

    /* 6. Extract payload into staging */
    char stage_root[LPM_PATH_MAX];
    snprintf(stage_root, sizeof(stage_root), "%s/root", tmpdir);
    mkdir_p(stage_root);
    char *stage_root_esc = shell_escape(stage_root);

    snprintf(cmd, cmdlen + strlen(stage_root_esc), "tar -xzf %s -C %s --exclude=manifest.json 2>/dev/null", lpkg_esc, stage_root_esc);
    int extract_res = run("%s", cmd);
    free(stage_root_esc);

    if (extract_res != 0) {
        fprintf(stderr, "lpm: failed to extract payload into staging area\n");
        ret = 1;
        goto cleanup;
    }

    /* 7. Verify per-file checksums in staging */
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

    /* 8. Transaction Backup for Rollback */
    char backup_dir[LPM_PATH_MAX];
    snprintf(backup_dir, sizeof(backup_dir), "%s/backup", tmpdir);
    mkdir_p(backup_dir);

    for (int i = 0; i < m->nfiles; i++) {
        if (access(m->files[i], F_OK) == 0) {
            char backup_file[LPM_PATH_MAX];
            snprintf(backup_file, sizeof(backup_file), "%s%s", backup_dir, m->files[i]);
            char *last_slash = strrchr(backup_file, '/');
            if (last_slash) {
                *last_slash = '\0';
                char mk_cmd[LPM_PATH_MAX + 32];
                snprintf(mk_cmd, sizeof(mk_cmd), "mkdir -p '%s'", backup_file);
                run("%s", mk_cmd);
                *last_slash = '/';
            }
            char cp_cmd[LPM_PATH_MAX * 2 + 32];
            snprintf(cp_cmd, sizeof(cp_cmd), "cp -a '%s' '%s' 2>/dev/null", m->files[i], backup_file);
            run("%s", cp_cmd);
        }
    }

    /* 9. Atomic Commit: Copy staged files to root */
    printf("lpm: committing %s-%s to system root\n", m->name, m->version);
    char copy_cmd[LPM_PATH_MAX * 2 + 128];
    snprintf(copy_cmd, sizeof(copy_cmd), "cp -a %s/root/. / 2>/dev/null || (cd %s/root && tar -cf - .) | (cd / && tar -xf -)",
             tmpdir, tmpdir);
    if (run("%s", copy_cmd) != 0) {
        fprintf(stderr, "lpm: transaction failed during commit to rootfs. Rolling back...\n");
        char rb_cmd[LPM_PATH_MAX * 2 + 64];
        snprintf(rb_cmd, sizeof(rb_cmd), "cp -a %s/backup/. / 2>/dev/null", tmpdir);
        run("%s", rb_cmd);
        ret = 1;
        goto cleanup;
    }

    /* 10. Update installed package database */
    mkdir_p(LPM_INSTALLED);
    mkdir_p(dbdir);
    if (manifest_save(m, dbdir) != 0) {
        fprintf(stderr, "lpm: failed to write installed database entry. Rolling back...\n");
        char rb_cmd[LPM_PATH_MAX * 2 + 64];
        snprintf(rb_cmd, sizeof(rb_cmd), "cp -a %s/backup/. / 2>/dev/null", tmpdir);
        run("%s", rb_cmd);
        ret = 1;
        goto cleanup;
    }

    /* 11. Cleanup obsolete files from previous package version */
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

cleanup:
    if (old_m) manifest_free(old_m);
    if (m) manifest_free(m);
    if (tmpdir_esc) {
        char rm_cmd[LPM_PATH_MAX + 32];
        snprintf(rm_cmd, sizeof(rm_cmd), "rm -rf %s", tmpdir_esc);
        run("%s", rm_cmd);
        free(tmpdir_esc);
    }
    free(cmd);
    free(lpkg_esc);
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

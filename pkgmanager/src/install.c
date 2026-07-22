#include "manifest.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <errno.h>
#include <ctype.h>

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

/*
 * Escape a string for use in single-quoted shell arguments.
 * Single quotes are the safest quoting mechanism: the only char
 * that needs special handling is the single quote itself, which we
 * terminate the quote, add an escaped quote, and re-open.
 * Returns a heap-allocated string the caller must free.
 */
static char *shell_escape(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    /* Worst case: every char is ' -> 4x expansion */
    char *esc = malloc(len * 4 + 3);
    if (!esc) return NULL;
    char *p = esc;
    *p++ = '\'';
    for (const char *src = s; *src; src++) {
        if (*src == '\'') {
            /* End quote, escaped quote, reopen */
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

int cmd_install(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm install <file.lpkg>\n"); return 1; }
    
    char *lpkg_esc = shell_escape(argv[0]);
    if (!lpkg_esc) { fprintf(stderr, "lpm: memory error\n"); return 1; }

    char tmpdir[] = "/tmp/lpm-XXXXXX";
    if (!mkdtemp(tmpdir)) { perror("mkdtemp"); free(lpkg_esc); return 1; }
    char *tmpdir_esc = shell_escape(tmpdir);
    if (!tmpdir_esc) { free(lpkg_esc); return 1; }

    int ret = 0;
    char *cmd = NULL;
    size_t cmdlen;

    /* Extract manifest from package */
    cmdlen = strlen(tmpdir_esc) + strlen(lpkg_esc) + 80;
    cmd = malloc(cmdlen);
    if (!cmd) { free(lpkg_esc); free(tmpdir_esc); return 1; }
    snprintf(cmd, cmdlen, "cd %s && tar -xzf %s manifest.json 2>/dev/null", tmpdir_esc, lpkg_esc);
    if (run("%s", cmd) != 0) {
        fprintf(stderr, "lpm: no manifest.json in %s\n", argv[0]);
        ret = 1;
        goto cleanup;
    }

    manifest *m = manifest_load(tmpdir);
    if (!m || !m->name || !*m->name) {
        fprintf(stderr, "lpm: invalid manifest\n");
        ret = 1;
        goto cleanup;
    }

    if (!lpm_valid_pkgname(m->name)) {
        fprintf(stderr, "lpm: manifest has invalid package name '%s'\n", m->name);
        manifest_free(m);
        ret = 1;
        goto cleanup;
    }

    printf("lpm: installing %s-%s\n", m->name, m->version);

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", m->name);
    mkdir_p(LPM_INSTALLED);
    mkdir_p(dbdir);
    manifest_save(m, dbdir);

    /* Extract package payload */
    snprintf(cmd, cmdlen, "tar -xzf %s -C / --exclude=manifest.json 2>/dev/null", lpkg_esc);
    if (run("%s", cmd) != 0) {
        fprintf(stderr, "lpm: extraction failed\n");
        manifest_free(m);
        ret = 1;
        goto cleanup;
    }

    printf("lpm: installed %s-%s (%d files)\n", m->name, m->version, m->nfiles);
    manifest_free(m);

cleanup:
    {
        char *rm_cmd = malloc(strlen(tmpdir_esc) + 20);
        if (rm_cmd) {
            snprintf(rm_cmd, strlen(tmpdir_esc) + 20, "rm -rf %s", tmpdir_esc);
            run("%s", rm_cmd);
            free(rm_cmd);
        }
    }
    free(cmd);
    free(lpkg_esc);
    free(tmpdir_esc);
    return ret;
}

int cmd_remove(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm remove <package>\n"); return 1; }
    const char *name = argv[0];

    if (!lpm_valid_pkgname(name)) {
        fprintf(stderr, "lpm: invalid package name '%s'\n", name);
        return 1;
    }

    char dbdir[LPM_PATH_MAX];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
    manifest *m = manifest_load(dbdir);
    if (!m) { fprintf(stderr, "lpm: '%s' not installed\n", name); return 1; }

    /* Only remove files that are within a safe, absolute path */
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
    return 0;
}

#include "manifest.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

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
    const char *lpkg = argv[0];

    char tmpdir[] = "/tmp/lpm-XXXXXX";
    if (!mkdtemp(tmpdir)) { perror("mkdtemp"); return 1; }

    if (run("cd '%s' && tar -xzf '%s' manifest.json 2>/dev/null", tmpdir, lpkg) != 0) {
        fprintf(stderr, "lpm: no manifest.json in %s\n", lpkg);
        run("rm -rf '%s'", tmpdir);
        return 1;
    }

    manifest *m = manifest_load(tmpdir);
    if (!m || !m->name || !*m->name) {
        fprintf(stderr, "lpm: invalid manifest\n");
        run("rm -rf '%s'", tmpdir);
        return 1;
    }

    printf("lpm: installing %s-%s\n", m->name, m->version);

    char dbdir[4096];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", m->name);
    mkdir(LPM_INSTALLED, 0755);
    mkdir(dbdir, 0755);
    manifest_save(m, dbdir);

    if (run("tar -xzf '%s' -C / --exclude=manifest.json 2>/dev/null", lpkg) != 0) {
        fprintf(stderr, "lpm: extraction failed\n");
        manifest_free(m);
        run("rm -rf '%s'", tmpdir);
        return 1;
    }

    printf("lpm: installed %s-%s (%d files)\n", m->name, m->version, m->nfiles);
    manifest_free(m);
    run("rm -rf '%s'", tmpdir);
    return 0;
}

int cmd_remove(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm remove <package>\n"); return 1; }
    const char *name = argv[0];

    char dbdir[4096];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", name);
    manifest *m = manifest_load(dbdir);
    if (!m) { fprintf(stderr, "lpm: '%s' not installed\n", name); return 1; }

    for (int i = m->nfiles - 1; i >= 0; i--) {
        if (unlink(m->files[i]) != 0 && errno != ENOENT)
            fprintf(stderr, "lpm: warning: could not remove %s\n", m->files[i]);
    }

    char mp[4096];
    snprintf(mp, sizeof(mp), "%s/manifest.json", dbdir);
    unlink(mp);
    rmdir(dbdir);

    printf("lpm: removed %s-%s\n", m->name, m->version);
    manifest_free(m);
    return 0;
}

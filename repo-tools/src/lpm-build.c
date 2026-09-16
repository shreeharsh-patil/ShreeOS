#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include "../../pkgmanager/src/manifest.h"

static void usage(void) {
    fprintf(stderr,
        "lpm-build — ShreeOS Package Packager\n"
        "Usage:\n"
        "  lpm-build <staging-dir> [output.lpkg]\n\n"
        "The staging directory must contain a valid manifest.json file.\n"
    );
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage();
        return 1;
    }

    const char *staging = argv[1];
    char manifest_path[LPM_PATH_MAX];
    snprintf(manifest_path, sizeof(manifest_path), "%s/manifest.json", staging);

    manifest *m = manifest_load(staging);
    if (!m || !m->name || !*m->name) {
        fprintf(stderr, "lpm-build: invalid or missing manifest at %s\n", manifest_path);
        if (m) manifest_free(m);
        return 1;
    }

    char out_lpkg[LPM_PATH_MAX];
    if (argc >= 3) {
        snprintf(out_lpkg, sizeof(out_lpkg), "%s", argv[2]);
    } else {
        snprintf(out_lpkg, sizeof(out_lpkg), "%s-%s.lpkg", m->name, m->version);
    }

    printf("lpm-build: packaging %s-%s into %s...\n", m->name, m->version, out_lpkg);

    char cmd[LPM_PATH_MAX * 3];
#ifdef _WIN32
    snprintf(cmd, sizeof(cmd), "tar -czf \"%s\" -C \"%s\" .", out_lpkg, staging);
#else
    snprintf(cmd, sizeof(cmd), "tar -czf \"%s\" -C \"%s\" --transform=\"s|^\\./||\" manifest.json .", out_lpkg, staging);
#endif

    int ret = system(cmd);
    if (ret != 0 || access(out_lpkg, F_OK) != 0) {
        fprintf(stderr, "lpm-build: failed to create package %s\n", out_lpkg);
        manifest_free(m);
        return 1;
    }

    printf("lpm-build: successfully created %s (%d files)\n", out_lpkg, m->nfiles);
    manifest_free(m);
    return 0;
}

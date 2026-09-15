#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include "../../pkgmanager/src/manifest.h"

static int run_tar(const char *output, const char *staging) {
    pid_t pid = fork();
    if (pid < 0) {
        perror("lpm-build: fork");
        return -1;
    }
    if (pid == 0) {
        char *const args[] = {
            "tar", "-czf", (char *)output,
            "-C", (char *)staging,
            "--transform=s|^\\./||",
            ".",
            NULL
        };
        execvp(args[0], args);
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        perror("lpm-build: waitpid");
        return -1;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

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

    struct stat staging_stat;
    if (stat(staging, &staging_stat) != 0 || !S_ISDIR(staging_stat.st_mode)) {
        fprintf(stderr, "lpm-build: staging path is not a directory: %s\n", staging);
        manifest_free(m);
        return 1;
    }

    struct stat output_stat;
    if (run_tar(out_lpkg, staging) != 0 ||
        stat(out_lpkg, &output_stat) != 0 ||
        !S_ISREG(output_stat.st_mode) ||
        output_stat.st_size <= 0) {
        fprintf(stderr, "lpm-build: failed to create package %s\n", out_lpkg);
        unlink(out_lpkg);
        manifest_free(m);
        return 1;
    }

    printf("lpm-build: successfully created %s (%d files)\n", out_lpkg, m->nfiles);
    manifest_free(m);
    return 0;
}

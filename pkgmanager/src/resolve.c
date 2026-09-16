#include "manifest.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

int cmd_query(int argc, char **argv) {
    if (argc < 1) { fprintf(stderr, "Usage: lpm query <package>\n"); return 1; }
    char dbdir[4096];
    snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", argv[0]);

    manifest *m = manifest_load(dbdir);
    if (!m) { printf("'%s' not installed\n", argv[0]); return 1; }

    printf("Name:    %s\n", m->name);
    printf("Version: %s\n", m->version);
    if (m->description && *m->description)
        printf("Desc:    %s\n", m->description);
    printf("Files (%d):\n", m->nfiles);
    for (int i = 0; i < m->nfiles; i++)
        printf("  %s\n", m->files[i]);

    manifest_free(m);
    return 0;
}

int cmd_list(int argc, char **argv) {
    (void)argc; (void)argv;
    DIR *dir = opendir(LPM_INSTALLED);
    if (!dir) { printf("No packages installed\n"); return 0; }

    struct dirent *ent;
    int found = 0;
    while ((ent = readdir(dir))) {
        if (ent->d_name[0] == '.') continue;
        char dbdir[4096];
        snprintf(dbdir, sizeof(dbdir), LPM_INSTALLED "/%s", ent->d_name);
        manifest *m = manifest_load(dbdir);
        if (m) {
            printf("%s-%s\n", m->name, m->version);
            manifest_free(m);
            found = 1;
        }
    }
    closedir(dir);
    if (!found) printf("No packages installed\n");
    return 0;
}

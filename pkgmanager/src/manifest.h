#ifndef LPM_MANIFEST_H
#define LPM_MANIFEST_H

#define LPM_DB "/var/lib/lpm"
#define LPM_INSTALLED LPM_DB "/installed"

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

#endif

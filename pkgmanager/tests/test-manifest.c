#include "manifest.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int failures = 0;
#define TEST(name, expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "FAIL: %s (%s)\n", name, #expr); \
        failures++; \
    } else { \
        printf("PASS: %s\n", name); \
    } \
} while(0)

static void test_basic_manifest(void) {
    const char *json =
        "{\n"
        "  \"name\": \"hello\",\n"
        "  \"version\": \"1.0\",\n"
        "  \"description\": \"Hello world\",\n"
        "  \"files\": [\"/usr/bin/hello\"]\n"
        "}";

    manifest *m = manifest_parse(json);
    TEST("parse returns non-NULL", m != NULL);
    TEST("name is hello", strcmp(m->name, "hello") == 0);
    TEST("version is 1.0", strcmp(m->version, "1.0") == 0);
    TEST("description matches", strcmp(m->description, "Hello world") == 0);
    TEST("1 file", m->nfiles == 1);
    TEST("file is /usr/bin/hello", strcmp(m->files[0], "/usr/bin/hello") == 0);
    TEST("no deps", m->ndeps == 0);
    manifest_free(m);
}

static void test_manifest_with_deps(void) {
    const char *json =
        "{\"name\":\"foo\",\"version\":\"2.0\",\"dependencies\":[\"bar\",\"baz\"],\"files\":[\"/usr/bin/foo\"]}";

    manifest *m = manifest_parse(json);
    TEST("deps parsed", m != NULL && m->ndeps == 2);
    TEST("first dep is bar", strcmp(m->deps[0], "bar") == 0);
    TEST("second dep is baz", strcmp(m->deps[1], "baz") == 0);
    manifest_free(m);
}

static void test_manifest_save_load(void) {
    const char *json = "{\"name\":\"test-pkg\",\"version\":\"0.1\",\"files\":[\"/usr/bin/test\"]}";
    manifest *m1 = manifest_parse(json);

    const char *tmpdir = "/tmp/lpm-test-manifest";
    mkdir(tmpdir, 0755);
    manifest_save(m1, tmpdir);
    manifest_free(m1);

    manifest *m2 = manifest_load(tmpdir);
    TEST("reloaded", m2 != NULL);
    TEST("name preserved", strcmp(m2->name, "test-pkg") == 0);
    TEST("version preserved", strcmp(m2->version, "0.1") == 0);
    TEST("file preserved", m2->nfiles == 1 && strcmp(m2->files[0], "/usr/bin/test") == 0);
    manifest_free(m2);

    /* cleanup */
    char mp[256]; snprintf(mp, sizeof(mp), "%s/manifest.json", tmpdir);
    unlink(mp); rmdir(tmpdir);
}

int main(void) {
    test_basic_manifest();
    test_manifest_with_deps();
    test_manifest_save_load();

    printf("\n%d failures\n", failures);
    return failures ? 1 : 0;
}

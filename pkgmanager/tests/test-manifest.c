#include "manifest.h"
#include "json.h"
#include "sha256.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef _WIN32
#include <direct.h>
#define mkdir(path, mode) _mkdir(path)
#else
#include <sys/stat.h>
#endif

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
    const char *json = "{\"name\":\"test-pkg\",\"version\":\"0.1\",\"files\":[\"/usr/bin/test\"],\"checksums\":{\"/usr/bin/test\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}";
    manifest *m1 = manifest_parse(json);

#ifdef _WIN32
    const char *tmpdir = "lpm-test-manifest";
#else
    const char *tmpdir = "/tmp/lpm-test-manifest";
#endif
    mkdir(tmpdir, 0755);
    manifest_save(m1, tmpdir);
    manifest_free(m1);

    manifest *m2 = manifest_load(tmpdir);
    TEST("reloaded", m2 != NULL);
    if (m2) {
        TEST("name preserved", strcmp(m2->name, "test-pkg") == 0);
        TEST("version preserved", strcmp(m2->version, "0.1") == 0);
        TEST("file preserved", m2->nfiles == 1 && strcmp(m2->files[0], "/usr/bin/test") == 0);
        TEST("checksum preserved", m2->nchecksums == 1 && strcmp(m2->checksums[0].path, "/usr/bin/test") == 0);
        manifest_free(m2);
    }

    /* cleanup */
    char mp[256]; snprintf(mp, sizeof(mp), "%s/manifest.json", tmpdir);
    unlink(mp); rmdir(tmpdir);
}

static void test_manifest_json_escaping(void) {
    const char *json = "{\"name\":\"quoted\\\\pkg\",\"version\":\"1.0\",\"description\":\"quote: \\\"; tab: \\t; unicode: \\u00e9\",\"dependencies\":[\"lib \\\"x\\\"\"],\"files\":[\"/usr/share/with space\"]}";
    manifest *m = manifest_parse(json);
    const char *tmpdir = "lpm-test-manifest-escaped";
    mkdir(tmpdir, 0755);
    TEST("escaped manifest parses", m != NULL);
    if (m) {
        TEST("escaped manifest saves", manifest_save(m, tmpdir) == 0);
        manifest_free(m);
        m = manifest_load(tmpdir);
        TEST("escaped manifest reloads", m != NULL);
        if (m) {
            TEST("escaped description preserved", strcmp(m->description, "quote: \"; tab: \t; unicode: \xC3\xA9") == 0);
            TEST("escaped dependency preserved", m->ndeps == 1 && strcmp(m->deps[0], "lib \"x\"") == 0);
            manifest_free(m);
        }
    }
    char mp[256]; snprintf(mp, sizeof(mp), "%s/manifest.json", tmpdir);
    unlink(mp); rmdir(tmpdir);
}

static void test_strict_json_rejection(void) {
    static const char *const invalid[] = {
        "\"unterminated", "{\"a\" 1}", "{\"a\":1,}", "[1,]", "{\"a\":truee}",
        "{\"a\":nul}", "{\"a\":01}", "{\"a\":1} trailing", "\"\\q\"", "\"\\uD800\""
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i)
        TEST("strict parser rejects malformed JSON", json_parse(invalid[i]) == NULL);
    json_value *unicode = json_parse("\"\\uD83D\\uDE00\"");
    TEST("strict parser accepts surrogate pair", unicode != NULL && json_string(unicode) != NULL);
    json_free(unicode);
}

static void test_manifest_sha256(void) {
    const char *json =
        "{\"name\":\"sec-pkg\",\"version\":\"1.0\",\"sha256\":\"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"files\":[\"/usr/bin/sec\"],\"checksums\":{\"/usr/bin/sec\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}";

    manifest *m = manifest_parse(json);
    TEST("parse sha256", m != NULL && m->sha256 != NULL);
    if (m && m->sha256) {
        TEST("sha256 matches", strcmp(m->sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0);
    }
    const char *csum = manifest_get_checksum(m, "/usr/bin/sec");
    TEST("get checksum by path", csum != NULL && strcmp(csum, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
    manifest_free(m);
}

static void test_sha256_hashing(void) {
    char hex[65];
    /* SHA-256 of empty string is e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 */
    lpm_sha256_buffer("", 0, hex);
    TEST("sha256 empty string", strcmp(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0);

    /* SHA-256 of "abc" is ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad */
    lpm_sha256_buffer("abc", 3, hex);
    TEST("sha256 'abc'", strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
}

static void test_version_comparison(void) {
    TEST("1.0.0 == 1.0.0", lpm_version_cmp("1.0.0", "1.0.0") == 0);
    TEST("1.0.0 < 1.0.1", lpm_version_cmp("1.0.0", "1.0.1") < 0);
    TEST("1.2.0 > 1.1.9", lpm_version_cmp("1.2.0", "1.1.9") > 0);
    TEST("2.0.0 > 1.99.99", lpm_version_cmp("2.0.0", "1.99.99") > 0);
    TEST("1.10.0 > 1.9.0", lpm_version_cmp("1.10.0", "1.9.0") > 0);
}

static void test_manifest_check_deps(void) {
    const char *json = "{\"name\":\"app\",\"version\":\"1.0\",\"dependencies\":[\"missing-lib-12345\"],\"files\":[\"/usr/bin/app\"]}";
    manifest *m = manifest_parse(json);
    TEST("parse app manifest", m != NULL);

    char **missing = NULL;
    int nmissing = 0;
    int res = manifest_check_deps(m, &missing, &nmissing);
    TEST("missing deps detected", res == 1 && nmissing == 1);
    if (nmissing > 0 && missing) {
        TEST("missing dep name correct", strcmp(missing[0], "missing-lib-12345") == 0);
        free(missing[0]);
        free(missing);
    }
    manifest_free(m);
}

int main(void) {
    test_basic_manifest();
    test_manifest_with_deps();
    test_manifest_save_load();
    test_manifest_json_escaping();
    test_strict_json_rejection();
    test_manifest_sha256();
    test_sha256_hashing();
    test_version_comparison();
    test_manifest_check_deps();

    printf("\n%d failures\n", failures);
    return failures ? 1 : 0;
}

#include "manifest.h"
#include "json.h"
#include "sha256.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

#ifdef _WIN32
#include <direct.h>
#define mkdir(path, mode) _mkdir(path)
#else
#include <sys/stat.h>
#include <sys/file.h>
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

static void test_manifest_conflicts_provides_replaces(void) {
    const char *json =
        "{\n"
        "  \"name\": \"network-manager\",\n"
        "  \"version\": \"2.1.0\",\n"
        "  \"dependencies\": [\"libnet >= 1.0\"],\n"
        "  \"conflicts\": [\"legacy-network\"],\n"
        "  \"provides\": [\"network-service\", \"dhcp-client\"],\n"
        "  \"replaces\": [\"old-network\"]\n"
        "}";

    manifest *m = manifest_parse(json);
    TEST("parse with conflicts/provides/replaces", m != NULL);
    if (m) {
        TEST("name matches", strcmp(m->name, "network-manager") == 0);
        TEST("1 dep", m->ndeps == 1 && strcmp(m->deps[0], "libnet >= 1.0") == 0);
        TEST("1 conflict", m->nconflicts == 1 && strcmp(m->conflicts[0], "legacy-network") == 0);
        TEST("2 provides", m->nprovides == 2 && strcmp(m->provides[0], "network-service") == 0 && strcmp(m->provides[1], "dhcp-client") == 0);
        TEST("1 replaces", m->nreplaces == 1 && strcmp(m->replaces[0], "old-network") == 0);

        /* Test save & reload */
        const char *tmpdir = "/tmp/lpm-test-cpr";
        mkdir(tmpdir, 0755);
        TEST("save manifest with cpr", manifest_save(m, tmpdir) == 0);
        manifest_free(m);

        manifest *reloaded = manifest_load(tmpdir);
        TEST("reload manifest with cpr", reloaded != NULL);
        if (reloaded) {
            TEST("reloaded conflicts count", reloaded->nconflicts == 1 && strcmp(reloaded->conflicts[0], "legacy-network") == 0);
            TEST("reloaded provides count", reloaded->nprovides == 2 && strcmp(reloaded->provides[0], "network-service") == 0);
            TEST("reloaded replaces count", reloaded->nreplaces == 1 && strcmp(reloaded->replaces[0], "old-network") == 0);
            manifest_free(reloaded);
        }
        char mp[256]; snprintf(mp, sizeof(mp), "%s/manifest.json", tmpdir);
        unlink(mp); rmdir(tmpdir);
    }
}

static void test_dep_spec_parsing(void) {
    char name[64], op[16], ver[64];

    TEST("parse simple name", lpm_parse_dep_spec("libssl", name, sizeof(name), op, sizeof(op), ver, sizeof(ver)) &&
         strcmp(name, "libssl") == 0 && op[0] == '\0' && ver[0] == '\0');

    TEST("parse with >= and spaces", lpm_parse_dep_spec("glibc >= 2.38", name, sizeof(name), op, sizeof(op), ver, sizeof(ver)) &&
         strcmp(name, "glibc") == 0 && strcmp(op, ">=") == 0 && strcmp(ver, "2.38") == 0);

    TEST("parse with <= without spaces", lpm_parse_dep_spec("python<=3.12", name, sizeof(name), op, sizeof(op), ver, sizeof(ver)) &&
         strcmp(name, "python") == 0 && strcmp(op, "<=") == 0 && strcmp(ver, "3.12") == 0);

    TEST("parse with ==", lpm_parse_dep_spec("busybox == 1.36.1", name, sizeof(name), op, sizeof(op), ver, sizeof(ver)) &&
         strcmp(name, "busybox") == 0 && strcmp(op, "==") == 0 && strcmp(ver, "1.36.1") == 0);
}

static void test_version_constraints(void) {
    TEST("1.2.3 >= 1.2.0 (true)", lpm_version_matches("1.2.3", ">=", "1.2.0") == true);
    TEST("1.2.0 >= 1.2.0 (true)", lpm_version_matches("1.2.0", ">=", "1.2.0") == true);
    TEST("1.1.9 >= 1.2.0 (false)", lpm_version_matches("1.1.9", ">=", "1.2.0") == false);

    TEST("2.0.0 <= 2.1.0 (true)", lpm_version_matches("2.0.0", "<=", "2.1.0") == true);
    TEST("2.2.0 <= 2.1.0 (false)", lpm_version_matches("2.2.0", "<=", "2.1.0") == false);

    TEST("1.5.0 == 1.5.0 (true)", lpm_version_matches("1.5.0", "==", "1.5.0") == true);
    TEST("1.5.1 == 1.5.0 (false)", lpm_version_matches("1.5.1", "==", "1.5.0") == false);

    TEST("2.0 > 1.9 (true)", lpm_version_matches("2.0", ">", "1.9") == true);
    TEST("2.0 > 2.0 (false)", lpm_version_matches("2.0", ">", "2.0") == false);
}

static void test_path_traversal_protection(void) {
    TEST("reject ../ relative path", lpm_safe_path("../etc/shadow") == false);
    TEST("reject /usr/bin/../../etc/shadow", lpm_safe_path("/usr/bin/../../etc/shadow") == false);
    TEST("reject /var/lib/lpm db path", lpm_safe_path("/var/lib/lpm/manifest.json") == false);
    TEST("reject trailing /..", lpm_safe_path("/usr/bin/..") == false);
    TEST("reject double slash //etc/shadow", lpm_safe_path("//etc/shadow") == false);
    TEST("accept valid /usr/bin/hello", lpm_safe_path("/usr/bin/hello") == true);
    TEST("accept valid /etc/hostname", lpm_safe_path("/etc/hostname") == true);
    TEST("accept valid /lib/modules/test.ko", lpm_safe_path("/lib/modules/test.ko") == true);
}

static void test_safe_locking(void) {
    const char *test_lock = "/tmp/lpm-test.lock";
    setenv("LPM_LOCK_FILE", test_lock, 1);
    unlink(test_lock);

    TEST("acquire lock", lpm_lock() == 0);
    /* Attempting recursive lock should fail */
    int second_fd = open(test_lock, O_RDWR);
    if (second_fd >= 0) {
        TEST("flock prevents concurrent lock", flock(second_fd, LOCK_EX | LOCK_NB) != 0);
        close(second_fd);
    }
    lpm_unlock();
    unlink(test_lock);
    unsetenv("LPM_LOCK_FILE");
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
    test_manifest_conflicts_provides_replaces();
    test_dep_spec_parsing();
    test_version_constraints();
    test_path_traversal_protection();
    test_safe_locking();

    printf("\n%d failures\n", failures);
    return failures ? 1 : 0;
}

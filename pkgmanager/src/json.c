#include "json.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static void skip_ws(const char **p) {
    while (**p && (isspace((unsigned char)**p))) (*p)++;
}

static json_value *parse_value(const char **p);

static char *parse_string(const char **p) {
    if (**p != '"') return NULL;
    (*p)++;
    size_t cap = 64, len = 0;
    char *s = malloc(cap);
    if (!s) return NULL;
    while (**p && **p != '"') {
        if (**p == '\\') { (*p)++;
            if (**p == '"' || **p == '\\' || **p == '/') s[len++] = **p;
            else if (**p == 'n') s[len++] = '\n';
            else if (**p == 't') s[len++] = '\t';
            else s[len++] = **p;
        } else {
            s[len++] = **p;
        }
        if (len >= cap - 1) { cap *= 2; char *t = realloc(s, cap); if (!t) { free(s); return NULL; } s = t; }
        (*p)++;
    }
    if (**p == '"') (*p)++;
    s[len] = '\0';
    return s;
}

static json_pair *parse_object(const char **p) {
    json_pair *head = NULL, **tail = &head;
    if (**p == '{') (*p)++;
    skip_ws(p);
    if (**p == '}') { (*p)++; return NULL; }
    while (**p) {
        json_pair *pair = calloc(1, sizeof(json_pair));
        if (!pair) break;
        pair->key = parse_string(p);
        if (!pair->key) { free(pair); break; }
        skip_ws(p);
        if (**p == ':') (*p)++;
        skip_ws(p);
        pair->value = parse_value(p);
        *tail = pair; tail = &pair->next;
        skip_ws(p);
        if (**p == ',') { (*p)++; skip_ws(p); }
        else if (**p == '}') { (*p)++; break; }
        else break;
    }
    return head;
}

static json_pair *parse_array(const char **p) {
    json_pair *head = NULL, **tail = &head;
    if (**p == '[') (*p)++;
    skip_ws(p);
    if (**p == ']') { (*p)++; return NULL; }
    while (**p) {
        json_pair *pair = calloc(1, sizeof(json_pair));
        if (!pair) break;
        pair->value = parse_value(p);
        *tail = pair; tail = &pair->next;
        skip_ws(p);
        if (**p == ',') { (*p)++; skip_ws(p); }
        else if (**p == ']') { (*p)++; break; }
        else break;
    }
    return head;
}

static json_value *parse_value(const char **p) {
    json_value *v = calloc(1, sizeof(json_value));
    if (!v) return NULL;
    skip_ws(p);
    if (**p == '"') {
        v->type = JSON_STRING;
        v->string = parse_string(p);
    } else if (**p == '{') {
        v->type = JSON_OBJECT;
        v->head = parse_object(p);
    } else if (**p == '[') {
        v->type = JSON_ARRAY;
        v->head = parse_array(p);
    } else if (**p == 'n') { /* null */
        v->type = JSON_NULL;
        if (strncmp(*p, "null", 4) == 0) *p += 4;
    } else if (**p == 't' || **p == 'f') { /* true/false */
        v->type = JSON_NULL;
        while (**p && isalpha((unsigned char)**p)) (*p)++;
    } else {
        v->type = JSON_NUMBER;
        const char *start = *p;
        while (**p && (isdigit((unsigned char)**p) || **p == '.' || **p == '-' || **p == '+')) (*p)++;
        size_t n = *p - start;
        v->string = malloc(n + 1);
        if (!v->string) { free(v); return NULL; }
        memcpy(v->string, start, n);
        v->string[n] = '\0';
    }
    return v;
}

json_value *json_parse(const char *input) {
    if (!input) return NULL;
    return parse_value(&input);
}

void json_free(json_value *v) {
    if (!v) return;
    free(v->string);
    for (json_pair *p = v->head; p;) {
        json_pair *next = p->next;
        free(p->key);
        json_free(p->value);
        free(p);
        p = next;
    }
    free(v);
}

json_value *json_get(const json_value *obj, const char *key) {
    if (!obj || obj->type != JSON_OBJECT) return NULL;
    for (json_pair *p = obj->head; p; p = p->next)
        if (p->key && strcmp(p->key, key) == 0)
            return p->value;
    return NULL;
}

const char *json_string(const json_value *v) {
    if (!v || v->type != JSON_STRING) return NULL;
    return v->string;
}

int json_array_len(const json_value *v) {
    if (!v || v->type != JSON_ARRAY) return 0;
    int n = 0;
    for (json_pair *p = v->head; p; p = p->next) n++;
    return n;
}

const char *json_array_str(const json_value *v, int idx) {
    if (!v || v->type != JSON_ARRAY) return NULL;
    int i = 0;
    for (json_pair *p = v->head; p; p = p->next, i++)
        if (i == idx && p->value->type == JSON_STRING)
            return p->value->string;
    return NULL;
}

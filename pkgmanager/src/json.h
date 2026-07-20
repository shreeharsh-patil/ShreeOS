#ifndef LPM_JSON_H
#define LPM_JSON_H

#include <stddef.h>

enum json_type { JSON_NULL, JSON_STRING, JSON_NUMBER, JSON_OBJECT, JSON_ARRAY };

typedef struct json_value {
    enum json_type type;
    char *string;           /* STRING value / OBJECT key / NUMBER literal */
    struct json_pair *head; /* OBJECT / ARRAY children */
} json_value;

typedef struct json_pair {
    char *key;
    json_value *value;
    struct json_pair *next;
} json_pair;

json_value *json_parse(const char *input);
void        json_free(json_value *v);
json_value *json_get(const json_value *obj, const char *key);
const char *json_string(const json_value *v);
int         json_array_len(const json_value *v);
const char *json_array_str(const json_value *v, int idx);

#endif

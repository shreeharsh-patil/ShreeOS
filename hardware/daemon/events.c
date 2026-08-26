#include "shreed.h"

void shreed_events_subscribe(shreed_client_t *client) {
    if (client) client->subscribed = true;
}

#include <stdint.h>
#include <stddef.h>
#include "mosquitto_internal.h"
#include "packet_mosq.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1) return 0;

    struct mosquitto db;
    memset(&db, 0, sizeof(struct mosquitto));
    
    // Simulate a fake incoming packet
    struct mosquitto_packet packet;
    memset(&packet, 0, sizeof(struct mosquitto_packet));
    
    packet.payload = (uint8_t *)data;
    packet.remaining_length = size;
    
    // Target the broker's internal handle function
    // Note: On 'master', ensure you include the correct headers for internal functions
    handle__packet(&db, &packet);

    return 0;
}

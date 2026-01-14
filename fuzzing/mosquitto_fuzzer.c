#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include "mosquitto_internal.h"
#include "packet_mosq.h"
#include "read_handle.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1) return 0;
    
    // Allocate and initialize a mosquitto structure
    struct mosquitto *mosq = mosquitto_new(NULL, true, NULL);
    if (!mosq) return 0;
    
    mosq->in_packet.command = data[0];
    size_t payload_size = size - 1;

    if(payload_size > 0){
        mosq->in_packet.payload = malloc(payload_size);
        if (!mosq->in_packet.payload) {
            mosquitto_destroy(mosq);
            return 0;
        }
        memcpy(mosq->in_packet.payload, data + 1, payload_size);
    }

    mosq->in_packet.remaining_length = payload_size;
    mosq->in_packet.remaining_count = 0;
    mosq->in_packet.pos = 0;
    mosq->in_packet.to_process = payload_size;
    
    // Set some basic state to avoid crashes
    mosq->sock = -1;  // Invalid socket
    mosq->state = mosq_cs_connected;  // Pretend we're connected
    
    // Process the packet
    handle__packet(mosq);
    
    // Cleanup
    // mosquitto_destroy frees `in_packet` logic too?
    // mosquitto_destroy calls mosquitto__destroy calls packet__cleanup_all
    // packet__cleanup_all frees in_packet.payload if set?
    
    // Let's check packet__cleanup in packet_mosq.c
    // void packet__cleanup(struct mosquitto__packet *packet) {
    //    if(packet->payload) free(packet->payload);
    //    packet->payload = NULL;
    // }
    
    // mosquitto__destroy -> packet__cleanup(&mosq->in_packet);
    
    // So mosquitto_destroy should free the payload I allocated.
    mosquitto_destroy(mosq);
    
    return 0;
}

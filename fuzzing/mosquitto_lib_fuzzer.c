#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* Project headers - ensure your compiler include paths find these. */
#include "mosquitto.h"               /* mosquitto_new, mosquitto_destroy, mosquitto_lib_init */
#include "mosquitto_internal.h"      /* struct mosquitto, struct mosquitto__packet */
#include "mosquitto_broker_internal.h" /* broker functions like handle__auth */
#include "mqtt_protocol.h"           /* CMD_AUTH, mosq_p_mqtt5 */
#include "packet_mosq.h"             /* packet related declarations */

/* Fuzzer entry point */
extern int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
    /* Create a client instance. Use a fixed id. */
    struct mosquitto *mosq = mosquitto_new("fuzz", true, NULL);
    if(!mosq){
        return 0;
    }

    /* Ensure we are in MQTT5 protocol so handle__auth proceeds down its path. */
    mosq->protocol = mosq_p_mqtt5;

    /* Prepare in_packet using the fuzz input bytes.
     * packet__read_byte and subsequent property parsing read from payload,
     * checking remaining_length and pos, so set those appropriately.
     */

    /* Allocate payload buffer. If Size is 0, allocate a 1-byte buffer to avoid NULL pointers.
     * Remaining length will be set to the actual Size (0 is allowed and will be handled).
     */
    uint8_t *payload_buf = NULL;
    if(Size){
        payload_buf = (uint8_t *)malloc(Size);
        if(!payload_buf){
            mosquitto_destroy(mosq);
            return 0;
        }
        memcpy(payload_buf, Data, Size);
    }else{
        /* Zero-length input: allocate a small buffer but remaining_length=0 */
        payload_buf = (uint8_t *)malloc(1);
        if(!payload_buf){
            mosquitto_destroy(mosq);
            return 0;
        }
        payload_buf[0] = 0;
    }

    /* Initialize the packet structure fields used by handle__auth and helper readers. */
    mosq->in_packet.payload = payload_buf;
    mosq->in_packet.pos = 0;
    mosq->in_packet.remaining_length = (uint32_t)Size;
    mosq->in_packet.packet_length = (uint32_t)Size;
    mosq->in_packet.command = CMD_AUTH;
    /* Other fields set defensively */
    mosq->in_packet.remaining_mult = 0;
    mosq->in_packet.to_process = (uint32_t)Size;
    mosq->in_packet.remaining_count = 0;
    mosq->in_packet.mid = 0;

    /* Call the target function. It will read from the packet and perform its logic. */
    (void)handle__auth(mosq);

    /* Do not free payload_buf here: mosquitto_destroy() will free in_packet.payload
     * (packet__cleanup calls mosquitto__free on packet->payload). Freeing here causes
     * a double-free. Clean up by destroying mosq which frees payload_buf.
     */
    mosquitto_destroy(mosq);

    /* Always return 0 as required by libFuzzer contract. */
    return 0;
}

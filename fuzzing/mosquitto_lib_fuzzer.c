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
    /* Always return 0 as required by libFuzzer contract. */
    return 0;
}

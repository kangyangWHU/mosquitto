#include <stddef.h>
#include <stdint.h>

#include "mosquitto.h"

/*
 * Fuzz target for lib/utf8_mosq.c
 *
 * This exercises the MQTT-specific UTF-8 validation logic.
 */
int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
	if(Size > 65536){
		/* mosquitto_validate_utf8 rejects lengths > 65536 */
		Size = 65536;
	}

	(void)mosquitto_validate_utf8((const char *)Data, (int)Size);
	return 0;
}

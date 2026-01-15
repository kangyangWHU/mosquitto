#include "config.h"

#include <stdbool.h>

#include "net_mosq.h"
#include "time_mosq.h"

static unsigned int fuzz_init_refcount = 0;

int mosquitto_lib_init(void)
{
	int rc;

	if(fuzz_init_refcount == 0){
		mosquitto_time_init();
		rc = net__init();
		if(rc != 0){
			return rc;
		}
#ifdef WITH_TLS
		net__init_tls();
#endif
	}
	fuzz_init_refcount++;
	return 0;
}

int mosquitto_lib_cleanup(void)
{
	if(fuzz_init_refcount == 1){
		net__cleanup();
	}
	if(fuzz_init_refcount > 0){
		fuzz_init_refcount--;
	}
	return 0;
}

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Include project headers (absolute project paths as discovered in repository).
// If your build environment provides different include paths you may need to adjust these.
#include "/src/mosquitto/src/mosquitto_broker_internal.h"

// The real struct config_recurse is defined in src/conf.c. Provide the same
// definition here so the harness can instantiate it.
struct config_recurse {
    unsigned int log_dest;
    int log_dest_set;
    unsigned int log_type;
    int log_type_set;
};

// The target function is defined in conf.c and may not be declared in a public header.
// Provide the prototype here so we can call it.
extern int config__read_file_core(struct mosquitto__config *config, bool reload,
                                  struct config_recurse *cr, int level,
                                  int *lineno, FILE *fptr, char **buf, int *buflen);

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
    // Create a temporary file and write the fuzzer input into it.
    // Use tmpfile() to avoid depending on filenames on disk.
    FILE *f = tmpfile();
    if(!f){
        // tmpfile may fail in some sandboxed environments; bail out gracefully.
        return 0;
    }

    if(Size > 0){
        size_t written = fwrite(Data, 1, Size, f);
        (void)written; // ignore; we still try to parse whatever was written
    }
    rewind(f);

    // Per-iteration config: initialize, use, then cleanup to avoid accumulating state.
    struct mosquitto__config config;
    config__init(&config);

    struct config_recurse cr;
    memset(&cr, 0, sizeof(cr));

    int lineno = 0;
    int buflen = 1000;
    char *buf = (char *)malloc((size_t)buflen);
    if(!buf){
        // cleanup and return if allocation fails
        config__cleanup(&config);
        fclose(f);
        return 0;
    }
    // Ensure buffer is an empty string so fgets_extending can work with it.
    buf[0] = '\0';

    // Call the target function. We pass reload = false to mimic normal reading.
    // level = 0 is appropriate for a top-level parse.
    (void)config__read_file_core(&config, false, &cr, 0, &lineno, f, &buf, &buflen);

    // Free per-iteration resources.
    free(buf);
    config__cleanup(&config);
    fclose(f);

    return 0;
}

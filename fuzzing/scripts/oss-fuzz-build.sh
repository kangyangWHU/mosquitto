#!/bin/bash -eu
#
# Copyright (c) 2023 Cedalo GmbH
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License 2.0
# and Eclipse Distribution License v1.0 which accompany this distribution.
#
# The Eclipse Public License is available at
#   https://www.eclipse.org/legal/epl-2.0/
# and the Eclipse Distribution License is available at
#   http://www.eclipse.org/org/documents/edl-v10.php.
#
# SPDX-License-Identifier: EPL-2.0 OR BSD-3-Clause
#
# Contributors:
#    Roger Light - initial implementation and documentation.

export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export CFLAGS="${CFLAGS:-}"
export CXXFLAGS="${CXXFLAGS:-}"
export LDFLAGS="${LDFLAGS:-}"

# Some build environments ship a linker that doesn't understand DWARF v5
# (e.g. DW_FORM_strx* forms). Force DWARF v4 for compatibility.
case " ${CFLAGS} " in
    *" -gdwarf-"*) ;;
    *) export CFLAGS="${CFLAGS} -gdwarf-4" ;;
esac
case " ${CXXFLAGS} " in
    *" -gdwarf-"*) ;;
    *) export CXXFLAGS="${CXXFLAGS} -gdwarf-4" ;;
esac

# Build direct broker dependency - cJSON
# Note that other dependencies, i.e. sqlite are not yet built because they are
# only used by plugins and not currently otherwise used.
cd ${SRC}/cJSON
cmake \
	-DBUILD_SHARED_LIBS=OFF \
	-DCMAKE_C_FLAGS=-fPIC \
	-DENABLE_CJSON_TEST=OFF \
	.
make -j $(nproc)
make install

# Build broker and library static libraries (only lib and src, not apps)
cd ${SRC}/mosquitto

# Clean any previous builds to avoid sanitizer issues
# make -C lib clean
# make -C src clean

# Build library
make -C lib \
    WITH_STATIC_LIBRARIES=yes \
    WITH_DOCS=no \
    WITH_TLS=yes \
    WITH_CJSON=yes \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    -j$(nproc)

# Build broker object files (compile all .o files without linking the binary)
cd ${SRC}/mosquitto/src
# Extract OBJS list from Makefile and build just those object files
# Exclude mosquitto.o because it contains main() which conflicts with libFuzzer.
OBJS=$(make -n mosquitto 2>/dev/null | grep -o '[a-zA-Z0-9_]*\.o' | sort -u | grep -v '^mosquitto\.o$' | xargs)

# Build objects (no broker binary link step)
make -j$(nproc) ${OBJS} \
    WITH_DOCS=no \
    WITH_TLS=yes \
    WITH_CJSON=yes \
    CFLAGS="$CFLAGS -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION" \
    LDFLAGS="$LDFLAGS"

# Create static library from broker object files (no main())
rm -f libmosquitto_broker.a
# We still need a few broker globals/helpers that live in mosquitto.c (db, run,
# flag_* and listener__set_defaults). Build a fuzz-specific object with main renamed.
MOSQ_FUZZ_O=mosquitto_fuzz.o
MOSQ_COMPILE_CMD=$(make -n mosquitto.o WITH_DOCS=no WITH_TLS=yes WITH_CJSON=yes \
    CFLAGS="$CFLAGS -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION" LDFLAGS="$LDFLAGS" | head -n 1)
MOSQ_COMPILE_CMD=$(echo "$MOSQ_COMPILE_CMD" | sed -e 's/ -c / -Dmain=mosquitto_main -c /' -e 's/ -o mosquitto\.o/ -o '"$MOSQ_FUZZ_O"'/')
eval "$MOSQ_COMPILE_CMD"

ar cr libmosquitto_broker.a ${OBJS} ${MOSQ_FUZZ_O}
ranlib libmosquitto_broker.a

# 3. Compile your custom fuzzer
# Use $LIB_FUZZING_ENGINE (provided by OSS-Fuzz) or -fsanitize=fuzzer
cd ${SRC}/mosquitto

COMMON_INCLUDES=(
    -I.
    -I./include
    -I./src
    -I./lib
    -I./deps
)

COMMON_LIBS=(
    $LIB_FUZZING_ENGINE
    -lssl -lcrypto -lpthread -ldl -lcjson -lm
)

# Some broker-internal fuzz harnesses call mosquitto_lib_init(), but linking the
# full libmosquitto.a would duplicate objects already present in
# libmosquitto_broker.a. Provide a fuzz-only implementation instead.
FUZZ_LIBINIT_O=mosquitto_fuzz_lib_init.o
$CC $CFLAGS $LDFLAGS \
    "${COMMON_INCLUDES[@]}" \
    -c ./fuzzing/mosquitto_fuzz_lib_init.c \
    -o "$FUZZ_LIBINIT_O"

# Build all harnesses in fuzzing/ that match *_fuzzer.c
found_harnesses=0
for harness in ${SRC}/mosquitto/fuzzing/*_fuzzer.c; do
    [ -e "$harness" ] || continue
    found_harnesses=1
    name=$(basename "$harness" .c)

    # If the harness uses broker internals, link the broker object archive.
    # Otherwise, link the public libmosquitto.a.
    if grep -q 'mosquitto_broker_internal\.h' "$harness"; then
        $CC $CFLAGS $LDFLAGS \
            -DWITH_BROKER \
            "${COMMON_INCLUDES[@]}" \
            "$harness" \
            -o "$OUT/$name" \
            ./src/libmosquitto_broker.a \
            "$FUZZ_LIBINIT_O" \
            "${COMMON_LIBS[@]}"
    else
        $CC $CFLAGS $LDFLAGS \
            "${COMMON_INCLUDES[@]}" \
            "$harness" \
            -o "$OUT/$name" \
            ./lib/libmosquitto.a \
            "${COMMON_LIBS[@]}"
    fi
done

if [ "$found_harnesses" -eq 0 ]; then
    echo "No fuzz harnesses found in \\"${SRC}/mosquitto/fuzzing\\" (expected *_fuzzer.c)" >&2
    exit 1
fi

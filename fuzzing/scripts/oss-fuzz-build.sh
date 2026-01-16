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

cd ${SRC}/mosquitto

# For OSS-Fuzz we only need the static archives used by the fuzz targets.
# Avoid building apps/clients/plugins because they link normal binaries and
# commonly fail when sanitizer/coverage flags are injected via CFLAGS/CXXFLAGS.
make -C lib \
	WITH_ASAN=yes \
	WITH_SHARED_LIBRARIES=no \
	WITH_STATIC_LIBRARIES=yes \
	WITH_DOCS=no \
	-j $(nproc)

# Build the broker objects as a static archive for fuzzers that target broker internals.
make -C src \
	WITH_ASAN=yes \
    WITH_STATIC_LIBRARIES=yes \
	WITH_DOCS=no \
	-j $(nproc)


OUT_DIR="${OUT:-.}"
WORK_DIR="${WORK:-/tmp}"
FUZZER_OBJ="${WORK_DIR}/mosquitto_fuzzer.o"
PLUGIN_DEBUG_OBJ="${WORK_DIR}/plugin_debug.o"
LIB_FUZZER_OBJ="${WORK_DIR}/mosquitto_lib_fuzzer.o"

"$CC" $CFLAGS -DWITH_BROKER -DWITH_BRIDGE -I. -Iinclude -Isrc -Ilib -Ideps \
	-c fuzzing/mosquitto_fuzzer.c \
	-o "$FUZZER_OBJ"

"$CC" $CFLAGS -I. -Iinclude -Isrc -Ilib -Ideps \
	-c src/plugin_debug.c \
	-o "$PLUGIN_DEBUG_OBJ"

# Fuzzer 1: Broker fuzzer - link both libraries, linker will resolve from broker first
"$CXX" $CXXFLAGS $LDFLAGS \
	"$FUZZER_OBJ" \
	"$PLUGIN_DEBUG_OBJ" \
    src/libmosquitto_broker.a \
	lib/libmosquitto.a \
	${LIB_FUZZING_ENGINE:--fsanitize=fuzzer} \
	-fsanitize=address \
	-lssl -lcrypto -lpthread -ldl -lrt -lm -lcjson \
	-o "${OUT_DIR}/mosquitto_broker_fuzzer"


# Fuzzer 2: only src fuzzer
"$CC" $CFLAGS -I. -Iinclude -Ilib -Isrc -Ideps \
	-c fuzzing/mosquitto_src_fuzzer.c \
	-o "$LIB_FUZZER_OBJ"

"$CXX" $CXXFLAGS $LDFLAGS \
	"$LIB_FUZZER_OBJ" \
	src/libmosquitto_broker.a \
	${LIB_FUZZING_ENGINE:--fsanitize=fuzzer} \
	-fsanitize=address \
	-lssl -lcrypto -lpthread -ldl -lrt -lm \
	-o "${OUT_DIR}/mosquitto_src_fuzzer"


# Fuzzer 2: Client library fuzzer
"$CC" $CFLAGS -I. -Iinclude -Isrc -Ilib -Ideps \
	-c fuzzing/mosquitto_lib_fuzzer.c \
	-o "$LIB_FUZZER_OBJ"

"$CXX" $CXXFLAGS $LDFLAGS \
	"$LIB_FUZZER_OBJ" \
	lib/libmosquitto.a \
	${LIB_FUZZING_ENGINE:--fsanitize=fuzzer} \
	-fsanitize=address \
	-lssl -lcrypto -lpthread -ldl -lrt -lm \
	-o "${OUT_DIR}/mosquitto_lib_fuzzer"


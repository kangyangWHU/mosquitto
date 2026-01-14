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
OBJS=$(make -n mosquitto 2>/dev/null | grep -o '[a-z_]*\.o' | sort -u | xargs)
for obj in $OBJS; do
    make $obj WITH_DOCS=no WITH_TLS=yes WITH_CJSON=yes CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || true
done

# Create static library from all object files
ar cr libmosquitto_broker.a *.o

# 3. Compile your custom fuzzer
# Use $LIB_FUZZING_ENGINE (provided by OSS-Fuzz) or -fsanitize=fuzzer
cd ${SRC}/mosquitto
$CC $CFLAGS $LDFLAGS -I. -I./include -I./src -I./lib \
    ${SRC}/mosquitto/fuzzing/mosquitto_fuzzer.c -o $OUT/mosquitto_fuzzer \
    $LIB_FUZZING_ENGINE \
    ./lib/libmosquitto.a \
    ./src/libmosquitto_broker.a \
    -lssl -lcrypto -lpthread -ldl -lcjson -lm

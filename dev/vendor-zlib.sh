#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2026 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Vendors zlib into Sources/CNIOExtrasZlib with Z_PREFIX using cnioextras_ prefix.
# Usage: dev/vendor-zlib.sh <path-to-zlib-checkout>
# The zlib checkout must have had ./configure run already.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/.." && pwd)"
target_dir="${root}/Sources/CNIOExtrasZlib"
include_dir="${target_dir}/include"

# --- Validate arguments ---
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-zlib-checkout>"
    exit 1
fi

zlib_dir="$1"

if [[ ! -f "${zlib_dir}/zlib.h" ]]; then
    echo "Error: ${zlib_dir}/zlib.h not found. Is this a zlib checkout?"
    exit 1
fi

if [[ ! -f "${zlib_dir}/zconf.h" ]]; then
    echo "Error: ${zlib_dir}/zconf.h not found. Did you run ./configure?"
    exit 1
fi

zlib_version="$(grep '#define ZLIB_VERSION' "${zlib_dir}/zlib.h" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
zlib_git_desc="$(cd "${zlib_dir}" && git describe --abbrev --dirty 2>/dev/null || echo "${zlib_version}")"
echo "Vendoring zlib ${zlib_version} from ${zlib_dir}"

# --- Source files to copy ---
c_files=(
    adler32.c
    crc32.c
    deflate.c
    inffast.c
    inflate.c
    inftrees.c
    trees.c
    zutil.c
)

# Public headers (go into include/)
public_headers=(
    zlib.h
    zconf.h
)

# Private headers (go into source dir)
private_headers=(
    zutil.h
    deflate.h
    inflate.h
    inftrees.h
    inffast.h
    crc32.h
    gzguts.h
    trees.h
    inffixed.h
)

# --- Clean old vendored files ---
echo "Cleaning old vendored files..."

# Remove old .c files
for f in "${c_files[@]}"; do
    rm -f "${target_dir}/${f}"
done

# Remove old private headers
for h in "${private_headers[@]}"; do
    rm -f "${target_dir}/nioextras-${h}"
done

# Remove old public headers (but keep CNIOExtrasZlib.h - we regenerate it)
for h in "${public_headers[@]}"; do
    rm -f "${include_dir}/nioextras-${h}"
done

# Remove empty.c if present
rm -f "${target_dir}/empty.c"

# --- Copy C source files ---
echo "Copying source files..."
for f in "${c_files[@]}"; do
    cp "${zlib_dir}/${f}" "${target_dir}/${f}"
done

# --- Copy and rename headers ---
echo "Copying and renaming headers..."

for h in "${public_headers[@]}"; do
    cp "${zlib_dir}/${h}" "${include_dir}/nioextras-${h}"
done

for h in "${private_headers[@]}"; do
    cp "${zlib_dir}/${h}" "${target_dir}/nioextras-${h}"
done

# --- Update #include directives ---
echo "Updating #include directives..."

all_headers=("${public_headers[@]}" "${private_headers[@]}")
all_vendored_files=()
for f in "${c_files[@]}"; do
    all_vendored_files+=("${target_dir}/${f}")
done
for h in "${public_headers[@]}"; do
    all_vendored_files+=("${include_dir}/nioextras-${h}")
done
for h in "${private_headers[@]}"; do
    all_vendored_files+=("${target_dir}/nioextras-${h}")
done

for h in "${all_headers[@]}"; do
    # Replace "header.h" -> "nioextras-header.h"
    sed -i '' "s|\"${h}\"|\"nioextras-${h}\"|g" "${all_vendored_files[@]}"
    # Replace <header.h> -> <nioextras-header.h>
    sed -i '' "s|<${h}>|<nioextras-${h}>|g" "${all_vendored_files[@]}"
done

# --- Enable Z_PREFIX ---
echo "Enabling Z_PREFIX..."
sed -i '' 's/^#ifdef Z_PREFIX.*$/#if 1 \/* Z_PREFIX - cnioextras_z_ *\//' "${include_dir}/nioextras-zconf.h"

# --- Rename symbols with cnioextras_ prefix ---
echo "Applying cnioextras_ prefix..."

# Broad renames across all vendored files (order matters):
# 1. z_ -> cnioextras_z_ at word boundaries (types and Z_PREFIX targets)
#    Uses word-boundary to avoid matching z_ inside gz_header etc.
sed -i '' -E 's/(^|[^a-zA-Z_])z_/\1cnioextras_z_/g' "${all_vendored_files[@]}"

# 2. Z_ -> CNIOEXTRAS_Z_ at word boundaries (constants like Z_OK, Z_FINISH, Z_PREFIX_SET)
sed -i '' -E 's/(^|[^a-zA-Z_])Z_/\1CNIOEXTRAS_Z_/g' "${all_vendored_files[@]}"

# 3. ZLIB_ -> CNIOEXTRAS_ZLIB_ at word boundaries (ZLIB_VERSION, ZLIB_INTERNAL, etc.)
#    Also handles ZLIB_H include guard.
sed -i '' -E 's/(^|[^a-zA-Z_])ZLIB_/\1CNIOEXTRAS_ZLIB_/g' "${all_vendored_files[@]}"

# --- Rename ZCONF_H include guard (not caught by the above) ---
echo "Renaming include guards..."
sed -i '' 's/ZCONF_H/NIOEXTRAS_ZCONF_H/g' "${include_dir}/nioextras-zconf.h"

# --- Regenerate CNIOExtrasZlib.h ---
echo "Regenerating CNIOExtrasZlib.h..."
cat > "${include_dir}/CNIOExtrasZlib.h" << 'HEADER'
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2026 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
#ifndef C_NIO_ZLIB_H
#define C_NIO_ZLIB_H

#include "nioextras-zlib.h"

static inline int CNIOExtrasZlib_deflateInit2(cnioextras_z_streamp strm,
                                              int level,
                                              int method,
                                              int windowBits,
                                              int memLevel,
                                              int strategy) {
    return cnioextras_z_deflateInit2(strm, level, method, windowBits, memLevel, strategy);
}

static inline int CNIOExtrasZlib_inflateInit2(cnioextras_z_streamp strm, int windowBits) {
    return cnioextras_z_inflateInit2(strm, windowBits);
}

static inline cnioextras_z_Bytef *CNIOExtrasZlib_voidPtr_to_BytefPtr(void *in) {
    return (cnioextras_z_Bytef *)in;
}

#endif
HEADER

# --- Write version file ---
echo "${zlib_git_desc}" > "${target_dir}/vendored-zlib.version"

# --- Validate with clang + nm ---
echo "Validating symbol prefixes..."
validation_failed=0
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for f in "${c_files[@]}"; do
    if clang -c -DHAVE_HIDDEN -I"${include_dir}" -I"${target_dir}" \
        "${target_dir}/${f}" -o "${tmpdir}/${f}.o" 2>/dev/null; then
        bad_symbols="$(nm "${tmpdir}/${f}.o" 2>/dev/null | grep ' T ' | grep -v 'cnioextras_' || true)"
        if [[ -n "${bad_symbols}" ]]; then
            echo "WARNING: ${f} has unprefixed public symbols:"
            echo "${bad_symbols}"
            validation_failed=1
        fi
    else
        echo "WARNING: Failed to compile ${f} for validation"
        validation_failed=1
    fi
done

if [[ "${validation_failed}" -eq 0 ]]; then
    echo "Validation passed: all public symbols have cnioextras_ prefix"
else
    echo "ERROR: Some validation checks failed (see above)"
    exit 1
fi

echo "Done! zlib ${zlib_version} vendored into Sources/CNIOExtrasZlib/"

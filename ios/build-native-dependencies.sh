#!/bin/bash

set -e

if [[ ${CONFIGURATION} == "Debug" ]]
then
  LIGHTTPD_CONFIG="Debug"
else
  LIGHTTPD_CONFIG="Release"
fi

# Set defaults for Xcode-specific variables when not running from Xcode
IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.4}"
EFFECTIVE_PLATFORM_NAME="${EFFECTIVE_PLATFORM_NAME:--iphonesimulator}"

if [[ ${PLATFORM_FAMILY_NAME} == "iOS" ]]
then
  EXTRA_CONFIG_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET} -DCMAKE_SYSTEM_NAME=iOS -GXcode"
  BUILD_OUTPUT_FOLDER_LIGHTTPD="/${LIGHTTPD_CONFIG}${EFFECTIVE_PLATFORM_NAME}"
  BUILD_OUTPUT_FOLDER_PCRE2="/Release${EFFECTIVE_PLATFORM_NAME}"
else
  # This assumes Mac Catalyst build.
  EXTRA_CONFIG_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
  BUILD_OUTPUT_FOLDER_LIGHTTPD="/${LIGHTTPD_CONFIG}"
  BUILD_OUTPUT_FOLDER_PCRE2="/Release"
fi

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When run from Xcode, PROJECT_DIR might point to ios folder, so we need to handle that
if [[ "${PROJECT_DIR}" == *"/ios" ]]; then
  PROJECT_ROOT="${PROJECT_DIR%/ios}"
else
  PROJECT_ROOT="${PROJECT_DIR:-${SCRIPT_DIR}/..}"
fi

# Set defaults for variables when not running from Xcode
TARGET_TEMP_DIR="${TARGET_TEMP_DIR:-${SCRIPT_DIR}/build/temp}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-${SCRIPT_DIR}/build}"
PLATFORM_FAMILY_NAME="${PLATFORM_FAMILY_NAME:-iOS}"
CONFIGURATION="${CONFIGURATION:-Release}"

# Ensure build directory exists
mkdir -p "${TARGET_TEMP_DIR}"
mkdir -p "${BUILT_PRODUCTS_DIR}"

mkdir -p "${TARGET_TEMP_DIR}"

cmake "${PROJECT_ROOT}" -B "${TARGET_TEMP_DIR}" \
  -DBUILD_STATIC=1 -DBUILD_LIBRARY=1 ${EXTRA_CONFIG_ARGS} ${EXTRA_CMAKE_ARGS} -DWITH_MOD_WEBDAV=ON

cmake --build "${TARGET_TEMP_DIR}" --config ${LIGHTTPD_CONFIG} --target lighttpd

# Debug: Show what files were built
echo "=== Built lighttpd files ==="
LIGHTTPD_BUILD_DIR="${TARGET_TEMP_DIR}/lighttpd1.4/build"
if [[ -f "${LIGHTTPD_BUILD_DIR}/liblighttpd.a" ]]; then
  ls -la "${LIGHTTPD_BUILD_DIR}/"*.a 2>/dev/null || echo "No lighttpd .a files found in ${LIGHTTPD_BUILD_DIR}"
else
  ls -la "${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}/"*.a 2>/dev/null || echo "No lighttpd .a files found in ${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}"
fi

echo "=== Built pcre2 files ==="
PCRE2_BUILD_DIR="${TARGET_TEMP_DIR}/pcre2"
if [[ -f "${PCRE2_BUILD_DIR}/libpcre2-8.a" ]]; then
  ls -la "${PCRE2_BUILD_DIR}/"*.a 2>/dev/null || echo "No pcre2 .a files found in ${PCRE2_BUILD_DIR}"
else
  ls -la "${TARGET_TEMP_DIR}/pcre2${BUILD_OUTPUT_FOLDER_PCRE2}/"*.a 2>/dev/null || echo "No pcre2 .a files found in ${TARGET_TEMP_DIR}/pcre2${BUILD_OUTPUT_FOLDER_PCRE2}"
fi

echo "=== Copying files to ${BUILT_PRODUCTS_DIR} ==="

# Copy specific lighttpd libraries
if [[ -f "${LIGHTTPD_BUILD_DIR}/liblighttpd.a" ]]; then
  # Copy specific lighttpd libraries
  cp "${LIGHTTPD_BUILD_DIR}/liblighttpd.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "liblighttpd.a not found in ${LIGHTTPD_BUILD_DIR}"
  cp "${LIGHTTPD_BUILD_DIR}/libmod_h2.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "libmod_h2.a not found in ${LIGHTTPD_BUILD_DIR}"
else
  # Copy specific lighttpd libraries from alternative location
  cp "${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}/liblighttpd.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "liblighttpd.a not found in ${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}"
  cp "${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}/libmod_h2.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "libmod_h2.a not found in ${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}"
fi

# Copy specific pcre2 library
if [[ -f "${PCRE2_BUILD_DIR}/libpcre2-8.a" ]]; then
  cp "${PCRE2_BUILD_DIR}/libpcre2-8.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "libpcre2-8.a not found in ${PCRE2_BUILD_DIR}"
else
  cp "${TARGET_TEMP_DIR}/pcre2${BUILD_OUTPUT_FOLDER_PCRE2}/libpcre2-8.a" "${BUILT_PRODUCTS_DIR}" 2>/dev/null || echo "libpcre2-8.a not found in ${TARGET_TEMP_DIR}/pcre2${BUILD_OUTPUT_FOLDER_PCRE2}"
fi

echo "=== Final built products ==="
ls -la "${BUILT_PRODUCTS_DIR}/"*.a 2>/dev/null || echo "No .a files in built products dir"

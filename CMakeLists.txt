project(rn-static-server C)
cmake_minimum_required(VERSION 3.22.1 FATAL_ERROR)

if (CMAKE_VERSION MATCHES "3.30.0")
  message(FATAL_ERROR "CMake v3.30.0 is not supported: https://github.com/birdofpreyru/react-native-static-server/issues/111")
elseif (CMAKE_VERSION MATCHES "3.30.1")
  message(FATAL_ERROR "CMake v3.30.1 is not supported: https://github.com/birdofpreyru/react-native-static-server/issues/111")
endif()

# This prevents CMake from complaining that INSTALL(..) directives in
# Lighttpd CMakeLists.txt miss BUNDLE DESTINATION.
set(CMAKE_MACOSX_BUNDLE OFF)

# Pre-build of PCRE2 for the target system from sources.

if(CMAKE_CROSSCOMPILING AND CMAKE_HOST_SYSTEM_NAME MATCHES "Windows")
  # Use prebuilt host-side lemon.exe; lighttpd's Ninja build expects
  # "lighttpd1.4/build/lemon" (no extension) as a dependency and command.
  # Provide both "lemon.exe" and "lemon" so Ninja's dependency and the
  # actual invocation both succeed on Windows.
  set(_LEMON_SRC
      "${CMAKE_CURRENT_SOURCE_DIR}/windows/ReactNativeStaticServer/lighttpd/lemon.exe"
  )
  set(_LEMON_BUILD_DIR "${CMAKE_BINARY_DIR}/lighttpd1.4/build")

  file(MAKE_DIRECTORY "${_LEMON_BUILD_DIR}")
  file(COPY "${_LEMON_SRC}" DESTINATION "${_LEMON_BUILD_DIR}")
  file(COPY_FILE "${_LEMON_SRC}" "${_LEMON_BUILD_DIR}/lemon")

  set(LEMON_PATH "${_LEMON_BUILD_DIR}/lemon")
endif()

# Note: Archs in CMAKE_OSX_ARCHITECTURES are separated by semi-colons,
# if we don't escape semi-colons before inserting the value into other
# variables, most CMake commands will treat that semi-colon as argument
# separator in the list, and replace them with whitspaces, leading
# to obscure errors (e.g. it may successfully complete the build,
# but effectively doing it for the first of the archs only, and leave us
# to wonder, why something does not link for some arch later).
string(REPLACE " " "\\\;" ESCAPED_ARCHS "$ENV{ARCHS_STANDARD}")

if(CMAKE_SYSTEM_NAME MATCHES "Android")
  # These (and similar values set for DCMAKE_SHARED_LINKER_FLAGS below)
  # are necessary to ensure 16KB Memory Page Size compatibility of compiled
  # shared libraries; for additional details see:
  # https://developer.android.com/guide/practices/page-sizes
  link_libraries("-Wl,-z,max-page-size=16384")
  link_libraries("-Wl,-z,common-page-size=16384")
  set(
    EXTRA_BUILD_ARGS
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DANDROID_STL=${ANDROID_STL}
    -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -GNinja
  )

# TODO: This aims Mac Catalyst build, and needs a more specific condition,
# but will do like this for now, as we are not doing native Mac builds, thus
# Mac Catalyst build is the only scenario we have where the target system name
# is Darwin.
elseif(CMAKE_SYSTEM_NAME MATCHES "Darwin")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -target x86_64-apple-ios-macabi")
  set(
    EXTRA_BUILD_ARGS
    -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
    -DCMAKE_OSX_ARCHITECTURES=${ESCAPED_ARCHS}
  )
  # This allows to not sign compiled PCRE2 executables for iOS / macOS builds,
  # we don't really use them anyway, but we need them build for the install
  # command below to work.
  set(EXTRA_INSTALL_ARGS "--;CODE_SIGNING_ALLOWED=NO")

elseif(CMAKE_SYSTEM_NAME MATCHES "iOS")
  set(
    EXTRA_BUILD_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DCMAKE_OSX_ARCHITECTURES=${ESCAPED_ARCHS}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DCMAKE_IOS_INSTALL_COMBINED=${CMAKE_IOS_INSTALL_COMBINED}
    -GXcode
  )
  # This allows to not sign compiled PCRE2 executables for iOS / macOS builds,
  # we don't really use them anyway, but we need them build for the install
  # command below to work.
  set(EXTRA_INSTALL_ARGS "--;CODE_SIGNING_ALLOWED=NO")
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Android|Windows")
  set(EXTRA_BUILD_ARGS ${EXTRA_BUILD_ARGS} -DBUILD_SHARED_LIBS=ON)
endif()

execute_process(
  COMMAND ${CMAKE_COMMAND} ${CMAKE_CURRENT_SOURCE_DIR}/pcre2
    -B ${CMAKE_BINARY_DIR}/pcre2
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/sysroot
    -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
    ${EXTRA_BUILD_ARGS}
  COMMAND_ECHO STDOUT
  COMMAND_ERROR_IS_FATAL ANY
)

execute_process(
  COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR}/pcre2
    --config Release ${EXTRA_INSTALL_ARGS}
)

execute_process(COMMAND ${CMAKE_COMMAND} --install ${CMAKE_BINARY_DIR}/pcre2)

# Copies shared PCRE2 library into the folder from where Gradle automatically
# will bundle it in the host app package.
if(CMAKE_SYSTEM_NAME MATCHES "Android")
  file(
    COPY ${CMAKE_BINARY_DIR}/sysroot/lib/libpcre2-8.so
    DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/android/src/main/jniLibs/${ANDROID_ABI}
  )
endif()

# Builds & places for packing the glob library, for Android-targeted builds.
if(CMAKE_SYSTEM_NAME MATCHES "Android")
  execute_process(
    COMMAND ${CMAKE_COMMAND} ${CMAKE_CURRENT_SOURCE_DIR}/glob
      -B ${CMAKE_BINARY_DIR}/glob
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/sysroot
      -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
      ${EXTRA_BUILD_ARGS}
    COMMAND_ECHO STDOUT
    COMMAND_ERROR_IS_FATAL ANY
  )
  execute_process(
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR}/glob
      --config Release ${EXTRA_INSTALL_ARGS}
  )
  execute_process(COMMAND ${CMAKE_COMMAND} --install ${CMAKE_BINARY_DIR}/glob)
  file(
    COPY ${CMAKE_BINARY_DIR}/sysroot/lib/libglob.so
    DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/android/src/main/jniLibs/${ANDROID_ABI}
  )
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Android|Windows")
  set(BUILD_SHARED_LIBS 1)
endif()

# Above we have build & installed a local version of PCRE2 library, now we want
# to enforce Lighttpd build to see and use it (rather than any system-wide
# installation of another PCRE2 version). On Ubuntu / macOS it can be done
# by setting CMAKE_PREFIX_PATH; somehow it has no effect in Msys2 / UCRT64
# builds for Windows (beyond by current understanding), but there setting
# the PKG_CONFIG_PATH environment variable, which is picked up by pkg-config
# does the trick.
if(CMAKE_SYSTEM_NAME MATCHES "Windows")
  set(ENV{PKG_CONFIG_PATH} "${CMAKE_BINARY_DIR}/sysroot/lib/pkgconfig")
else()
  set(CMAKE_PREFIX_PATH "${CMAKE_BINARY_DIR}/sysroot")
endif()

add_subdirectory(lighttpd1.4)

set(PLUGIN_STATIC
  PLUGIN_INIT(mod_access)\n
  PLUGIN_INIT(mod_alias)\n
  PLUGIN_INIT(mod_dirlisting)\n
  PLUGIN_INIT(mod_evhost)\n
  PLUGIN_INIT(mod_expire)\n
  PLUGIN_INIT(mod_fastcgi)\n
  PLUGIN_INIT(mod_h2)\n
  PLUGIN_INIT(mod_indexfile)\n
  PLUGIN_INIT(mod_redirect)\n
  PLUGIN_INIT(mod_rewrite)\n
  PLUGIN_INIT(mod_scgi)\n
  PLUGIN_INIT(mod_setenv)\n
  PLUGIN_INIT(mod_simple_vhost)\n
  PLUGIN_INIT(mod_staticfile)\n
)

if(WITH_MOD_WEBDAV)
  set(PLUGIN_STATIC "${PLUGIN_STATIC}PLUGIN_INIT(mod_webdav)\n")
endif()

file(WRITE ${CMAKE_BINARY_DIR}/lighttpd1.4/build/plugin-static.h
  ${PLUGIN_STATIC}
)

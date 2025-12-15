require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
$extraCMakeArgs = ""

$libToolFlags = "-llighttpd -lpcre2-8 -lmod_dirlisting -lmod_h2"

$outputFiles = [
  # Note: Below is the list of all build products generated from PRCE2,
  # Lighttpd, and this library, as of now; the commented out modules are
  # not currently used by our library.
  '${BUILT_PRODUCTS_DIR}/liblighttpd.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_accesslog.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_ajp13.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_auth.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_authn_file.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_cgi.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_deflate.a',
  '${BUILT_PRODUCTS_DIR}/libmod_dirlisting.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_extforward.a',
  '${BUILT_PRODUCTS_DIR}/libmod_h2.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_proxy.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_rrdtool.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_sockproxy.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_ssi.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_status.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_userdir.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_vhostdb.a',
  # '${BUILT_PRODUCTS_DIR}/libmod_wstunnel.a',
  '${BUILT_PRODUCTS_DIR}/libpcre2-8.a'
]

if ENV['RN_STATIC_SERVER_WEBDAV'] == '1' then
  $extraCMakeArgs += " -DWITH_MOD_WEBDAV=ON"
  $libToolFlags += " -lmod_webdav"
  $outputFiles.append('${BUILT_PRODUCTS_DIR}/libmod_webdav.a')
end

Pod::Spec.new do |s|
  s.name         = "ReactNativeStaticServer"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/birdofpreyru/react-native-static-server.git", :tag => "#{s.version}" }

  s.preserve_paths = 'README.md', 'package.json', 'index.js'

  # This requires CMake on the build host, which can be installed via Homebrew (https://brew.sh)
  s.script_phase = {
    :name => 'Build native dependencies',
    :execution_position => :before_compile,
    :output_files => $outputFiles,
    :script => <<-CMD
      set -e

      if [[ ${CONFIGURATION} == "Debug" ]]
      then
        LIGHTTPD_CONFIG="Debug"
      else
        LIGHTTPD_CONFIG="Release"
      fi

      if [[ ${PLATFORM_FAMILY_NAME} == "iOS" ]]
      then
        EXTRA_CONFIG_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET} -DCMAKE_SYSTEM_NAME=iOS -GXcode"
        BUILD_OUTPUT_FOLDER_LIGHTTPD="/${LIGHTTPD_CONFIG}${EFFECTIVE_PLATFORM_NAME}"
        BUILD_OUTPUT_FOLDER_PCRE2="/Release${EFFECTIVE_PLATFORM_NAME}"
      else
        # This assumes Mac Catalyst build.
        EXTRA_CONFIG_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"
      fi

      cmake ${PODS_TARGET_SRCROOT} -B ${TARGET_TEMP_DIR} \
        -DBUILD_STATIC=1 -DBUILD_LIBRARY=1 ${EXTRA_CONFIG_ARGS} #{$extraCMakeArgs}

      cmake --build ${TARGET_TEMP_DIR} --config ${LIGHTTPD_CONFIG} --target lighttpd

      cp  ${TARGET_TEMP_DIR}/lighttpd1.4/build${BUILD_OUTPUT_FOLDER_LIGHTTPD}/*.a \
          ${TARGET_TEMP_DIR}/pcre2${BUILD_OUTPUT_FOLDER_PCRE2}/*.a \
          ${BUILT_PRODUCTS_DIR}
    CMD
  }
  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  s.pod_target_xcconfig    = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "OTHER_LIBTOOLFLAGS" => $libToolFlags
  }
  install_modules_dependencies(s)
end

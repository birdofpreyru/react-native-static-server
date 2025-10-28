#!/bin/bash

# Change to the iOS directory to ensure xcodebuild can find the project
cd "$(dirname "$0")"

rm -rf build/ReactNativeStaticServer.*

# For iOS Device
xcodebuild archive \
-scheme ReactNativeStaticServer \
-sdk iphoneos \
-configuration Release \
-destination 'generic/platform=iOS' \
-archivePath './build/ReactNativeStaticServer.framework-iphoneos.xcarchive' \
SKIP_INSTALL=NO \
BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

# For Simulators
xcodebuild archive \
-scheme ReactNativeStaticServer \
-sdk iphonesimulator \
-configuration Release \
-destination 'generic/platform=iOS Simulator' \
-archivePath './build/ReactNativeStaticServer.framework-iphonesimulator.xcarchive' \
SKIP_INSTALL=NO \
BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

# Create XCFramework
xcodebuild -create-xcframework \
-framework './build/ReactNativeStaticServer.framework-iphonesimulator.xcarchive/Products/Library/Frameworks/ReactNativeStaticServer.framework' \
-framework './build/ReactNativeStaticServer.framework-iphoneos.xcarchive/Products/Library/Frameworks/ReactNativeStaticServer.framework' \
-output './build/ReactNativeStaticServer.xcframework'

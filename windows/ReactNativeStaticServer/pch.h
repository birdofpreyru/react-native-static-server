#pragma once

#define NOMINMAX

#include <hstring.h>
#include <restrictederrorinfo.h>
#include <unknwn.h>
#include <windows.h>
#include <CppWinRTIncludes.h>
#if __has_include(<VersionMacros.h>)
  #include <VersionMacros.h>
#endif

#include <winrt/Microsoft.ReactNative.h>

#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Networking.Connectivity.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.h>

using namespace winrt::Windows::Foundation;

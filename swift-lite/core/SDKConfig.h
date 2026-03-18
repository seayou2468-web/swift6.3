#pragma once

#include <optional>
#include <string>

namespace swiftlite {

struct SDKConfig {
  std::string sdkRoot;
  std::string runtimeRoot;
  std::string targetTriple;

  bool hasSDK() const;
  bool hasRuntime() const;
};

SDKConfig &globalSDKConfig();
std::optional<std::string> validateDirectory(const std::string &path);

} // namespace swiftlite

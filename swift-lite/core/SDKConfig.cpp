#include "SDKConfig.h"

#include <filesystem>

namespace swiftlite {

bool SDKConfig::hasSDK() const { return !sdkRoot.empty(); }
bool SDKConfig::hasRuntime() const { return !runtimeRoot.empty(); }

SDKConfig &globalSDKConfig() {
  static SDKConfig config;
  return config;
}

std::optional<std::string> validateDirectory(const std::string &path) {
  if (path.empty()) {
    return "path is empty";
  }

  std::error_code ec;
  const auto state = std::filesystem::status(path, ec);
  if (ec || !std::filesystem::exists(state)) {
    return "path does not exist: " + path;
  }
  if (!std::filesystem::is_directory(state)) {
    return "path is not a directory: " + path;
  }
  return std::nullopt;
}

} // namespace swiftlite

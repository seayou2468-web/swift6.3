#include "SDKConfig.h"

#include <string>
#include <vector>

namespace swiftlite {

std::vector<std::string> buildClangImporterArgs(const SDKConfig &config) {
  std::vector<std::string> args;
  if (!config.sdkRoot.empty()) {
    args.push_back("-isysroot");
    args.push_back(config.sdkRoot);
    args.push_back("-F");
    args.push_back(config.sdkRoot + "/System/Library/Frameworks");
    args.push_back("-I");
    args.push_back(config.sdkRoot + "/usr/include");
  }
  if (!config.targetTriple.empty()) {
    args.push_back("-target");
    args.push_back(config.targetTriple);
  }
  return args;
}

} // namespace swiftlite

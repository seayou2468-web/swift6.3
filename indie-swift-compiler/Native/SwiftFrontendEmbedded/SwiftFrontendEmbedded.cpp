#include "swift/FrontendTool/FrontendTool.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

namespace {

std::string getEnv(std::string_view key) {
  if (const char *value = std::getenv(std::string(key).c_str())) {
    if (*value != '\0') {
      return std::string(value);
    }
  }
  return "";
}

std::string resolveTargetTriple(const char *targetTriple) {
  if (targetTriple && *targetTriple != '\0') {
    return std::string(targetTriple);
  }
  return getEnv("SWIFT_TARGET_TRIPLE");
}

std::string resolveSDKPath(const char *sdkPath) {
  if (sdkPath && *sdkPath != '\0') {
    return std::string(sdkPath);
  }
  return getEnv("SWIFT_SDK_PATH");
}

std::string resolveResourceDir() {
  return getEnv("SWIFT_RESOURCE_DIR");
}

int performFrontendInvocation(const std::vector<std::string> &args) {
  llvm::SmallVector<const char *, 32> argv;
  argv.reserve(args.size());
  for (const std::string &arg : args) {
    argv.push_back(arg.c_str());
  }

  return swift::performFrontend(
      argv,
      "swift-frontend-embedded",
      reinterpret_cast<void *>(&swift::performFrontend),
      nullptr);
}

int emitWithFrontend(
    const char *swiftSource,
    const char *moduleName,
    const char *outputPath,
    const char *targetTriple,
    const char *sdkPath,
    bool emitSIL) {
  if (!swiftSource || !moduleName || !outputPath) {
    return -3;
  }

  char tempTemplate[] = "/tmp/swift-frontend-embedded-XXXXXX";
  char *tempDirRaw = mkdtemp(tempTemplate);
  if (!tempDirRaw) {
    return -102;
  }

  const std::filesystem::path tempDir(tempDirRaw);
  const std::filesystem::path inputFile = tempDir / "input.swift";

  {
    std::ofstream out(inputFile);
    if (!out.is_open()) {
      std::filesystem::remove_all(tempDir);
      return -103;
    }
    out << swiftSource;
  }

  std::vector<std::string> args = {
      "-frontend",
      emitSIL ? "-emit-silgen" : "-emit-ir",
      inputFile.string(),
      "-module-name",
      moduleName,
      "-o",
      outputPath,
      "-parse-as-library",
  };

  const std::string target = resolveTargetTriple(targetTriple);
  if (!target.empty()) {
    args.emplace_back("-target");
    args.emplace_back(target);
  }

  const std::string sdk = resolveSDKPath(sdkPath);
  if (!sdk.empty()) {
    args.emplace_back("-sdk");
    args.emplace_back(sdk);
  }

  const std::string resourceDir = resolveResourceDir();
  if (!resourceDir.empty()) {
    args.emplace_back("-resource-dir");
    args.emplace_back(resourceDir);
  }

  const int rc = performFrontendInvocation(args);
  std::filesystem::remove_all(tempDir);
  return rc == 0 ? 0 : -200 - rc;
}

} // namespace

extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path) {
  return emitWithFrontend(
      swift_source,
      module_name,
      out_ll_path,
      target_triple,
      sdk_path,
      false);
}

extern "C" int swift_frontend_embedded_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path,
    const char *target_triple,
    const char *sdk_path) {
  return emitWithFrontend(
      swift_source,
      module_name,
      out_sil_path,
      target_triple,
      sdk_path,
      true);
}

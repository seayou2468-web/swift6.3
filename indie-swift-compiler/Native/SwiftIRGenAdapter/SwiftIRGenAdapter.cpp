#include "SwiftIRGenAdapter.h"

#include <cstdlib>
#include <filesystem>
#include <string>
#include <thread>

namespace {
#if defined(__GNUC__) || defined(__clang__)
extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path) __attribute__((weak));
#else
extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path);
#endif

swift_irgen_adapter_compile_fn gCompileCallback = nullptr;

std::string resolveSDKPath() {
  if (const char *home = std::getenv("HOME")) {
    std::filesystem::path documentsSDK = std::filesystem::path(home) / "Documents" / "sdk";
    if (std::filesystem::exists(documentsSDK)) {
      return documentsSDK.string();
    }
  }
  if (const char *sdkPath = std::getenv("SWIFT_SDK_PATH")) {
    if (*sdkPath != '\0') {
      return std::string(sdkPath);
    }
  }
  return "";
}

std::string resolveTargetTriple() {
  if (const char *target = std::getenv("SWIFT_TARGET_TRIPLE")) {
    if (*target != '\0') {
      return std::string(target);
    }
  }
  return "";
}

swift_irgen_adapter_compile_fn resolveCompileCallback() {
  if (gCompileCallback != nullptr) {
    return gCompileCallback;
  }
#if defined(__GNUC__) || defined(__clang__)
  if (swift_frontend_embedded_compile != nullptr) {
    return swift_frontend_embedded_compile;
  }
#endif
  return nullptr;
}
} // namespace

int swift_irgen_adapter_set_frontend_path(const char *swift_frontend_path) {
  (void)swift_frontend_path;
  return -9;
}

int swift_irgen_adapter_set_compile_callback(swift_irgen_adapter_compile_fn callback) {
  gCompileCallback = callback;
  return gCompileCallback ? 0 : -10;
}

int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path) {
  if (!swift_source || !module_name || !out_ll_path) {
    return -3;
  }

  swift_irgen_adapter_compile_fn callback = resolveCompileCallback();
  if (!callback) {
    return -7;
  }

  const std::string target = resolveTargetTriple();
  const std::string sdk = resolveSDKPath();

  int rc = -6;
  std::thread compileThread([&]() {
    rc = callback(
        swift_source,
        module_name,
        out_ll_path,
        target.empty() ? nullptr : target.c_str(),
        sdk.empty() ? nullptr : sdk.c_str());
  });
  compileThread.join();

  return rc;
}

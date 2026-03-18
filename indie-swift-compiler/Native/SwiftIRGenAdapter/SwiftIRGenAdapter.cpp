#include "SwiftIRGenAdapter.h"

#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
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
extern "C" int swift_frontend_embedded_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path,
    const char *target_triple,
    const char *sdk_path) __attribute__((weak));
extern "C" int swift_irgen_embedded_emit_ir_from_sil(
    const char *input_sil_path,
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
extern "C" int swift_frontend_embedded_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path,
    const char *target_triple,
    const char *sdk_path);
extern "C" int swift_irgen_embedded_emit_ir_from_sil(
    const char *input_sil_path,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path);
#endif

using SILMandatoryEntryFn = int (*)(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

using SILPerformanceEntryFn = int (*)(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

swift_irgen_adapter_compile_fn gCompileCallback = nullptr;
swift_irgen_adapter_emit_sil_fn gEmitSILCallback = nullptr;
swift_irgen_adapter_emit_ir_from_sil_fn gEmitIRFromSILCallback = nullptr;

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

swift_irgen_adapter_emit_sil_fn resolveEmitSILCallback() {
  if (gEmitSILCallback != nullptr) {
    return gEmitSILCallback;
  }
#if defined(__GNUC__) || defined(__clang__)
  if (swift_frontend_embedded_emit_sil != nullptr) {
    return swift_frontend_embedded_emit_sil;
  }
#endif
  return nullptr;
}

swift_irgen_adapter_emit_ir_from_sil_fn resolveEmitIRFromSILCallback() {
  if (gEmitIRFromSILCallback != nullptr) {
    return gEmitIRFromSILCallback;
  }
#if defined(__GNUC__) || defined(__clang__)
  if (swift_irgen_embedded_emit_ir_from_sil != nullptr) {
    return swift_irgen_embedded_emit_ir_from_sil;
  }
#endif
  return nullptr;
}

SILMandatoryEntryFn resolveSILMandatoryFunction() {
  void *symbol = dlsym(nullptr, "swift_sil_optimizer_adapter_run_mandatory");
  if (!symbol) {
    return nullptr;
  }
  return reinterpret_cast<SILMandatoryEntryFn>(symbol);
}

SILPerformanceEntryFn resolveSILPerformanceFunction() {
  void *symbol = dlsym(nullptr, "swift_sil_optimizer_adapter_run_performance");
  if (!symbol) {
    return nullptr;
  }
  return reinterpret_cast<SILPerformanceEntryFn>(symbol);
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

int swift_irgen_adapter_set_emit_sil_callback(swift_irgen_adapter_emit_sil_fn callback) {
  gEmitSILCallback = callback;
  return gEmitSILCallback ? 0 : -10;
}

int swift_irgen_adapter_set_emit_ir_from_sil_callback(
    swift_irgen_adapter_emit_ir_from_sil_fn callback) {
  gEmitIRFromSILCallback = callback;
  return gEmitIRFromSILCallback ? 0 : -10;
}

int swift_irgen_adapter_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path) {
  if (!swift_source || !module_name || !out_sil_path) {
    return -3;
  }

  swift_irgen_adapter_emit_sil_fn callback = resolveEmitSILCallback();
  if (!callback) {
    return -7;
  }

  const std::string target = resolveTargetTriple();
  const std::string sdk = resolveSDKPath();

  int rc = -6;
  std::thread silThread([&]() {
    rc = callback(
        swift_source,
        module_name,
        out_sil_path,
        target.empty() ? nullptr : target.c_str(),
        sdk.empty() ? nullptr : sdk.c_str());
  });
  silThread.join();
  return rc;
}

int swift_irgen_adapter_emit_ir_from_sil(
    const char *input_sil_path,
    const char *module_name,
    const char *out_ll_path) {
  if (!input_sil_path || !module_name || !out_ll_path) {
    return -3;
  }

  swift_irgen_adapter_emit_ir_from_sil_fn callback = resolveEmitIRFromSILCallback();
  if (!callback) {
    return -7;
  }

  const std::string target = resolveTargetTriple();
  const std::string sdk = resolveSDKPath();

  int rc = -6;
  std::thread irThread([&]() {
    rc = callback(
        input_sil_path,
        module_name,
        out_ll_path,
        target.empty() ? nullptr : target.c_str(),
        sdk.empty() ? nullptr : sdk.c_str());
  });
  irThread.join();
  return rc;
}

int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path) {
  if (!swift_source || !module_name || !out_ll_path) {
    return -3;
  }

  if (resolveEmitSILCallback() != nullptr &&
      resolveEmitIRFromSILCallback() != nullptr &&
      resolveSILMandatoryFunction() != nullptr &&
      resolveSILPerformanceFunction() != nullptr) {
    const std::filesystem::path workDir =
        std::filesystem::temp_directory_path() / std::filesystem::path("swift-irgen-adapter");
    std::filesystem::create_directories(workDir);
    const auto rawSIL = (workDir / "raw.sil").string();
    const auto mandatorySIL = (workDir / "mandatory.sil").string();
    const auto optimizedSIL = (workDir / "optimized.sil").string();

    int silRC = swift_irgen_adapter_emit_sil(swift_source, module_name, rawSIL.c_str());
    if (silRC != 0) {
      return silRC;
    }
    int mandatoryRC =
        resolveSILMandatoryFunction()(rawSIL.c_str(), module_name, mandatorySIL.c_str());
    if (mandatoryRC != 0) {
      return mandatoryRC;
    }
    int perfRC =
        resolveSILPerformanceFunction()(mandatorySIL.c_str(), module_name, optimizedSIL.c_str());
    if (perfRC != 0) {
      return perfRC;
    }
    return swift_irgen_adapter_emit_ir_from_sil(optimizedSIL.c_str(), module_name, out_ll_path);
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

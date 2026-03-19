#include "SwiftSILOptimizerAdapter.h"

#include <filesystem>

namespace {
#if defined(__GNUC__) || defined(__clang__)
extern "C" int swift_sil_optimizer_embedded_run_mandatory(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path) __attribute__((weak));
extern "C" int swift_sil_optimizer_embedded_run_performance(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path) __attribute__((weak));
#else
extern "C" int swift_sil_optimizer_embedded_run_mandatory(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);
extern "C" int swift_sil_optimizer_embedded_run_performance(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);
#endif

swift_sil_optimizer_adapter_mandatory_fn gMandatoryCallback = nullptr;
swift_sil_optimizer_adapter_performance_fn gPerformanceCallback = nullptr;

swift_sil_optimizer_adapter_mandatory_fn resolveMandatoryCallback() {
  if (gMandatoryCallback != nullptr) {
    return gMandatoryCallback;
  }
#if defined(__GNUC__) || defined(__clang__)
  if (swift_sil_optimizer_embedded_run_mandatory != nullptr) {
    return swift_sil_optimizer_embedded_run_mandatory;
  }
#endif
  return nullptr;
}

swift_sil_optimizer_adapter_performance_fn resolvePerformanceCallback() {
  if (gPerformanceCallback != nullptr) {
    return gPerformanceCallback;
  }
#if defined(__GNUC__) || defined(__clang__)
  if (swift_sil_optimizer_embedded_run_performance != nullptr) {
    return swift_sil_optimizer_embedded_run_performance;
  }
#endif
  return nullptr;
}

} // namespace

int swift_sil_optimizer_adapter_set_mandatory_callback(
    swift_sil_optimizer_adapter_mandatory_fn callback) {
  gMandatoryCallback = callback;
  return gMandatoryCallback ? 0 : -10;
}

int swift_sil_optimizer_adapter_set_performance_callback(
    swift_sil_optimizer_adapter_performance_fn callback) {
  gPerformanceCallback = callback;
  return gPerformanceCallback ? 0 : -10;
}

int swift_sil_optimizer_adapter_run_mandatory(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path) {
  if (!input_sil_path || !module_name || !out_sil_path) {
    return -3;
  }

  if (swift_sil_optimizer_adapter_mandatory_fn callback = resolveMandatoryCallback()) {
    return callback(input_sil_path, module_name, out_sil_path);
  }

  return -7;
}

int swift_sil_optimizer_adapter_run_performance(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path) {
  if (!input_sil_path || !module_name || !out_sil_path) {
    return -3;
  }

  if (swift_sil_optimizer_adapter_performance_fn callback = resolvePerformanceCallback()) {
    return callback(input_sil_path, module_name, out_sil_path);
  }

  return -7;
}

int swift_sil_optimizer_adapter_optimize(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path) {
  if (!input_sil_path || !module_name || !out_sil_path) {
    return -3;
  }

  const std::filesystem::path workDir =
      std::filesystem::temp_directory_path() / std::filesystem::path("swift-siloptimizer-adapter");
  std::filesystem::create_directories(workDir);
  const auto mandatoryOut = (workDir / "mandatory.sil").string();

  int mandatoryRC =
      swift_sil_optimizer_adapter_run_mandatory(input_sil_path, module_name, mandatoryOut.c_str());
  if (mandatoryRC != 0) {
    return mandatoryRC;
  }
  return swift_sil_optimizer_adapter_run_performance(
      mandatoryOut.c_str(), module_name, out_sil_path);
}

const char *swift_sil_optimizer_adapter_stage_name(int layer) {
  return layer == 0 ? "SILOptimizerMandatory" : "SILOptimizerPerformance";
}

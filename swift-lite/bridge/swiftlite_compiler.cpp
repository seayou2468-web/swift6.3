#include "swiftlite_compiler.h"

#include "../core/NativePipeline.h"
#include "../core/SwiftFrontendPipeline.h"
#include "../core/SDKConfig.h"

#include <string>

using swiftlite::globalSDKConfig;
using swiftlite::validateDirectory;

namespace {

thread_local std::string g_lastMessage;

static const char *persist_message(const std::string &message) {
  g_lastMessage = message;
  return g_lastMessage.c_str();
}

static void fill_diag(swiftlite_diagnostics *d, swiftlite_error_code code,
                      const std::string &message) {
  if (!d) {
    return;
  }
  d->code = code;
  d->line = 0;
  d->column = 0;
  d->message = persist_message(message);
}

static std::string resolve_sdk_root(const swiftlite_compile_options *options) {
  if (options->sdk_root && options->sdk_root[0] != '\0') {
    return options->sdk_root;
  }
  return globalSDKConfig().sdkRoot;
}

static std::string resolve_runtime_root(const swiftlite_compile_options *options) {
  if (options->runtime_root && options->runtime_root[0] != '\0') {
    return options->runtime_root;
  }
  return globalSDKConfig().runtimeRoot;
}

static swiftlite_error_code validate_options(const swiftlite_compile_options *options,
                                             swiftlite_diagnostics *diag) {
  if (!options || !options->output_path || !options->target_triple) {
    fill_diag(diag, SWL_ERR_INVALID_ARGUMENT,
              "options/output_path/target_triple must be set");
    return SWL_ERR_INVALID_ARGUMENT;
  }

  std::string sdkRoot = resolve_sdk_root(options);
  if (auto err = validateDirectory(sdkRoot); err.has_value()) {
    fill_diag(diag, SWL_ERR_SDK_NOT_FOUND, *err);
    return SWL_ERR_SDK_NOT_FOUND;
  }

  std::string runtimeRoot = resolve_runtime_root(options);
  if (auto err = validateDirectory(runtimeRoot); err.has_value()) {
    fill_diag(diag, SWL_ERR_RUNTIME_NOT_FOUND, *err);
    return SWL_ERR_RUNTIME_NOT_FOUND;
  }

  if (options->emit_llvm_ir && (!options->llvm_ir_path || !options->llvm_ir_path[0])) {
    fill_diag(diag, SWL_ERR_INVALID_ARGUMENT,
              "llvm_ir_path must be set when emit_llvm_ir=1");
    return SWL_ERR_INVALID_ARGUMENT;
  }

  return SWL_OK;
}

static swiftlite::SDKConfig make_sdk_config(const swiftlite_compile_options *options) {
  swiftlite::SDKConfig config;
  config.sdkRoot = resolve_sdk_root(options);
  config.runtimeRoot = resolve_runtime_root(options);
  config.targetTriple = options->target_triple ? options->target_triple : "";
  return config;
}

} // namespace

extern "C" const char *swiftlite_error_string(swiftlite_error_code code) {
  switch (code) {
  case SWL_OK:
    return "ok";
  case SWL_ERR_INVALID_ARGUMENT:
    return "invalid argument";
  case SWL_ERR_SDK_NOT_FOUND:
    return "SDK path not found";
  case SWL_ERR_RUNTIME_NOT_FOUND:
    return "runtime path not found";
  case SWL_ERR_PARSE_FAILED:
    return "SwiftSyntax parse failed";
  case SWL_ERR_AST_BRIDGE_FAILED:
    return "SwiftSyntax -> AST bridge failed";
  case SWL_ERR_SEMA_FAILED:
    return "semantic analysis failed";
  case SWL_ERR_SIL_FAILED:
    return "SIL generation/optimization failed";
  case SWL_ERR_IRGEN_FAILED:
    return "IRGen failed";
  case SWL_ERR_EMIT_FAILED:
    return "emit object/IR failed";
  case SWL_ERR_UNSUPPORTED_SYNTAX:
    return "unsupported syntax in MVP";
  case SWL_ERR_INTERNAL:
  default:
    return "internal error";
  }
}

extern "C" swiftlite_error_code swiftlite_set_sdk_root(const char *sdk_root) {
  if (!sdk_root) {
    return SWL_ERR_INVALID_ARGUMENT;
  }

  std::string value(sdk_root);
  if (auto err = validateDirectory(value); err.has_value()) {
    return SWL_ERR_SDK_NOT_FOUND;
  }
  globalSDKConfig().sdkRoot = value;
  return SWL_OK;
}

extern "C" swiftlite_error_code swiftlite_set_runtime_root(
    const char *runtime_root) {
  if (!runtime_root) {
    return SWL_ERR_INVALID_ARGUMENT;
  }

  std::string value(runtime_root);
  if (auto err = validateDirectory(value); err.has_value()) {
    return SWL_ERR_RUNTIME_NOT_FOUND;
  }
  globalSDKConfig().runtimeRoot = value;
  return SWL_OK;
}

extern "C" swiftlite_error_code swiftlite_compile_to_object(
    const char *source, size_t source_len, const swiftlite_compile_options *options,
    swiftlite_diagnostics *diagnostics) {
  if (!source || source_len == 0) {
    fill_diag(diagnostics, SWL_ERR_INVALID_ARGUMENT, "source is empty");
    return SWL_ERR_INVALID_ARGUMENT;
  }

  if (auto code = validate_options(options, diagnostics); code != SWL_OK) {
    return code;
  }

  const auto config = make_sdk_config(options);
  const std::string moduleName =
      (options->module_name && options->module_name[0]) ? options->module_name : "swiftlite";
  const std::string clangPath =
      (options->clang_path && options->clang_path[0]) ? options->clang_path : "clang";

  const bool preferSwiftFrontend = swiftlite::isSwiftFrontendPipelineAvailable();

  const auto result = preferSwiftFrontend
                          ? swiftlite::compileWithSwiftFrontend(
                                std::string(source, source_len), config,
                                options->target_triple, options->output_path,
                                moduleName, false)
                          : swiftlite::compileToObject(std::string(source, source_len),
                                                       config,
                                                       options->target_triple,
                                                       options->output_path,
                                                       moduleName,
                                                       clangPath);

  if (result.code != SWL_OK) {
    fill_diag(diagnostics, result.code, result.message);
    return result.code;
  }

  if (options->emit_llvm_ir) {
    const auto irResult = preferSwiftFrontend
                              ? swiftlite::compileWithSwiftFrontend(
                                    std::string(source, source_len), config,
                                    options->target_triple, options->llvm_ir_path,
                                    moduleName, true)
                              : swiftlite::emitLLVMIR(std::string(source, source_len),
                                                      config,
                                                      options->target_triple,
                                                      options->llvm_ir_path,
                                                      moduleName,
                                                      clangPath);
    if (irResult.code != SWL_OK) {
      fill_diag(diagnostics, irResult.code, irResult.message);
      return irResult.code;
    }
  }

  fill_diag(diagnostics, SWL_OK, "ok");
  return SWL_OK;
}

extern "C" swiftlite_error_code swiftlite_emit_ir(
    const char *source, size_t source_len, const swiftlite_compile_options *options,
    swiftlite_diagnostics *diagnostics) {
  if (!source || source_len == 0 || !options || !options->llvm_ir_path) {
    fill_diag(diagnostics, SWL_ERR_INVALID_ARGUMENT,
              "source/options/llvm_ir_path must be set");
    return SWL_ERR_INVALID_ARGUMENT;
  }

  if (auto code = validate_options(options, diagnostics); code != SWL_OK) {
    return code;
  }

  const auto config = make_sdk_config(options);
  const std::string moduleName =
      (options->module_name && options->module_name[0]) ? options->module_name : "swiftlite";
  const std::string clangPath =
      (options->clang_path && options->clang_path[0]) ? options->clang_path : "clang";

  const bool preferSwiftFrontend = swiftlite::isSwiftFrontendPipelineAvailable();
  const auto result = preferSwiftFrontend
                          ? swiftlite::compileWithSwiftFrontend(
                                std::string(source, source_len), config,
                                options->target_triple, options->llvm_ir_path,
                                moduleName, true)
                          : swiftlite::emitLLVMIR(std::string(source, source_len),
                                                  config,
                                                  options->target_triple,
                                                  options->llvm_ir_path,
                                                  moduleName,
                                                  clangPath);
  if (result.code != SWL_OK) {
    fill_diag(diagnostics, result.code, result.message);
    return result.code;
  }

  fill_diag(diagnostics, SWL_OK, "ok");
  return SWL_OK;
}

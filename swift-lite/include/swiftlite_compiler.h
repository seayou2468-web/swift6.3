#ifndef SWIFTLITE_COMPILER_H
#define SWIFTLITE_COMPILER_H

#include <stddef.h>
#include <stdint.h>

#include "swiftlite_errors.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct swiftlite_diagnostics {
  const char *message;
  int32_t line;
  int32_t column;
  swiftlite_error_code code;
} swiftlite_diagnostics;

typedef struct swiftlite_compile_options {
  const char *module_name;
  const char *target_triple;   // 例: arm64-apple-ios17.0
  const char *sdk_root;        // アプリが解決したSDKパス
  const char *runtime_root;    // stdlib/runtime配置先
  const char *output_path;     // object file path
  uint8_t emit_llvm_ir;        // 1: .ll を追加出力
  const char *llvm_ir_path;    // emit_llvm_ir=1 時に必要
  const char *clang_path;      // 未指定時は clang を使用
} swiftlite_compile_options;

swiftlite_error_code swiftlite_set_sdk_root(const char *sdk_root);
swiftlite_error_code swiftlite_set_runtime_root(const char *runtime_root);

swiftlite_error_code swiftlite_compile_to_object(const char *source,
                                                 size_t source_len,
                                                 const swiftlite_compile_options *options,
                                                 swiftlite_diagnostics *diagnostics);

swiftlite_error_code swiftlite_emit_ir(const char *source,
                                       size_t source_len,
                                       const swiftlite_compile_options *options,
                                       swiftlite_diagnostics *diagnostics);

#ifdef __cplusplus
}
#endif

#endif // SWIFTLITE_COMPILER_H

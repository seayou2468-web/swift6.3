#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Swift->LLVM IR 生成の将来拡張用 API。
/// swift-frontend 実行パスを設定する（0:成功, 非0:失敗）。
int swift_irgen_adapter_set_frontend_path(const char *swift_frontend_path);

/// SwiftソースからLLVM IR(.ll)を出力する。
/// 0: 成功, 非0: 失敗
int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path);

#ifdef __cplusplus
}
#endif

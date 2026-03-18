#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Swift->LLVM IR 生成の将来拡張用 API。
/// 互換API（CLIベースの path 指定は廃止）。
/// 常に -9 を返す。
int swift_irgen_adapter_set_frontend_path(const char *swift_frontend_path);

/// 埋め込みfrontendライブラリのコンパイル関数シグネチャ。
/// source/module/out_ll_path/target_triple/sdk_path を受け取る。
typedef int (*swift_irgen_adapter_compile_fn)(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path);

/// 埋め込みfrontendの関数ポインタを設定する（0:成功）。
int swift_irgen_adapter_set_compile_callback(swift_irgen_adapter_compile_fn callback);

/// SwiftソースからLLVM IR(.ll)を出力する。
/// SDK は優先順で HOME/Documents/sdk -> SWIFT_SDK_PATH。
/// 処理は内部でスレッド起動して callback を呼び出す（CLI起動なし）。
/// 0: 成功, 非0: 失敗
int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path);

#ifdef __cplusplus
}
#endif

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

/// Swift ソースから raw SIL を生成する関数シグネチャ。
typedef int (*swift_irgen_adapter_emit_sil_fn)(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path,
    const char *target_triple,
    const char *sdk_path);

/// SIL から LLVM IR を生成する関数シグネチャ。
typedef int (*swift_irgen_adapter_emit_ir_from_sil_fn)(
    const char *input_sil_path,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path);

/// 埋め込みfrontendの関数ポインタを設定する（0:成功）。
int swift_irgen_adapter_set_compile_callback(swift_irgen_adapter_compile_fn callback);

/// 埋め込みfrontendの SIL 生成関数を設定する（0:成功）。
int swift_irgen_adapter_set_emit_sil_callback(swift_irgen_adapter_emit_sil_fn callback);

/// 埋め込み IRGen の SIL->IR 変換関数を設定する（0:成功）。
int swift_irgen_adapter_set_emit_ir_from_sil_callback(
    swift_irgen_adapter_emit_ir_from_sil_fn callback);

/// Swift ソースから raw SIL(.sil) を出力する。
int swift_irgen_adapter_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path);

/// SIL(.sil) から LLVM IR(.ll) を出力する。
int swift_irgen_adapter_emit_ir_from_sil(
    const char *input_sil_path,
    const char *module_name,
    const char *out_ll_path);

/// SwiftソースからLLVM IR(.ll)を出力する。
/// SDK は優先順で HOME/Documents/sdk -> SWIFT_SDK_PATH。
/// 処理は内部でスレッド起動して callback を呼び出す（CLI起動なし）。
/// 0: 成功, 非0: 失敗
int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path);

#ifdef __cplusplus
}
#endif

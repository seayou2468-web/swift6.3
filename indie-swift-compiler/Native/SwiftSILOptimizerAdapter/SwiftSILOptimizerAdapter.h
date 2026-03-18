#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// mandatory層で入力SILファイルを canonical SIL に整える callback シグネチャ。
typedef int (*swift_sil_optimizer_adapter_mandatory_fn)(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

/// performance層で canonical SIL を最適化する callback シグネチャ。
typedef int (*swift_sil_optimizer_adapter_performance_fn)(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

/// mandatory層 callback を登録する。
int swift_sil_optimizer_adapter_set_mandatory_callback(
    swift_sil_optimizer_adapter_mandatory_fn callback);

/// performance層 callback を登録する。
int swift_sil_optimizer_adapter_set_performance_callback(
    swift_sil_optimizer_adapter_performance_fn callback);

/// 入力SILファイルを mandatory 層へ通す。
int swift_sil_optimizer_adapter_run_mandatory(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

/// 入力SILファイルを performance 層へ通す。
int swift_sil_optimizer_adapter_run_performance(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

/// mandatory + performance の2層を順に実行する互換API。
int swift_sil_optimizer_adapter_optimize(
    const char *input_sil_path,
    const char *module_name,
    const char *out_sil_path);

/// 埋め込み済みSILOptimizer層を識別する固定文字列を返す。
const char *swift_sil_optimizer_adapter_stage_name(int layer);

#ifdef __cplusplus
}
#endif

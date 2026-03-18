# swift-lite (MVP)

`swift-lite` は upstream Swift リポジトリを直接改造せず、
SwiftSyntax + Swift compiler core を使って iOS 実機向けコンパイラライブラリを構築するための最小レイヤーです。

## 目的
- `swiftc` の置き換えではなく、iOS アプリへ組み込み可能なコンパイラコアを提供
- 出力は `libswiftlite.a` を優先し、最終的に `xcframework` を生成
- MVP は「基本構文 (import / var / let / func(Int固定戻り値))」を対象

## 非対象（MVP時点）
- SwiftPM の統合
- CLI ツールの提供
- テストスイート全体のビルド
- iOS 以外の配布ターゲット

## ディレクトリ構成
- `include/`: 外部公開 C API
- `bridge/`: SwiftSyntax と C/C++ core を接続する Swift/C shim
- `core/`: SDK/Runtime 設定、ClangImporter オプション変換
- `scripts/`: 最小ビルド/パッケージング
- `docs/`: ビルド方針・マトリクス
- `package/`: 配布レイアウト定義

## SDK の扱い
SDK は同梱しません。アプリ側から SDK ルートを渡してください。

## 現在のMVP実装
- `swiftlite_compile_to_object` は、MVP対応構文をネイティブコード生成パイプラインへ流し、最終的に `.o` を生成します。
- 現段階のバックエンドは **Swift構文サブセット（複数行func対応） -> Cコード変換 -> clang でネイティブ生成** です（`swift-frontend` 依存なし）。
- `swiftlite_emit_ir` は同一経路で LLVM IR (`.ll`) を出力します。
- `SwiftLiteMVPValidator` は SwiftSyntax で基本構文のみを許可する前段バリデーションとして利用可能です。

## 使い方（概要）
1. `scripts/build-core.sh` で iOS arm64 向けに `libswiftlite.a` を生成
2. `scripts/package-ios.sh` でヘッダとライブラリを収集
3. `scripts/create-xcframework.sh` で `swiftlite.xcframework` を生成

## Swift AST/Sema/SIL/IRGen 直結モード（新規）
`SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE=ON` でビルドすると、`swift::performFrontend` を in-process 呼び出しするバックエンドを優先利用します。

- 必須 CMake 変数:
  - `SWIFTLITE_SWIFT_FRONTEND_INCLUDE_DIR`（`swift/include` へのパス）
  - `SWIFTLITE_SWIFT_FRONTEND_LIBS`（リンク対象ライブラリ群。セミコロン区切り）
- このモードでは `-frontend` パイプラインをライブラリ内部から実行し、AST/Sema/SIL/IRGen を経由して `.o` / `.ll` を生成します。
- 変数未設定の場合は CMake エラーにして誤設定を防止します。


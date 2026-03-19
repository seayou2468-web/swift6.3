# Indie Swift Compiler (抽出内蔵コンパイラベース)

## 1. ビルド対象と環境（最初に確認）

| 項目 | 値 |
|---|---|
| 対象端末 | iPhone / iPad (iOS 15+) |
| 開発環境 | Xcode 26.1.1, Swift 6.3ツールチェーン |
| 使用言語 | Swift |
| 出力物 | `MiniSwiftCompilerCore(.xcframework)` / `Clang.xcframework` / `LLVM.xcframework`（依存込み配布） |

> 注意: iOSアプリ内での「ネイティブコードJIT実行」は制約があります。ここでの実装は、**Swiftソース → LLVM IR文字列生成**までを担当します。

## 2. 目的

- Swift本家リポジトリのフロントエンド〜IRGenの流れを参照しつつ、
- ビルド時に `../swift` ディレクトリへ依存しない、
- Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を抽出して独自コンパイラへ直接内蔵する。

## 3. ディレクトリ構成

```text
indie-swift-compiler/
  Makefile
  Package.swift
  Sources/
    MiniSwiftCompilerCore/
      MiniCompiler.swift
      CompilerBridge.swift
  Tools/
    generate_minimal_update_checkout_config.py
    generate_profiled_update_checkout_config.py
    create_irgen_bundle.py
    analyze_irgen_dependencies.py
    sync_toolchain_repos.py
  Config/
    minimal-update-checkout-config.json
    compatibility-profile.json
    irgen-source-set.json
    sil-source-set.json
    irgen-dependency-report.json
    sil-dependency-report.json
  Docs/
    IOS_OFFLINE_COMPILER_STRATEGY.md
  Native/
    SwiftIRGenAdapter/
      SwiftIRGenAdapter.h
      SwiftIRGenAdapter.cpp
    SwiftSILOptimizerAdapter/
      SwiftSILOptimizerAdapter.h
      SwiftSILOptimizerAdapter.cpp
  Vendor/
    SwiftFrontendExtract/      # 完全抽出した内蔵用コピー
  Examples/
    hello.swift
```

## 4. 目的
この独自コンパイラは Swift コードから LLVM IR を生成し LLVM に渡すまでを目的とする。
フロントエンド実行ファイルへの依存は廃止し、Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を完全抽出対象として直接内蔵する。
LLVM と Clang への依存は許可し、それらは `LLVM.xcframework` と `Clang.xcframework` として解決する。

現在最優先で進めるべきことは、抽出コンポーネント群の内蔵化と llvm / clang の xcframework 整備である。


## 5. iOS アプリへの内蔵
- SwiftPM では `MiniSwiftCompilerCore` (dynamic) または `MiniSwiftCompilerCoreStatic` (static) を利用できる。
- アプリ側では `MiniCompilerIOSAdapter` と `MiniCompilerToolchainLayout` を使って `SWIFT_RESOURCE_DIR` / `SWIFT_SDK_PATH` / `SWIFT_TARGET_TRIPLE` を設定し、抽出済みコンパイラを直接呼び出せる。
- LLVM/Clang 単体配布物は手動実行の `make manual-release` で `Release/` に生成する。

- 抽出コピー更新は `./Scripts/extract_swift_pipeline.sh` をそのまま実行すればよく、外部 Swift リポジトリ指定は不要。


## 6. ワークフロー
- `./Scripts/build_embedded_compiler_stack.sh` は、独自コンパイラ用の最小 `update-checkout` 同期 (`bootstrap_minimal_toolchain_repos.sh`) → `swift/` から抽出コピー更新 → `LLVM.xcframework` / `Clang.xcframework` のビルド → `MiniSwiftCompilerCore` の release build を一連で実行する。
- 抽出対象は Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen のみで、`swift-frontend` 実行ファイルや Frontend / Driver 層は抽出しない。
- GitHub Actions では `build-embedded-compiler-stack.yml` を手動実行して同じ流れを再現できる。
- `./Scripts/build_production_and_demo_app_pipeline.sh` は、独自コンパイラ用の最小 `update-checkout` 同期を先に実行したうえで、`LLVM/Clang.xcframework` ビルド → `MiniSwiftCompilerCore` ビルド → `EmbeddedCompilerIDE` ビルドを順序保証つきで実行し、`Release/DemoAppBuildInputs/` に入力成果物をステージする。
- GitHub Actions では `build-production-and-demo-app.yml` を手動実行すると、この順序保証スクリプトを使って同じフローを再現できる。
- `Demo/EmbeddedCompilerIDE` には、本番 API (`MiniCompilerAppService`) を使って任意のランタイムレス Swift コードをコンパイルし、LLVM IR と実行推定結果を表示する簡易 IDE アプリ実装を置いている。

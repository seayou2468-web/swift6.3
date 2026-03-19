# Indie Swift Compiler (swift-frontend adapterベース)

## 1. ビルド対象と環境（最初に確認）

| 項目 | 値 |
|---|---|
| 対象端末 | iPhone / iPad (iOS 15+) |
| 開発環境 | Xcode 26.1.1, Swift 6.3ツールチェーン |
| 使用言語 | Swift |
| 出力物 | `SwiftToolchainKit.xcframework`（単一配布） |

> 注意: iOSアプリ内での「ネイティブコードJIT実行」は制約があります。ここでの実装は、**Swiftソース → LLVM IR文字列生成**までを担当します。

## 2. 目的

- Swift本家リポジトリのフロントエンド〜IRGenの流れを参照しつつ、
- ビルド時に `../swift` ディレクトリへ依存しない、
- 独立した最小コンパイラ（サブセット）を構築する。

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
    SwiftFrontendExtract/      # 参照用コピー（ビルド不使用）
  Examples/
    hello.swift
```

## 4. 目的
この独自コンパイラはswiftコードからllvm irの生成しllvmに渡すまでを目的としている。
swift-frontendをllvmの依存なしでビルドし、swiftコードをswift-frontendでsilにしてそこからsiloptimに渡しsil最適化し、irgenに渡してllvm ir生成しそこからllvmに渡すようにする。

現在最優先で進めるべきことはllvm&clangのビルドである。

# Indie Swift Compiler App

## 1. ビルド対象と環境（最初に確認）

| 項目 | 値 |
|---|---|
| 対象端末 | iPhone / iPad (iOS 15+) |
| 開発環境 | Xcode 26.1.1, Swift 6.3ツールチェーン |
| 使用言語 | Swift |
| 出力物 | 
`Clang.xcframework` / `LLVM.xcframework`（依存込み配布） |

> 注意: iOSアプリ内での「ネイティブコードJIT実行」は制約があります。ここでの実装は、**Swiftソース → LLVMコンパイル**までを担当します。

## 2. 目的

- Swift本家リポジトリのフロントエンド〜IRGenの流れを参照しつつ、
- ビルド時に `../swift` ディレクトリへ依存しない、
- Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を抽出してアプリへ直接内蔵する。

## 3. 目的
このアプリは Swift コードから 内蔵したParser / AST / Sema / SILGen / SIL / SILOptimizer / IRGenと、llvmと、clangを通じてコンパイルすることが目的。
フロントエンド実行ファイルへの依存は廃止し、Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を完全抽出対象として直接内蔵する。
LLVM と Clang への依存は許可し、それらは `LLVM.xcframework` と `Clang.xcframework` として解決する。

現在最優先で進めるべきことは、抽出コンポーネント群の内蔵化と llvm / clang の xcframework 整備である。


## 5. iOS アプリへの内蔵。
- LLVM/Clang 単体配布物は手動実行の `make manual-release` で `Release/` に生成する。

- 抽出コピー更新は `./Scripts/extract_swift_pipeline.sh` をそのまま実行すればよく、外部 Swift リポジトリ指定は不要。

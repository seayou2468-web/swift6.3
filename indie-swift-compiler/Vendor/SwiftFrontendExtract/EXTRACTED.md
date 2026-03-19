# Extracted Swift Embedded Compiler Components

このディレクトリは、このリポジトリ直下の `swift/` ツリーから Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を
直接コピーして、独自コンパイラに内蔵するための作業コピーです。

- 外部の swift リポジトリパス指定は不要です。
- `Scripts/extract_swift_pipeline.sh` は常にこのリポジトリ直下の `swift/` からコピーします。
- 新規コンパイラは swift-frontend 実行ファイルではなく、ここでコピーした層を直接内蔵する方針です。
- `swift-frontend` 実行ファイル / Frontend / Driver 層は抽出禁止としてスクリプトで検証しています。

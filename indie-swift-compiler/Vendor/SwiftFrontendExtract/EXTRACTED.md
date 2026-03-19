# Extracted Swift  Compiler App Components

このディレクトリは、このリポジトリ直下の `swift/` ツリーから Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen を
直接コピーして、アプリに内蔵するための作業コピーです。

- 外部の swift リポジトリパス指定は不要です。
- `Scripts/extract_swift_pipeline.sh` は常にこのリポジトリ直下の `swift/` からコピーします。
- アプリはここでコピーした層を直接内蔵する方針です。

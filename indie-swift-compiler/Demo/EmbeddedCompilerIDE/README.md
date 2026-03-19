# EmbeddedCompilerIDE Demo App

このフォルダは、`MiniSwiftCompilerCore` を iOS アプリへ内蔵するための簡易 IDE デモです。

## 想定デモ
- `print("Hello, world!")` のような簡単な Swift コードを入力
- `Compile & Run Hello World` を押す
- LLVM IR とデモ実行結果を表示

## 実装メモ
- `EmbeddedCompilerIDEViewModel` は `EmbeddedCompilerDemoIDE` を使ってコンパイルとデモ実行を行います。
- 実行結果は `EmbeddedCompilerDemoExecutor` による簡易デモ用ランタイム推定です。
- LLVM / Clang の xcframework と `MiniSwiftCompilerCore` をアプリ側へ同梱して使う前提です。

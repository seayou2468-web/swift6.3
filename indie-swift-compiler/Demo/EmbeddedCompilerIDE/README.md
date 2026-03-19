# EmbeddedCompilerIDE Demo App

このフォルダは、`MiniSwiftCompilerCore` を iOS アプリへ内蔵するための簡易 IDE デモです。

## 想定デモ
- Swift ソースを入力
- `Compile & Run (Runtime-less)` を押す
- LLVM IR とランタイムレス実行結果を表示

## 実装メモ
- `EmbeddedCompilerIDEViewModel` は `MiniCompilerAppService` を使って本番アプリ向け API でコンパイルと実行を行います。
- 実行結果は `MiniCompilerRuntimeLessExecutor` によるランタイムレス実行推定です。
- LLVM / Clang の xcframework と `MiniSwiftCompilerCore` をアプリ側へ同梱して使う前提です。

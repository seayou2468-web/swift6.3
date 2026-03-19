# EmbeddedCompilerIDE iOS Demo App

このフォルダは、`MiniSwiftCompilerCore` を iOS アプリへ内蔵するための簡易 IDE デモです。

## 想定デモ
- Swift ソースを入力
- `Compile & Run (Runtime-less)` を押す
- LLVM IR とランタイムレス実行結果を表示

## 実装メモ
- `EmbeddedCompilerIDEViewModel` は `MiniCompilerAppService` を使って本番アプリ向け API でコンパイルと実行を行います。
- 実行結果は `MiniCompilerRuntimeLessExecutor` によるランタイムレス実行推定です。
- iOS アプリ本体は `Demo/EmbeddedCompilerIDE-iOS/EmbeddedCompilerIDE.xcodeproj` から **実機向け (`iphoneos`)** にビルドします。
- LLVM / Clang の xcframework を静的リンクしつつ、`Sources/MiniSwiftCompilerCore` のコンパイラ実装をアプリへ取り込みます。

# EmbeddedCompilerIDE Demo App

このフォルダは、`MiniSwiftCompilerCore` を iOS アプリへ内蔵するための簡易 IDE デモです。

## 想定デモ
- 文字列出力や整数演算を含む簡単な Swift コードを入力
- `Compile & Run` を押す
- LLVM IR と実行結果を表示

## 実装メモ
- アプリ側は本番向け API `EmbeddedCompilerAppRuntime` を使ってコンパイルと実行を行います。
- デモアプリの `RuntimeFreeExecutionBackend` は、Swift ランタイム非依存のコードを対象に、文字列出力・変数参照・整数演算・`return` / `print` を扱う簡易実行バックエンドです。
- LLVM / Clang の xcframework と `MiniSwiftCompilerCore` をアプリ側へ同梱して使う前提です。

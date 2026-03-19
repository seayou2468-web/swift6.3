# iOSオフラインSwiftコンパイル戦略（フル互換Lite）

## 目的

- ネットワークやサーバー不要で、端末内のみでSwiftソースを処理する。
- Swift言語互換を最大化しつつ、不要機能を削った最小依存ツールチェーンを使う。

## 現実的な実装方針

1. **ビルド時に最小ツールチェーンを同梱**
   - 抽出・内蔵した `Parser / AST / Sema / SILGen / SIL / SILOptimizer / IRGen`
   - `llvm-project`
   - `clang`
   - `swift-syntax`, `swift-llvm-bindings`
2. **アプリ実行時はローカルのみ**
   - `MiniCompiler` は `parser -> ast -> sema -> silgen -> sil -> SILOptimizer(mandatory) -> SILOptimizer(performance) -> IRGen -> LLVM` の段階実行を優先
   - `swift-frontend` 実行ファイルには依存しない
   - 抽出済みコンポーネントの利用を明示的に許可する
   - サーバー通信なし
3. **実行モデルを分離**
   - `コンパイル(ソース->IR)` と `実行` を分離し、iOS制約に抵触しない運用を選ぶ

## 重要な制約

- iOSアプリでの動的コード実行/JITにはプラットフォーム制約がある。
- そのため、"コンパイル可能" と "任意コードをその場でネイティブ実行可能" は同義ではない。

## このリポジトリでの位置づけ

- `MiniCompiler` は抽出内蔵した `parser / ast / sema / silgen / sil / SILOptimizer / IRGen` を順に呼び出して LLVM IR を生成し、LLVM へ進む。
- 構成マニフェスト `Config/compiler-pipeline.json` で
  `swift -> parser -> ast -> sema -> silgen -> sil -> sil-optimizer-mandatory -> sil-optimizer-performance -> irgen -> llvm`
  を固定化する。
- `compatibility-profile.json` で依存/機能削減ポリシーを管理する。


## 配布とリリース運用

- LLVM / Clang は独自コンパイラ本体とは分離して単体ビルドする。
- リリース成果物は `LLVM.xcframework` と `Clang.xcframework` をそれぞれ zip 化して配布する。
- 自動実行ではなく、`make manual-release` または GitHub Actions の `workflow_dispatch` から手動で生成する。
- iOS アプリは `MiniSwiftCompilerCore` と上記 xcframework 群を同梱して、抽出済みパイプラインをアプリ内で利用する。

- 抽出用コピーはこのリポジトリ同梱の `swift/` から `./Scripts/extract_swift_pipeline.sh` で再生成し、外部 checkout を要求しない。

- 一連の手順は `./Scripts/build_embedded_compiler_stack.sh` と `build-embedded-compiler-stack.yml` で、LLVM/Clang xcframework の生成から独自コンパイラ release build まで手動実行できる。
- `Demo/EmbeddedCompilerIDE` は iOS 組み込み用の簡易 IDE デモで、Hello World のコンパイル結果とデモ実行結果を表示する。

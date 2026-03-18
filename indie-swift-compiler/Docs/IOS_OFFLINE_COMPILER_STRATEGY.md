# iOSオフラインSwiftコンパイル戦略（フル互換Lite）

## 目的

- ネットワークやサーバー不要で、端末内のみでSwiftソースを処理する。
- Swift言語互換を最大化しつつ、不要機能を削った最小依存ツールチェーンを使う。

## 現実的な実装方針

1. **ビルド時に最小ツールチェーンを同梱**
   - `swift-frontend`
   - `llvm-project`（必要なライブラリのみ）
   - `cmark`, `swift-syntax`, `swift-driver`, `swift-llvm-bindings`
2. **アプリ実行時はローカルのみ**
   - `swift-frontend -emit-ir` 相当のパスをローカルで実行
   - サーバー通信なし
3. **実行モデルを分離**
   - `コンパイル(ソース->IR)` と `実行` を分離し、iOS制約に抵触しない運用を選ぶ

## 重要な制約

- iOSアプリでの動的コード実行/JITにはプラットフォーム制約がある。
- そのため、"コンパイル可能" と "任意コードをその場でネイティブ実行可能" は同義ではない。

## このリポジトリでの位置づけ

- `MiniCompiler` は
  - `lightweight`（軽量/限定）
  - `swiftFrontend`（互換優先）
  の2経路を持つ。
- `compatibility-profile.json` で依存/機能削減ポリシーを管理する。

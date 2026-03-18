# swift6.3

このリポジトリには、`swift/`（上流Swift）とは独立してビルドできる
`indie-swift-compiler/` を追加しています（CLI非搭載、iOS組み込み向けFramework構成）。

- 新規コンパイラ実装: `indie-swift-compiler/`（単一配布 `SwiftToolchainKit.xcframework` 生成スクリプト付き）
- 上流 `swift/` は参照抽出時のみ利用（ビルド依存なし）
- ツールチェーン同期はリポジトリ内の最小JSON + 独自同期スクリプトで完結（Swift本家スクリプト非依存）
- `update-checkout` 最小JSON生成で、Swift/LLVM/Clang取得リポジトリを必要最小限に制限
- 「フル互換Lite」（言語互換優先＋不要機能削減）の方針を追加
- iOSオフラインコンパイル方針ドキュメントを追加
- 抽出したSwift IRGenソースを最小バンドルとして再利用する仕組みを追加
- 抽出IRGenのヘッダ依存を可視化する依存分析スクリプトを追加
- 抽出IRGen接続の実装開始として Native Adapter ライブラリ土台を追加

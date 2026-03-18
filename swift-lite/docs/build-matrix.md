# swift-lite Build Matrix (MVP)

| 項目 | サポート |
|---|---|
| Host | macOS (GitHub Actions macos-latest) |
| Target | iOS device arm64 only |
| Primary artifact | `libswiftlite.a` |
| Optional artifact | `swiftlite.xcframework` |
| SDK bundle | しない（外部指定） |
| SwiftPM | 非対応 |
| CLI | 非対応 |
| test build | 非対応 |

## 方針
- compiler-core only でビルドし、不要ターゲットを参照しない。
- upstream の全体ビルドではなく `swift-lite` 独立レイヤーから必要最小限を起動する。

## MVPネイティブコード生成方式
- Swift構文サブセットをCコードへ変換し、clangで `.o` / `.ll` を生成します。
- `swift-frontend` サブプロセス実行には依存しません。
- 将来は Swift AST/Sema/SIL/IRGen 直結へ置き換える設計です。


### 構文サブセット
- `import <Module>`
- `let/var <name> = <int>`
- `func <name>() -> Int { return <int> }`（単一行/複数行）


### コンパイルバックエンド選択
- 既定: Swiftサブセット -> C -> clang
- `SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE=ON`: `swift::performFrontend` 直結（AST/Sema/SIL/IRGen 経路）

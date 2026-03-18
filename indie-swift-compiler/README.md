# Indie Swift Compiler (SwiftSyntaxベース)

## 1. ビルド対象と環境（最初に確認）

| 項目 | 値 |
|---|---|
| 対象端末 | iPhone / iPad (iOS 15+) |
| 開発環境 | Xcode 26.1.1, Swift 6.3ツールチェーン |
| 使用言語 | Swift |
| 出力物 | `SwiftToolchainKit.xcframework`（単一配布） |

> 注意: iOSアプリ内での「ネイティブコードJIT実行」は制約があります。ここでの実装は、**Swiftソース → LLVM IR文字列生成**までを担当します。

## 2. 目的

- Swift本家リポジトリのフロントエンド〜IRGenの流れを参照しつつ、
- ビルド時に `../swift` ディレクトリへ依存しない、
- 独立した最小コンパイラ（サブセット）を構築する。

## 3. ディレクトリ構成

```text
indie-swift-compiler/
  Package.swift
  Sources/
    MiniSwiftCompilerCore/
      MiniCompiler.swift
      CompilerBridge.swift
  Scripts/
    extract_swift_pipeline.sh
    prepare_irgen_source_bundle.sh
    analyze_irgen_dependencies.sh
    build_extracted_irgen_lib.sh
    bootstrap_minimal_toolchain_repos.sh
    build_swift_compiler_xcframework.sh
    build_llvm_clang_xcframework.sh
    build_unified_toolchain_xcframework.sh
  Tools/
    generate_minimal_update_checkout_config.py
    generate_profiled_update_checkout_config.py
    create_irgen_bundle.py
    analyze_irgen_dependencies.py
    sync_toolchain_repos.py
  Config/
    minimal-update-checkout-config.json
    compatibility-profile.json
    irgen-source-set.json
    irgen-dependency-report.json
  Docs/
    IOS_OFFLINE_COMPILER_STRATEGY.md
  Native/
    SwiftIRGenAdapter/
      SwiftIRGenAdapter.h
      SwiftIRGenAdapter.cpp
  Vendor/
    SwiftFrontendExtract/      # 参照用コピー（ビルド不使用）
  Examples/
    hello.swift
```

## 4. できること（現状）

- `func foo() -> Int { return 1 + 2 }` のようなシンプルな関数をパース。
- `let` 束縛 + 変数参照 + `+ - * /` を含む式を独自IRにlowering。
- LLVM IR 文字列を生成（`alloca/load/add/sub/mul/sdiv/ret`）。
- `swift-frontend` はパス未指定でも自動探索（`SWIFT_FRONTEND_PATH` → `xcrun --find` → `PATH`）。
- Swift frontend adapter を `libSwiftFrontend.a` + `SwiftIRGenAdapter.h` として iOS/simulator 向けに生成可能。
- `swift_irgen_adapter_compile` シンボルをリンク済みなら、Swift側は `.h`/`.a` 経由で実行（Swift側CLI起動なし）。
- frontend 実行時の `-sdk` は iOSアプリ内 `Documents/sdk` を最優先で使用（未存在時は環境変数・xcrun）。

## 5. クイックスタート

```bash
cd indie-swift-compiler
swift build
swift test
```

## 6. Swift本体からの参照抽出（任意）

```bash
./Scripts/extract_swift_pipeline.sh ../swift
```

この抽出結果は参照専用です。本コンパイラのビルドには使いません。

抽出済みソースを「最小依存のIRGenバンドル」として使う場合:

```bash
./Scripts/prepare_irgen_source_bundle.sh
```

これにより `Generated/SwiftIRGenExtract/` に、`irgen-source-set.json` で定義した
最小ソースセットと `CMakeLists.txt` が生成されます。

依存分析を行う場合:

```bash
./Scripts/analyze_irgen_dependencies.sh
```

`irgen-dependency-report.json` が生成され、抽出ソースが要求する `swift/*`, `llvm/*`, `clang/*`
ヘッダ依存を可視化できます。

抽出IRGen利用の実装開始（Adapterライブラリのビルド）:

```bash
./Scripts/build_extracted_irgen_lib.sh ./.toolchain-workspace release/6.3
```

このステップで `Native/SwiftIRGenAdapter` の C API を起点に、抽出IRGenへの接続実装を進めます。

現在の Adapter API:

- `swift_irgen_adapter_set_frontend_path(const char*)`
- `swift_irgen_adapter_compile(const char*, const char*, const char*)`

`libSwiftFrontend.a` 側の callback を C API で叩き、内部スレッドでコンパイル処理を実行します。

## 6.1 最小依存だけ取得する（update-checkout最小JSON）

```bash
./Scripts/bootstrap_minimal_toolchain_repos.sh release/6.3 ./.toolchain-workspace
```

この処理は次を行います。

1. `compatibility-profile.json` の `enable` を使って必要最小限リポジトリのみ抽出
2. `Config/minimal-update-checkout-config.json` を生成
3. `sync_toolchain_repos.py` で最小セットだけ clone/update

既定の抽出対象:

- `swift`
- `llvm-project`
- `cmark`
- `swift-syntax`
- `swift-llvm-bindings`

無効化ポリシー（`compatibility-profile.json`）:

- Swift Package Manager 連携
- Macro system
- Indexing / IDE support
- Driver（`swiftc` 相当）

## 7. XCFramework生成

```bash
./Scripts/build_swift_compiler_xcframework.sh
```

出力:

```text
Artifacts/MiniSwiftCompilerCore.xcframework
```

LLVM/Clang も個別にXCFramework化する場合:

```bash
./Scripts/build_llvm_clang_xcframework.sh /path/to/llvm-project
```

出力:

```text
Artifacts/LLVM.xcframework
Artifacts/Clang.xcframework
```

単一のXCFrameworkにまとめる場合（推奨）:

```bash
./Scripts/build_unified_toolchain_xcframework.sh release/6.3
```

GitHub Actions（`macos-latest`）でリリース順ビルドを行う場合:

```bash
# 手元実行
./Scripts/ci_release_ordered_build.sh release/6.3

# CI実行
.github/workflows/release-toolchain.yml
```

Workflow は順番固定で次を実行し、成果物を `upload-artifact` でダウンロード可能にします。

1. `swift test`
2. `bootstrap_minimal_toolchain_repos`
3. `build_unified_toolchain_xcframework`（llvm/clang -> swift frontend lib -> core -> unified）
4. `build_swift_frontend_xcframework`
5. `build_swift_runtime_xcframework`（任意）

Linux上で `Swift -> swift-frontend -> LLVM -> 実行` を検証する場合は以下を使用します。

```bash
./Scripts/verify_swift_frontend_to_llvm_pipeline.sh
```

`llvm-as` / `llc` が無い環境では `clang -x ir` で直接リンクするフォールバック経路で検証します。

`ci_release_ordered_build.sh` は本番向けに以下も実施します。

- 必須成果物（`SwiftToolchainKit.xcframework`, `SwiftFrontend.xcframework`）の存在チェック
- `Dist/release-manifest.txt` 出力（scheme, build_id, commit, 生成物一覧）
- 各 xcframework zip の SHA-256 および最終配布zipの SHA-256 を `Dist/release-checksums.txt` に出力
- `Scripts/verify_release_bundle.sh` で manifest / checksums / 必須成果物を検証

このスクリプトは以下を順番に実行します。

1. `Config/minimal-update-checkout-config.json` から `release/6.3` の `llvm-project` ref を取得
2. LLVM/Clang を arm64 (device/simulator) でビルド
3. MiniSwiftCompilerCore をビルド
4. `SwiftToolchainKit.xcframework` を生成

統合XCFrameworkには以下を同梱します。

- `MiniSwiftCompilerCore.framework`（device/simulator）
- `libSwiftFrontend.a` + `SwiftIRGenAdapter.h`（device/simulator）
- `libLLVM.a` / `libclang-cpp.a`（device/simulator）

## 8. iOS組み込み

1. 生成した `MiniSwiftCompilerCore.xcframework` をXcodeに追加。
2. `Frameworks, Libraries, and Embedded Content` に設定。
3. 以下のように呼び出し:

```swift
import MiniSwiftCompilerCore

let bridge = MiniSwiftCompilerBridge()
let ir = try bridge.compileToIR(
    source: "func main() -> Int { return 40 + 2 }",
    moduleName: "AppModule"
)
print(ir)
```

`swift-frontend` モードの呼び出し:

```swift
import MiniSwiftCompilerCore

let bridge = MiniSwiftCompilerBridge()
let ir = try bridge.compileToIRUsingSwiftFrontend(
    source: "struct S<T> { let value: T }\\nfunc main() -> Int { 1 }",
    moduleName: "AppModule"
)
print(ir)
```

また、以下の環境変数を与えると iOS SDK を指定したIR出力が可能です。

- `SWIFT_TARGET_TRIPLE` (例: `arm64-apple-ios15.0`)
- `SWIFT_SDK_PATH` または `SWIFT_SDK` (例: `iphoneos`)

デフォルトでは `Documents/sdk` が存在すればそれを `-sdk` に使います（アプリ同梱SDK向け）。

## 9. 依存整理

- 必須依存: `swift-syntax`（`SwiftParser`, `SwiftSyntax`）
- `../swift`（本家リポジトリ）: **不要**
- フル対応フェーズで使うツールチェーン取得は `minimal-update-checkout-config.json` 経由で最小化
- 機能方針は `Config/compatibility-profile.json` で管理
- iOSオフライン運用方針は `Docs/IOS_OFFLINE_COMPILER_STRATEGY.md` を参照

## 10. フル互換Lite方針（重要）

このプロジェクトは「Swift本家と同等の全機能」は目指しません。  
代わりに、**Swift言語互換を優先しつつ、不要機能を切り落とした Lite 構成**を目指します。

- 言語互換の主経路: `swift-frontend` バックエンド利用
- 依存最小化: `minimal-update-checkout-config.json`
- 抽出IRGen利用: `irgen-source-set.json` で必要ソースのみをバンドル化
- 方針定義: `compatibility-profile.json`

完全に自前実装だけで本家同等を狙うのではなく、互換性が必要な部分は上流コンポーネントを活用し、
不要な周辺機能（Doc, LSP, Debuggerなど）を除外します。

## 11. 今回の抽出方針（重要）

- `Vendor/SwiftFrontendExtract/` は **Swift本家の処理を丸ごと移植したものではありません**。
- Swift本家からは「フロントエンド〜IRGenの導線確認に必要な参照ファイル」をコピーし、
  独自実装側（`MiniSwiftCompilerCore`）は SwiftSyntax ベースで最小再構築しています。
- そのため、依存は大幅に軽くなりますが、本家と同等機能には未到達です。
- 本家の「フルSwift対応（型検査/SIL最適化/完全IRGen）」を目指す場合は、
  Swiftコンパイラ実装（Frontend, AST, SIL, IRGen）の大規模な取り込みと依存解決が必要です。

# swift6.3

このリポジトリの目的はswiftコンパイラをiOS向けにビルドすることである。
clang&llvmのビルドにはMakefileをつかうこと。
swiftpmなど不要な機能は全てオフにしてビルドする。
全てのビルド対象のテストを全てオフにする。
例えばapiテストなど。
ios以外のプラットフォーム対象を無効化して。
GitHub actionsのmacos-latestを使いビルドする。
xcodeは、26.1.1で、
必要なのは最低限です。
必ずupdate checkoutを、ワークフローの処理に入れること。
必ず設定できるオプションを確認してからビルド設定をすること。
cliツールは全て無効化すること。
最低限の機能しか求めていない。
c/c++/objc\objc++との互換性のオプションは有効化すること。
updatecheckoutでチェックアウトするバージョンはswift6.3に対応したバージョンで。

アプリに組み込むことを目的としているのでそれを考慮して。


## 追加した最小ビルド構成

- `swift/utils/build-presets.ini` に `ios_minimal_compiler_embedded` プリセットを追加した。
- `make swift-ios-minimal` で `update-checkout -> shallow化したsubmodule再初期化 -> build-script -> clang成果物回収` の順番を固定した。
- `update-checkout` は `--skip-history --skip-tags` を使い、さらに submodule も `depth=1` 相当で再初期化するようにした。
- api系を含むテストは `skip-test-swift` / `skip-test-sourcekit` / `skip-test-benchmarks` などの明示フラグで無効化した。
- clang の成果物回収では `clang-c` ヘッダだけでなく、`c++` ヘッダ、`libc++`、`libc++abi`、`libunwind` も回収する。
- GitHub Actions は `macos-latest` 上で `Xcode 26.1.1` を選択し、`release/6.3` の `update-checkout` を `--skip-history --skip-tags` 付きで実行してからビルドする。

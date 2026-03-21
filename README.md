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
- `update-checkout` スクリプト自体を shallow / tagless 前提に寄せ、submodule も `depth=1` 相当で再初期化するようにした。
- stdlib deployment target は `iphoneos-arm64` のみに絞って不要な派生ターゲットを増やさず、LLVM target も `AArch64` のみに限定したうえで、sdk overlay と C++ interop 関連の fallback toolchain content も無効化した。
- api系を含むテストは `skip-test-swift` / `skip-test-sourcekit` / `skip-test-benchmarks` などの明示フラグで無効化した。
- clang の成果物回収では `clang-c` ヘッダに加えて、`c++` ヘッダと `libc++` / `libc++abi` / `libunwind` の関連ファイルも再帰的に回収し、最終的に `LLVM.xcframework` / `Clang.xcframework` / `Swift.xcframework` にまとめる。
- GitHub Actions は `macos-latest` 上で `Xcode 26.1.1` を選択し、`python3 -m venv` で分離した環境を作って `CMAKE_VERSION=3.30.2` の CMake を導入し、`swift/utils/update_checkout/update-checkout-config.json` の `release/6.3` が要求する版と完全一致することを検証してから、update-checkout 用キャッシュと build キャッシュを復元し、`release/6.3` の `update-checkout` を走らせ、CPU 並列数を最大限使ってビルドし、3つの xcframework をダウンロード成果物としてアップロードする。

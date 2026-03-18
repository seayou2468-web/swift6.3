# swift-lite iOS 配布レイアウト

```text
swiftlite-dist/
  include/
    swiftlite_compiler.h
    swiftlite_errors.h
  lib/
    ios-arm64/
      libswiftlite.a
  runtime/
    ios/
      manifest.json
```

## ルール
- SDK は含めない。
- runtime は必須最小セットのみ配置し、`manifest.json` に情報を残す。
- 最終的に `xcodebuild -create-xcframework` で `swiftlite.xcframework` を生成する。

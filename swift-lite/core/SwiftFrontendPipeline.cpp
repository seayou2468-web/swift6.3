#include "SwiftFrontendPipeline.h"

#include <filesystem>
#include <fstream>
#include <vector>

#if SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE
#include "swift/FrontendTool/FrontendTool.h"
#endif

namespace swiftlite {

bool isSwiftFrontendPipelineAvailable() {
#if SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE
  return true;
#else
  return false;
#endif
}

PipelineResult compileWithSwiftFrontend(const std::string &source,
                                        const SDKConfig &config,
                                        const std::string &targetTriple,
                                        const std::string &outputPath,
                                        const std::string &moduleName,
                                        bool emitIR) {
#if SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE
  std::error_code ec;
  const std::filesystem::path outPath(outputPath);
  const auto parent = outPath.parent_path();
  if (!parent.empty()) {
    std::filesystem::create_directories(parent, ec);
    if (ec) {
      return {SWL_ERR_INTERNAL,
              "出力ディレクトリ作成に失敗しました: " + parent.string()};
    }
  }

  const std::filesystem::path tempDir =
      parent.empty() ? std::filesystem::current_path() : parent;
  const std::filesystem::path tempSwift =
      tempDir / (outPath.stem().string() + "_swiftlite_frontend.swift");

  {
    std::ofstream ofs(tempSwift);
    ofs << source;
    ofs.flush();
  }

  if (!std::filesystem::exists(tempSwift)) {
    return {SWL_ERR_INTERNAL, "一時Swiftソース生成に失敗しました"};
  }

  std::vector<std::string> stringArgs;
  stringArgs.push_back("-frontend");
  stringArgs.push_back(emitIR ? "-emit-ir" : "-c");
  stringArgs.push_back(tempSwift.string());
  stringArgs.push_back("-target");
  stringArgs.push_back(targetTriple);
  stringArgs.push_back("-sdk");
  stringArgs.push_back(config.sdkRoot);
  stringArgs.push_back("-module-name");
  stringArgs.push_back(moduleName.empty() ? "swiftlite" : moduleName);
  stringArgs.push_back("-o");
  stringArgs.push_back(outputPath);

  if (!config.runtimeRoot.empty()) {
    stringArgs.push_back("-resource-dir");
    stringArgs.push_back(config.runtimeRoot);
  }

  std::vector<const char *> args;
  args.reserve(stringArgs.size());
  for (const auto &arg : stringArgs) {
    args.push_back(arg.c_str());
  }

  const int rc = swift::performFrontend(args, "swiftlite", nullptr, nullptr);
  std::filesystem::remove(tempSwift, ec);

  if (rc != 0) {
    return {SWL_ERR_EMIT_FAILED,
            "Swift frontend 実行に失敗しました。rc=" + std::to_string(rc)};
  }

  if (!std::filesystem::exists(outPath)) {
    return {SWL_ERR_EMIT_FAILED,
            "Swift frontendは成功しましたが出力ファイルが存在しません: " +
                outputPath};
  }

  return {SWL_OK, ""};
#else
  (void)source;
  (void)config;
  (void)targetTriple;
  (void)outputPath;
  (void)moduleName;
  (void)emitIR;
  return {SWL_ERR_INTERNAL,
          "SWIFTLITE_ENABLE_SWIFT_FRONTEND_CORE=ON で再ビルドしてください"};
#endif
}

} // namespace swiftlite

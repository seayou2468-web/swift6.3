#include "SwiftIRGenAdapter.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

namespace {
std::string gSwiftFrontendPath;
}

int swift_irgen_adapter_set_frontend_path(const char *swift_frontend_path) {
  if (!swift_frontend_path) {
    return -1;
  }
  gSwiftFrontendPath = swift_frontend_path;
  return gSwiftFrontendPath.empty() ? -2 : 0;
}

int swift_irgen_adapter_compile(const char *swift_source, const char *module_name, const char *out_ll_path) {
  if (!swift_source || !module_name || !out_ll_path) {
    return -3;
  }
  if (gSwiftFrontendPath.empty()) {
    return -4;
  }

  std::filesystem::path tempDir = std::filesystem::temp_directory_path() / "swift_irgen_adapter";
  std::error_code ec;
  std::filesystem::create_directories(tempDir, ec);
  if (ec) {
    return -5;
  }

  std::filesystem::path srcPath = tempDir / "input.swift";
  std::ofstream src(srcPath);
  src << swift_source;
  src.close();

  std::string command = "\"" + gSwiftFrontendPath + "\" -frontend -emit-ir \"" + srcPath.string() +
                        "\" -module-name \"" + std::string(module_name) + "\" -o \"" +
                        std::string(out_ll_path) + "\"";

  int rc = std::system(command.c_str());
  return rc == 0 ? 0 : -6;
}

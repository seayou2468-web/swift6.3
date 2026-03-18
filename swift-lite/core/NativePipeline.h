#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "../include/swiftlite_errors.h"
#include "SDKConfig.h"

namespace swiftlite {

struct ParsedVarDecl {
  std::string name;
  int64_t value;
  bool mutableVar;
};

struct ParsedFuncDecl {
  std::string name;
  int64_t returnValue;
};

struct ParsedProgram {
  std::vector<ParsedVarDecl> globals;
  std::vector<ParsedFuncDecl> functions;
};

struct PipelineResult {
  swiftlite_error_code code = SWL_OK;
  std::string message;
};

PipelineResult compileToObject(const std::string &source,
                               const SDKConfig &config,
                               const std::string &targetTriple,
                               const std::string &outputPath,
                               const std::string &moduleName,
                               const std::string &clangPath);

PipelineResult emitLLVMIR(const std::string &source,
                          const SDKConfig &config,
                          const std::string &targetTriple,
                          const std::string &outputPath,
                          const std::string &moduleName,
                          const std::string &clangPath);

} // namespace swiftlite

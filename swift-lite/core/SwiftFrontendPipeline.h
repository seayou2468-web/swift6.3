#pragma once

#include <string>

#include "../include/swiftlite_errors.h"
#include "NativePipeline.h"
#include "SDKConfig.h"

namespace swiftlite {

bool isSwiftFrontendPipelineAvailable();

PipelineResult compileWithSwiftFrontend(const std::string &source,
                                        const SDKConfig &config,
                                        const std::string &targetTriple,
                                        const std::string &outputPath,
                                        const std::string &moduleName,
                                        bool emitIR);

} // namespace swiftlite

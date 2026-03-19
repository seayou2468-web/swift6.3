#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <spawn.h>
#include <string>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char **environ;

namespace {

std::string getEnv(std::string_view key) {
  if (const char *value = std::getenv(std::string(key).c_str())) {
    if (*value != '\0') {
      return std::string(value);
    }
  }
  return "";
}

std::string resolveFrontendPath() {
  return getEnv("SWIFT_FRONTEND_PATH");
}

std::string resolveTargetTriple(const char *targetTriple) {
  if (targetTriple && *targetTriple != '\0') {
    return std::string(targetTriple);
  }
  return getEnv("SWIFT_TARGET_TRIPLE");
}

std::string resolveSDKPath(const char *sdkPath) {
  if (sdkPath && *sdkPath != '\0') {
    return std::string(sdkPath);
  }
  return getEnv("SWIFT_SDK_PATH");
}

int runFrontend(const std::vector<std::string> &args) {
  std::vector<char *> argv;
  argv.reserve(args.size() + 1);
  for (const std::string &arg : args) {
    argv.push_back(const_cast<char *>(arg.c_str()));
  }
  argv.push_back(nullptr);

  pid_t pid = 0;
  int spawnRC = posix_spawn(&pid, argv[0], nullptr, nullptr, argv.data(), environ);
  if (spawnRC != 0) {
    return -120 - spawnRC;
  }

  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    return -160 - errno;
  }
  if (!WIFEXITED(status)) {
    return -180;
  }
  return WEXITSTATUS(status);
}

int emitWithFrontend(
    const char *swiftSource,
    const char *moduleName,
    const char *outputPath,
    const char *targetTriple,
    const char *sdkPath,
    bool emitSIL) {
  if (!swiftSource || !moduleName || !outputPath) {
    return -3;
  }

  const std::string frontendPath = resolveFrontendPath();
  if (frontendPath.empty()) {
    return -101;
  }

  char tempTemplate[] = "/tmp/swift-frontend-XXXXXX";
  char *tempDirRaw = mkdtemp(tempTemplate);
  if (!tempDirRaw) {
    return -102;
  }
  const std::filesystem::path tempDir(tempDirRaw);
  const std::filesystem::path inputFile = tempDir / "input.swift";

  {
    std::ofstream out(inputFile);
    if (!out.is_open()) {
      std::filesystem::remove_all(tempDir);
      return -103;
    }
    out << swiftSource;
  }

  std::vector<std::string> args = {
      frontendPath,
      emitSIL ? "-emit-silgen" : "-emit-ir",
      inputFile.string(),
      "-module-name",
      moduleName,
      "-o",
      outputPath,
      "-parse-as-library",
  };

  const std::string target = resolveTargetTriple(targetTriple);
  if (!target.empty()) {
    args.emplace_back("-target");
    args.emplace_back(target);
  }

  const std::string sdk = resolveSDKPath(sdkPath);
  if (!sdk.empty()) {
    args.emplace_back("-sdk");
    args.emplace_back(sdk);
  }

  const int rc = runFrontend(args);
  std::filesystem::remove_all(tempDir);
  return rc == 0 ? 0 : -200 - rc;
}

} // namespace

extern "C" int swift_frontend_embedded_compile(
    const char *swift_source,
    const char *module_name,
    const char *out_ll_path,
    const char *target_triple,
    const char *sdk_path) {
  return emitWithFrontend(
      swift_source,
      module_name,
      out_ll_path,
      target_triple,
      sdk_path,
      false);
}

extern "C" int swift_frontend_embedded_emit_sil(
    const char *swift_source,
    const char *module_name,
    const char *out_sil_path,
    const char *target_triple,
    const char *sdk_path) {
  return emitWithFrontend(
      swift_source,
      module_name,
      out_sil_path,
      target_triple,
      sdk_path,
      true);
}

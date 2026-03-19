import Foundation
import Testing

@testable import MiniSwiftCompilerCore

@Suite(.serialized)
struct EmbeddedPipelineTests {}

let recordedStagesLock = NSLock()
nonisolated(unsafe) var recordedStagesByModule: [String: [String]] = [:]

func resetRecordedStages() {
  recordedStagesLock.lock()
  defer { recordedStagesLock.unlock() }
  recordedStagesByModule = [:]
}

func appendRecordedStage(_ stage: String, module: String) {
  recordedStagesLock.lock()
  defer { recordedStagesLock.unlock() }
  recordedStagesByModule[module, default: []].append(stage)
}

func recordedStages(for module: String) -> [String] {
  recordedStagesLock.lock()
  defer { recordedStagesLock.unlock() }
  return recordedStagesByModule[module] ?? []
}

@_cdecl("mini_swift_test_emit_sil")
private func mini_swift_test_emit_sil(
  _ swiftSource: UnsafePointer<CChar>?,
  _ moduleName: UnsafePointer<CChar>?,
  _ outSILPath: UnsafePointer<CChar>?,
  _ targetTriple: UnsafePointer<CChar>?,
  _ sdkPath: UnsafePointer<CChar>?
) -> Int32 {
  guard let swiftSource, let moduleName, let outSILPath else { return -101 }
  _ = targetTriple
  _ = sdkPath

  let module = String(cString: moduleName)
  let source = String(cString: swiftSource)
  let outputPath = String(cString: outSILPath)
  for stage in ["parser", "ast", "sema", "silgen", "sil"] {
    appendRecordedStage(stage, module: module)
  }
  let sil = """
    sil_stage raw

    // module: \(module)
    // source: \(source.replacingOccurrences(of: "\n", with: " "))
    """
  do {
    try sil.write(toFile: outputPath, atomically: true, encoding: .utf8)
    return 0
  } catch {
    return -102
  }
}

@_cdecl("mini_swift_test_optimize_sil_mandatory")
private func mini_swift_test_optimize_sil_mandatory(
  _ inputSILPath: UnsafePointer<CChar>?,
  _ moduleName: UnsafePointer<CChar>?,
  _ outSILPath: UnsafePointer<CChar>?
) -> Int32 {
  guard let inputSILPath, let moduleName, let outSILPath else { return -201 }
  do {
    let inputPath = String(cString: inputSILPath)
    let outputPath = String(cString: outSILPath)
    let module = String(cString: moduleName)
    let raw = try String(contentsOfFile: inputPath, encoding: .utf8)
    guard raw.contains("sil_stage raw") else { return -202 }
    appendRecordedStage("sil-optimizer-mandatory", module: module)
    let mandatory = """
      sil_stage canonical

      // mandatory module: \(module)
      \(raw)
      """
    try mandatory.write(toFile: outputPath, atomically: true, encoding: .utf8)
    return 0
  } catch {
    return -203
  }
}

@_cdecl("mini_swift_test_optimize_sil_performance")
private func mini_swift_test_optimize_sil_performance(
  _ inputSILPath: UnsafePointer<CChar>?,
  _ moduleName: UnsafePointer<CChar>?,
  _ outSILPath: UnsafePointer<CChar>?
) -> Int32 {
  guard let inputSILPath, let moduleName, let outSILPath else { return -211 }
  do {
    let inputPath = String(cString: inputSILPath)
    let outputPath = String(cString: outSILPath)
    let module = String(cString: moduleName)
    let mandatory = try String(contentsOfFile: inputPath, encoding: .utf8)
    guard mandatory.contains("sil_stage canonical") else { return -212 }
    appendRecordedStage("sil-optimizer-performance", module: module)
    let optimized = """
      \(mandatory)

      // performance module: \(module)
      """
    try optimized.write(toFile: outputPath, atomically: true, encoding: .utf8)
    return 0
  } catch {
    return -213
  }
}

@_cdecl("mini_swift_test_emit_ir_from_sil")
private func mini_swift_test_emit_ir_from_sil(
  _ inputSILPath: UnsafePointer<CChar>?,
  _ moduleName: UnsafePointer<CChar>?,
  _ outLLPath: UnsafePointer<CChar>?,
  _ targetTriple: UnsafePointer<CChar>?,
  _ sdkPath: UnsafePointer<CChar>?
) -> Int32 {
  _ = targetTriple
  _ = sdkPath
  guard let inputSILPath, let moduleName, let outLLPath else { return -301 }
  do {
    let inputPath = String(cString: inputSILPath)
    let module = String(cString: moduleName)
    let outputPath = String(cString: outLLPath)
    let optimized = try String(contentsOfFile: inputPath, encoding: .utf8)
    guard optimized.contains("sil_stage canonical") else { return -302 }
    guard optimized.contains("performance module") else { return -304 }
    appendRecordedStage("irgen", module: module)
    let ir = """
      ; ModuleID = '\(module)'
      define i64 @main() {
      entry:
        ret i64 42
      }
      """
    try ir.write(toFile: outputPath, atomically: true, encoding: .utf8)
    return 0
  } catch {
    return -303
  }
}

func installEmbeddedPipelineCallbacksForTests() {
  resetRecordedStages()
  let silRC = MiniCompiler.setEmbeddedSILEmitCallback(mini_swift_test_emit_sil)
  let mandatoryRC = MiniCompiler.setEmbeddedSILMandatoryOptimizerCallback(
    mini_swift_test_optimize_sil_mandatory)
  let performanceRC = MiniCompiler.setEmbeddedSILPerformanceOptimizerCallback(
    mini_swift_test_optimize_sil_performance)
  let irRC = MiniCompiler.setEmbeddedIRGenFromSILCallback(mini_swift_test_emit_ir_from_sil)
  #expect(silRC == 0)
  #expect(mandatoryRC == 0)
  #expect(performanceRC == 0)
  #expect(irRC == 0)
}

@Test func simpleFunctionCompilesToIR() throws {
  installEmbeddedPipelineCallbacksForTests()
  let moduleName = "DemoSimple"
  let source = """
    func main() -> Int {
        return 40 + 2
    }
    """

  let output = try MiniCompiler().compileSource(source, moduleName: moduleName)
  #expect(output.llvmIR.contains("define"))
  #expect(output.llvmIR.contains("main"))
  #expect(output.llvmIR.contains("ret"))
  #expect(
    recordedStages(for: moduleName).suffix(3) == [
      "sil-optimizer-mandatory", "sil-optimizer-performance", "irgen",
    ])
}

@Test func letBindingCompilesToIR() throws {
  installEmbeddedPipelineCallbacksForTests()
  let moduleName = "DemoBinding"
  let source = """
    func main() -> Int {
        let x = 40
        return x + 2
    }
    """

  let output = try MiniCompiler().compileSource(source, moduleName: moduleName)
  #expect(output.llvmIR.contains("define"))
  #expect(output.llvmIR.contains(moduleName))
  #expect(output.llvmIR.contains("ret"))
  #expect(
    recordedStages(for: moduleName).suffix(3) == [
      "sil-optimizer-mandatory", "sil-optimizer-performance", "irgen",
    ])
}

@Test func embeddedPipelineArchitectureMatchesExpectedOrder() throws {
  let architecture = try MiniCompiler.defaultArchitecture()
  #expect(
    architecture.stageNames == [
      "swift", "parser", "ast", "sema", "silgen", "sil", "sil-optimizer-mandatory",
      "sil-optimizer-performance", "irgen", "llvm",
    ])
  #expect(architecture.isExpectedEmbeddedOrder)
  #expect(architecture.stages.count == 10)
  #expect(architecture.stages[1].entrypoints.contains("swift_parser_embedded_parse"))
  #expect(architecture.stages[4].entrypoints.contains("swift_silgen_embedded_emit_raw_sil"))
  #expect(architecture.stages[6].entrypoints.contains("swift_sil_optimizer_adapter_run_mandatory"))
  #expect(
    architecture.stages[7].entrypoints.contains("swift_sil_optimizer_adapter_run_performance"))
  #expect(architecture.stages[8].entrypoints.contains("swift_irgen_adapter_emit_ir_from_sil"))
  #expect(architecture.stages[9].entrypoints.contains("llvm_embedded_emit_object"))
}

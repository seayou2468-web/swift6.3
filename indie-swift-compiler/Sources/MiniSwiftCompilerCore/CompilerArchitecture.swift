import Foundation

public enum CompilerStage: String, CaseIterable, Sendable {
  case swift
  case parser
  case ast
  case sema
  case silgen
  case sil
  case silOptimizerMandatory = "sil-optimizer-mandatory"
  case silOptimizerPerformance = "sil-optimizer-performance"
  case irgen
  case llvm
}

public struct CompilerStageDescriptor: Sendable, Equatable {
  public let stage: CompilerStage
  public let kind: String
  public let entrypoints: [String]
  public let dependsOn: [CompilerStage]
}

public struct CompilerArchitecture: Sendable, Equatable {
  public let name: String
  public let goal: String
  public let stages: [CompilerStageDescriptor]

  public var stageOrder: [CompilerStage] {
    stages.map(\.stage)
  }

  public var stageNames: [String] {
    stageOrder.map(\.rawValue)
  }

  public var isExpectedEmbeddedOrder: Bool {
    stageOrder == [
      .swift,
      .parser,
      .ast,
      .sema,
      .silgen,
      .sil,
      .silOptimizerMandatory,
      .silOptimizerPerformance,
      .irgen,
      .llvm,
    ]
  }
}

private struct CompilerPipelineManifest: Decodable {
  struct StageNode: Decodable {
    let kind: String
    let entrypoints: [String]
    let dependsOn: [String]
  }

  let name: String
  let goal: String
  let stageOrder: [String]
  let stages: [String: StageNode]
}

public enum CompilerArchitectureLoader {
  public static func loadDefaultArchitecture() throws -> CompilerArchitecture {
    let manifestURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Config", isDirectory: true)
      .appendingPathComponent("compiler-pipeline.json")

    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(CompilerPipelineManifest.self, from: data)

    let descriptors = try manifest.stageOrder.map { stageName -> CompilerStageDescriptor in
      guard let stage = CompilerStage(rawValue: stageName) else {
        throw MiniCompilerError.unsupportedSyntax("未知のstageです: \(stageName)")
      }
      guard let node = manifest.stages[stageName] else {
        throw MiniCompilerError.unsupportedSyntax("stage定義が不足しています: \(stageName)")
      }

      let deps = try node.dependsOn.map { depName -> CompilerStage in
        guard let dep = CompilerStage(rawValue: depName) else {
          throw MiniCompilerError.unsupportedSyntax("未知の依存stageです: \(depName)")
        }
        return dep
      }

      return CompilerStageDescriptor(
        stage: stage,
        kind: node.kind,
        entrypoints: node.entrypoints,
        dependsOn: deps
      )
    }

    return CompilerArchitecture(
      name: manifest.name,
      goal: manifest.goal,
      stages: descriptors
    )
  }
}

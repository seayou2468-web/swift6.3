import Foundation
import MiniSwiftCompilerCore

struct RuntimeFreeExecutionBackend {
  enum Value: Equatable {
    case integer(Int)
    case string(String)
  }

  static func install() {
    EmbeddedCompilerAppRuntime.setExecutionHandler { request, _ in
      try execute(source: request.source)
    }
  }

  static func execute(source: String) throws -> String {
    var environment: [String: Value] = [:]
    var outputs: [String] = []

    for rawLine in source.split(separator: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("let ") {
        let declaration = String(line.dropFirst(4))
        let parts = declaration.split(separator: "=", maxSplits: 1).map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2 else { continue }
        environment[parts[0]] = try evaluate(parts[1], environment: environment)
        continue
      }

      if line.hasPrefix("print(") && line.hasSuffix(")") {
        let expression = String(line.dropFirst(6).dropLast())
        outputs.append(render(try evaluate(expression, environment: environment)))
        continue
      }

      if line.hasPrefix("return ") {
        let expression = String(line.dropFirst(7))
        outputs.append(render(try evaluate(expression, environment: environment)))
        continue
      }
    }

    return outputs.isEmpty ? "(no output)" : outputs.joined(separator: "\n")
  }

  private static func evaluate(_ expression: String, environment: [String: Value]) throws -> Value {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
      return .string(String(trimmed.dropFirst().dropLast()))
    }
    if let integer = Int(trimmed) {
      return .integer(integer)
    }
    if let value = environment[trimmed] {
      return value
    }

    for op in ["+", "-", "*", "/"] {
      if let range = trimmed.range(of: op) {
        let lhs = try evaluate(String(trimmed[..<range.lowerBound]), environment: environment)
        let rhs = try evaluate(String(trimmed[range.upperBound...]), environment: environment)
        return try apply(op: op, lhs: lhs, rhs: rhs)
      }
    }

    throw NSError(domain: "RuntimeFreeExecutionBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported expression: \(trimmed)"])
  }

  private static func apply(op: String, lhs: Value, rhs: Value) throws -> Value {
    switch (lhs, rhs, op) {
    case let (.integer(left), .integer(right), "+"):
      return .integer(left + right)
    case let (.integer(left), .integer(right), "-"):
      return .integer(left - right)
    case let (.integer(left), .integer(right), "*"):
      return .integer(left * right)
    case let (.integer(left), .integer(right), "/"):
      return .integer(left / right)
    case let (.string(left), .string(right), "+"):
      return .string(left + right)
    default:
      throw NSError(domain: "RuntimeFreeExecutionBackend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported operands for \(op)"])
    }
  }

  private static func render(_ value: Value) -> String {
    switch value {
    case .integer(let integer):
      return String(integer)
    case .string(let string):
      return string
    }
  }
}

import Foundation
import SwiftParser
import SwiftSyntax
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum MiniCompilerError: Error, CustomStringConvertible {
    case sourceReadFailed(String)
    case unsupportedSyntax(String)
    case missingMain
    case swiftFrontendNotFound

    public var description: String {
        switch self {
        case .sourceReadFailed(let path):
            "ソースファイルの読み込みに失敗しました: \(path)"
        case .unsupportedSyntax(let message):
            "未対応の構文です: \(message)"
        case .missingMain:
            "main() 相当のトップレベル式が見つかりませんでした"
        case .swiftFrontendNotFound:
            "swift frontend adapter が未リンクか、実行に必要なツールチェーンが見つかりませんでした"
        }
    }
}

public struct CompileOutput {
    public let llvmIR: String
    public let diagnostics: [String]

    public init(llvmIR: String, diagnostics: [String]) {
        self.llvmIR = llvmIR
        self.diagnostics = diagnostics
    }
}

public struct MiniCompiler {
    public init() {}

    public enum BackendMode {
        /// SwiftSyntaxで最小変換（軽量・限定構文、フォールバック用途）
        case lightweight
        /// swift-frontend へ委譲（Swift本家互換性優先）
        case swiftFrontend
    }

    public func compileSource(_ source: String, moduleName: String = "Main") throws -> CompileOutput {
        if ProcessInfo.processInfo.environment["SWIFT_FRONTEND_ENABLED"] == "1"
            || ProcessInfo.processInfo.environment["SWIFT_FRONTEND_PATH"] != nil {
            return try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
        }
        return try compileSource(source, moduleName: moduleName, mode: .lightweight)
    }

    public func compileSource(
        _ source: String,
        moduleName: String = "Main",
        mode: BackendMode
    ) throws -> CompileOutput {
        switch mode {
        case .lightweight:
            let syntax = Parser.parse(source: source)
            let lowered = try FunctionLowerer().lower(sourceFile: syntax)
            let ir = LLVMIRGenerator().emit(moduleName: moduleName, loweredFunctions: lowered)
            return CompileOutput(llvmIR: ir, diagnostics: [])
        case .swiftFrontend:
            return try SwiftFrontendBridge().emitIR(
                source: source,
                moduleName: moduleName
            )
        }
    }

    public func compileSourceUsingSwiftFrontend(
        _ source: String,
        moduleName: String = "Main"
    ) throws -> CompileOutput {
        try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
    }

    public func compileSource(_ source: String, moduleName: String = "Main", modeRaw: String) throws -> CompileOutput {
        if modeRaw == "swift-frontend" {
            return try compileSource(source, moduleName: moduleName, mode: .swiftFrontend)
        }
        let syntax = Parser.parse(source: source)
        let lowered = try FunctionLowerer().lower(sourceFile: syntax)
        let ir = LLVMIRGenerator().emit(moduleName: moduleName, loweredFunctions: lowered)
        return CompileOutput(llvmIR: ir, diagnostics: [])
    }

    public func compileFile(at path: String, moduleName: String = "Main") throws -> CompileOutput {
        try compileFile(at: path, moduleName: moduleName, mode: .lightweight)
    }

    public func compileFile(
        at path: String,
        moduleName: String = "Main",
        mode: BackendMode
    ) throws -> CompileOutput {
        guard let data = FileManager.default.contents(atPath: path),
              let source = String(data: data, encoding: .utf8) else {
            throw MiniCompilerError.sourceReadFailed(path)
        }

        return try compileSource(source, moduleName: moduleName, mode: mode)
    }
}

indirect enum LoweredExpr {
    case intLiteral(Int)
    case variable(String)
    case binary(op: String, lhs: LoweredExpr, rhs: LoweredExpr)
}

enum LoweredStmt {
    case letBinding(name: String, value: LoweredExpr)
    case `return`(LoweredExpr)
}

struct LoweredFunction {
    let name: String
    let statements: [LoweredStmt]
}

private struct FunctionLowerer {
    func lower(sourceFile: SourceFileSyntax) throws -> [LoweredFunction] {
        var lowered: [LoweredFunction] = []

        for statement in sourceFile.statements {
            guard let function = statement.item.as(FunctionDeclSyntax.self) else {
                continue
            }

            guard function.signature.parameterClause.parameters.isEmpty else {
                throw MiniCompilerError.unsupportedSyntax("引数付き関数: \(function.name.text)")
            }

            guard function.signature.returnClause?.type.as(IdentifierTypeSyntax.self)?.name.text == "Int" else {
                throw MiniCompilerError.unsupportedSyntax("Int 戻り値以外の関数: \(function.name.text)")
            }

            guard let body = function.body else {
                throw MiniCompilerError.unsupportedSyntax("関数本体なし: \(function.name.text)")
            }

            let statements = try extractStatements(from: body)
            lowered.append(LoweredFunction(name: function.name.text, statements: statements))
        }

        guard lowered.isEmpty == false else {
            throw MiniCompilerError.missingMain
        }

        return lowered
    }

    private func extractStatements(from body: CodeBlockSyntax) throws -> [LoweredStmt] {
        var lowered: [LoweredStmt] = []

        for item in body.statements {
            if let bindingDecl = item.item.as(VariableDeclSyntax.self) {
                lowered.append(contentsOf: try lowerBindings(bindingDecl))
                continue
            }

            if let returnStmt = item.item.as(ReturnStmtSyntax.self),
               let expr = returnStmt.expression {
                lowered.append(.return(try lowerExpression(expr)))
            }
        }

        guard lowered.contains(where: {
            if case .return = $0 { return true }
            return false
        }) else {
            throw MiniCompilerError.unsupportedSyntax("return 文が見つかりません")
        }

        return lowered
    }

    private func lowerBindings(_ decl: VariableDeclSyntax) throws -> [LoweredStmt] {
        guard decl.bindingSpecifier.tokenKind == .keyword(.let) else {
            throw MiniCompilerError.unsupportedSyntax("let 以外の変数宣言は未対応")
        }

        var result: [LoweredStmt] = []
        for binding in decl.bindings {
            guard let namePattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                throw MiniCompilerError.unsupportedSyntax("識別子以外のパターン束縛は未対応")
            }
            guard let initClause = binding.initializer else {
                throw MiniCompilerError.unsupportedSyntax("初期化なしletは未対応: \(namePattern.identifier.text)")
            }
            let lowered = try lowerExpression(initClause.value)
            result.append(.letBinding(name: namePattern.identifier.text, value: lowered))
        }
        return result
    }

    private func lowerExpression(_ expr: ExprSyntax) throws -> LoweredExpr {
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            return .intLiteral(Int(intLiteral.literal.text) ?? 0)
        }

        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return .variable(declRef.baseName.text)
        }


        if let seq = expr.as(SequenceExprSyntax.self) {
            let elements = seq.elements
            guard elements.count == 3,
                  let first = elements.first,
                  let middle = elements.dropFirst().first,
                  let last = elements.last,
                  let opExpr = middle.as(BinaryOperatorExprSyntax.self) else {
                throw MiniCompilerError.unsupportedSyntax("未対応の連結式: \(expr.description.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            let lhsExpr = ExprSyntax(first)
            let rhsExpr = ExprSyntax(last)
            let lhs = try lowerExpression(lhsExpr)
            let rhs = try lowerExpression(rhsExpr)
            switch opExpr.operator.text {
            case "+", "-", "*", "/":
                return .binary(op: opExpr.operator.text, lhs: lhs, rhs: rhs)
            default:
                throw MiniCompilerError.unsupportedSyntax("未対応の演算子: \(opExpr.operator.text)")
            }
        }

        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let lhs = ExprSyntax(infix.leftOperand),
           let rhs = ExprSyntax(infix.rightOperand),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            let left = try lowerExpression(lhs)
            let right = try lowerExpression(rhs)
            switch op {
            case "+", "-", "*", "/":
                return .binary(op: op, lhs: left, rhs: right)
            default:
                throw MiniCompilerError.unsupportedSyntax("未対応の演算子: \(op)")
            }
        }

        throw MiniCompilerError.unsupportedSyntax("未対応の式: \(expr.description.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}

private struct LLVMIRGenerator {
    func emit(moduleName: String, loweredFunctions: [LoweredFunction]) -> String {
        var lines: [String] = []
        lines.append("; ModuleID = '\(moduleName)'")
        lines.append("source_filename = \"\(moduleName).swift\"")
        lines.append("")

        for function in loweredFunctions {
            lines.append("define i64 @\(function.name)() {")
            lines.append("entry:")
            var builder = FunctionIRBuilder()
            let body = builder.emit(statements: function.statements)
            lines.append(contentsOf: body)
            lines.append("}")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

private struct FunctionIRBuilder {
    private var nextRegister = 0
    private var variablePtr: [String: String] = [:]
    private var lines: [String] = []

    mutating func emit(statements: [LoweredStmt]) -> [String] {
        for stmt in statements {
            switch stmt {
            case .letBinding(let name, let value):
                let ptr = fresh()
                lines.append("  \(ptr) = alloca i64")
                let v = emitExpr(value)
                lines.append("  store i64 \(v), ptr \(ptr)")
                variablePtr[name] = ptr
            case .return(let expr):
                let rv = emitExpr(expr)
                lines.append("  ret i64 \(rv)")
            }
        }

        if lines.contains(where: { $0.contains("ret i64") }) == false {
            lines.append("  ret i64 0")
        }

        return lines
    }

    private mutating func emitExpr(_ expr: LoweredExpr) -> String {
        switch expr {
        case .intLiteral(let value):
            return "\(value)"
        case .variable(let name):
            guard let ptr = variablePtr[name] else {
                return "0"
            }
            let reg = fresh()
            lines.append("  \(reg) = load i64, ptr \(ptr)")
            return reg
        case .binary(let op, let lhs, let rhs):
            let l = emitExpr(lhs)
            let r = emitExpr(rhs)
            let reg = fresh()
            let instr: String
            switch op {
            case "+": instr = "add"
            case "-": instr = "sub"
            case "*": instr = "mul"
            case "/": instr = "sdiv"
            default: instr = "add"
            }
            lines.append("  \(reg) = \(instr) i64 \(l), \(r)")
            return reg
        }
    }

    private mutating func fresh() -> String {
        defer { nextRegister += 1 }
        return "%\(nextRegister)"
    }
}

private struct SwiftFrontendBridge {
    func emitIR(source: String, moduleName: String) throws -> CompileOutput {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        guard let linkedResult = try SwiftFrontendAdapterBridge().emitIRUsingLinkedAdapter(
            source: source,
            moduleName: moduleName,
            temporaryDirectory: tmpDir
        ) else {
            throw MiniCompilerError.swiftFrontendNotFound
        }
        return linkedResult
    }
}

private struct SwiftFrontendAdapterBridge {
    typealias AdapterCompileFn = @convention(c) (
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32

    func emitIRUsingLinkedAdapter(
        source: String,
        moduleName: String,
        temporaryDirectory: URL
    ) throws -> CompileOutput? {
        guard let compileFn = resolveCompileFunction() else {
            return nil
        }

        let outputPath = temporaryDirectory.appendingPathComponent("output.ll")
        applyEmbeddedSDKDefaults()

        let rc = source.withCString { src in
            moduleName.withCString { mod in
                outputPath.path.withCString { out in
                    compileFn(src, mod, out)
                }
            }
        }

        guard rc == 0 else {
            throw MiniCompilerError.unsupportedSyntax("swift frontend adapter 実行失敗: rc=\(rc)")
        }

        let ir = try String(contentsOf: outputPath, encoding: .utf8)
        return CompileOutput(llvmIR: ir, diagnostics: [])
    }

    private func resolveCompileFunction() -> AdapterCompileFn? {
        guard let symbol = dlsym(nil, "swift_irgen_adapter_compile") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AdapterCompileFn.self)
    }

    private func applyEmbeddedSDKDefaults() {
        if let target = ProcessInfo.processInfo.environment["SWIFT_TARGET_TRIPLE"], !target.isEmpty {
            _ = setenv("SWIFT_TARGET_TRIPLE", target, 1)
        }

        if let sdkPath = ProcessInfo.processInfo.environment["SWIFT_SDK_PATH"], !sdkPath.isEmpty {
            _ = setenv("SWIFT_SDK_PATH", sdkPath, 1)
            return
        }

        if let docsSDK = SwiftFrontendResolver.resolveDocumentsSDKPath() {
            _ = setenv("SWIFT_SDK_PATH", docsSDK, 1)
            return
        }

        if let sdk = ProcessInfo.processInfo.environment["SWIFT_SDK"], !sdk.isEmpty,
           let resolved = SwiftFrontendResolver.resolveSDKPath(sdk: sdk) {
            _ = setenv("SWIFT_SDK_PATH", resolved, 1)
        }
    }
}

private enum SwiftFrontendResolver {
    static func resolveSDKPath(sdk: String) -> String? {
        runAndReadOutput("/usr/bin/xcrun", ["--sdk", sdk, "--show-sdk-path"])
    }

    static func resolveDocumentsSDKPath() -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let sdk = docs.appendingPathComponent("sdk", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sdk.path) else {
            return nil
        }
        return sdk.path
    }

    private static func runAndReadOutput(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

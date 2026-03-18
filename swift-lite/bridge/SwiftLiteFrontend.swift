import Foundation
import SwiftParser
import SwiftSyntax

public enum SwiftLiteFrontendError: Error {
    case emptySource
    case unsupportedSyntax(String)
}

public struct SwiftLiteMVPValidator {
    public init() {}

    /// MVP: import / var / let / func(return Int literal) のみを通す簡易検査
    public func validate(source: String) throws {
        guard !source.isEmpty else {
            throw SwiftLiteFrontendError.emptySource
        }

        let tree = Parser.parse(source: source)
        for stmt in tree.statements {
            let item = stmt.item
            if item.is(ImportDeclSyntax.self) { continue }

            if let variable = item.as(VariableDeclSyntax.self) {
                guard variable.bindings.count == 1,
                      let binding = variable.bindings.first,
                      binding.initializer?.value.is(IntegerLiteralExprSyntax.self) == true else {
                    throw SwiftLiteFrontendError.unsupportedSyntax("MVPでは整数リテラル初期化のみ対応")
                }
                continue
            }

            if let function = item.as(FunctionDeclSyntax.self) {
                let returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
                guard returnType == "Int" else {
                    throw SwiftLiteFrontendError.unsupportedSyntax("MVPでは戻り値 Int のみ対応")
                }

                guard let body = function.body,
                      body.statements.count == 1,
                      let first = body.statements.first?.item.as(ReturnStmtSyntax.self),
                      first.expression?.is(IntegerLiteralExprSyntax.self) == true else {
                    throw SwiftLiteFrontendError.unsupportedSyntax("MVP関数は return <int> のみ対応")
                }
                continue
            }

            throw SwiftLiteFrontendError.unsupportedSyntax(
                "MVPでは未対応の構文: \(item.syntaxNodeType)"
            )
        }
    }
}

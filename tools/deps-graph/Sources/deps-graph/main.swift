// Extracts type declarations and cross-type references from a Swift source tree
// using swift-syntax, and prints them as JSON for scripts/swift-deps-graph.py.
//
// Usage: deps-graph <source-root>
//
// Reference kinds (strongest first):
//   holds    — type of a stored instance property (incl. property wrappers),
//              or the constructor in a stored property's initializer
//   injects  — type of an `init` parameter
//   conforms — inheritance / protocol conformance clause
//   uses     — anything else (local variables, method signatures, static calls)

import Foundation
import SwiftParser
import SwiftSyntax

struct Decl: Codable {
    let name: String  // qualified, e.g. "MacAppModel.State"
    let kind: String  // class | struct | enum | actor | protocol
    let file: String
    let line: Int
    let inherits: [String]  // raw names from the inheritance clause, incl. external (e.g. View)
}

struct RawRef {
    let file: String
    let scope: [String]  // lexical type scope at the reference site
    let path: [String]  // referenced name, possibly dotted (Foo.Bar)
    let kind: String
    let line: Int
}

struct Ref: Codable, Hashable {
    let file: String
    let from: String  // qualified enclosing type ("" for file scope)
    let to: String
    let kind: String
    let line: Int
}

struct Import: Codable {
    let file: String
    let module: String
    let line: Int
}

struct Output: Codable {
    let decls: [Decl]
    let refs: [Ref]
    let imports: [Import]
}

final class Collector: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var scope: [String] = []
    var decls: [Decl] = []
    var refs: [RawRef] = []
    var imports: [Import] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        converter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func line(of node: some SyntaxProtocol) -> Int {
        node.startLocation(converter: converter).line
    }

    // MARK: Scopes and declarations

    private func enter(
        _ node: some DeclGroupSyntax, name: TokenSyntax, kind: String
    ) -> SyntaxVisitorContinueKind {
        scope.append(name.text)
        let inherits =
            node.inheritanceClause?.inheritedTypes.map {
                $0.type.trimmedDescription
            } ?? []
        decls.append(
            Decl(
                name: scope.joined(separator: "."), kind: kind, file: file,
                line: line(of: name), inherits: inherits
            ))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name, kind: "class")
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name, kind: "struct")
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name, kind: "enum")
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name, kind: "actor")
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        enter(node, name: node.name, kind: "protocol")
    }
    override func visitPost(_: ClassDeclSyntax) { scope.removeLast() }
    override func visitPost(_: StructDeclSyntax) { scope.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { scope.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { scope.removeLast() }
    override func visitPost(_: ProtocolDeclSyntax) { scope.removeLast() }

    private var extensionDepths: [Int] = []
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // `import SwiftUI`, `import struct Foundation.URL` -> top-level module name.
        if let module = node.path.first?.name.text {
            imports.append(Import(file: file, module: module, line: line(of: node)))
        }
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // The extended type itself is a reference from file scope.
        let path = typePath(node.extendedType)
        record(path, at: Syntax(node.extendedType), kind: "uses")
        extensionDepths.append(path.count)
        scope.append(contentsOf: path)
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        scope.removeLast(extensionDepths.removeLast())
    }

    // MARK: References

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record([node.name.text], at: Syntax(node), kind: role(of: Syntax(node)))
        return .visitChildren  // generic arguments
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        let path = typePath(TypeSyntax(node))
        if !path.isEmpty {
            record(path, at: Syntax(node), kind: role(of: Syntax(node)))
            if let args = node.genericArgumentClause { walk(args) }
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // Capitalized expression references: `Foo(...)`, `Foo.shared`, `Foo.Bar.baz`.
        guard let first = node.baseName.text.first, first.isUppercase else { return .visitChildren }
        // Skip `.Foo` member accesses — those name members, not types.
        if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
            return .visitChildren
        }
        var kind = role(of: Syntax(node))
        if kind == "holds", !isConstructorCall(node) { kind = "uses" }
        record([node.baseName.text], at: Syntax(node), kind: kind)
        return .visitChildren
    }

    private func record(_ path: [String], at node: Syntax, kind: String) {
        guard !path.isEmpty else { return }
        refs.append(RawRef(file: file, scope: scope, path: path, kind: kind, line: line(of: node)))
    }

    private func typePath(_ type: TypeSyntax) -> [String] {
        if let id = type.as(IdentifierTypeSyntax.self) { return [id.name.text] }
        if let member = type.as(MemberTypeSyntax.self) {
            let base = typePath(member.baseType)
            return base.isEmpty ? [] : base + [member.name.text]
        }
        return []
    }

    private func isConstructorCall(_ node: DeclReferenceExprSyntax) -> Bool {
        guard let call = node.parent?.as(FunctionCallExprSyntax.self) else { return false }
        return call.calledExpression.id == node.id
    }

    /// Classifies a reference by walking up to the nearest meaningful ancestor.
    private func role(of node: Syntax) -> String {
        var current = node.parent
        while let n = current {
            if n.is(InheritanceClauseSyntax.self) { return "conforms" }
            if n.is(CodeBlockSyntax.self) || n.is(ClosureExprSyntax.self) || n.is(MemberBlockSyntax.self) {
                return "uses"
            }
            if let sig = n.as(FunctionSignatureSyntax.self) {
                return sig.parent?.is(InitializerDeclSyntax.self) == true ? "injects" : "uses"
            }
            if let binding = n.as(PatternBindingSyntax.self) {
                return isStoredInstanceProperty(binding) ? "holds" : "uses"
            }
            current = n.parent
        }
        return "uses"
    }

    private func isStoredInstanceProperty(_ binding: PatternBindingSyntax) -> Bool {
        guard let decl = binding.parent?.parent?.as(VariableDeclSyntax.self),
            decl.parent?.is(MemberBlockItemSyntax.self) == true
        else { return false }
        if decl.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) { return false }
        switch binding.accessorBlock?.accessors {
        case .none: return true
        case .getter: return false
        case let .accessors(list):
            // willSet/didSet observers keep storage; get/set do not.
            return list.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        }
    }
}

// MARK: Resolution

/// Resolves `path` against the lexical scope, innermost first: in scope
/// [A, B], name X resolves to A.B.X, then A.X, then X.
func resolve(_ ref: RawRef, in known: [String: Decl]) -> String? {
    for depth in stride(from: ref.scope.count, through: 0, by: -1) {
        let candidate = (ref.scope.prefix(depth) + ref.path).joined(separator: ".")
        if known[candidate] != nil { return candidate }
    }
    return nil
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: deps-graph <source-root>\n".data(using: .utf8)!)
    exit(2)
}
let root = URL(fileURLWithPath: args[1]).standardizedFileURL
let cwd = FileManager.default.currentDirectoryPath + "/"

var decls: [Decl] = []
var rawRefs: [RawRef] = []
var imports: [Import] = []
let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
for case let url as URL in enumerator where url.pathExtension == "swift" {
    let path = url.standardizedFileURL.path
    let rel = path.hasPrefix(cwd) ? String(path.dropFirst(cwd.count)) : path
    let source = try String(contentsOf: url, encoding: .utf8)
    let tree = Parser.parse(source: source)
    let collector = Collector(file: rel, tree: tree)
    collector.walk(tree)
    decls += collector.decls
    rawRefs += collector.refs
    imports += collector.imports
}

var known: [String: Decl] = [:]
for decl in decls where known[decl.name] == nil { known[decl.name] = decl }

var refs = Set<Ref>()
for raw in rawRefs {
    guard let target = resolve(raw, in: known) else { continue }
    let from = raw.scope.joined(separator: ".")
    // Self and enclosing-type references are not dependencies.
    if from == target || from.hasPrefix(target + ".") { continue }
    refs.insert(Ref(file: raw.file, from: from, to: target, kind: raw.kind, line: raw.line))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let output = Output(
    decls: decls.sorted { $0.name < $1.name },
    refs: refs.sorted { ($0.file, $0.line, $0.to, $0.kind) < ($1.file, $1.line, $1.to, $1.kind) },
    imports: imports.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
)
FileHandle.standardOutput.write(try encoder.encode(output))

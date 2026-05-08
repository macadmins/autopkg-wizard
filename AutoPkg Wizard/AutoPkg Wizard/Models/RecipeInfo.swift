import Foundation

/// Represents a parsed value from `autopkg info` input values.
/// Supports nested dictionaries, lists, strings, booleans, and numbers.
enum InputValue: Equatable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case float(Double)
    case dict([(key: String, value: InputValue)])
    case list([InputValue])
    case none

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "True" : "False"
        case .integer(let i): return "\(i)"
        case .float(let d): return "\(d)"
        case .none: return "None"
        case .dict(let entries):
            let items = entries.map { "\($0.key): \($0.value.displayString)" }
            return "{\(items.joined(separator: ", "))}"
        case .list(let items):
            return "[\(items.map { $0.displayString }.joined(separator: ", "))]"
        }
    }

    /// Whether this value contains nested structure worth expanding.
    var isComplex: Bool {
        switch self {
        case .dict(let entries): return !entries.isEmpty
        case .list(let items): return !items.isEmpty
        default: return false
        }
    }

    static func == (lhs: InputValue, rhs: InputValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.float(let a), .float(let b)): return a == b
        case (.none, .none): return true
        case (.list(let a), .list(let b)): return a == b
        case (.dict(let a), .dict(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    // MARK: - Plist / YAML round-trip

    /// Create an `InputValue` from a Foundation object (plist or YAML decoded).
    static func from(any value: Any) -> InputValue {
        // Check Bool before numeric types since NSNumber bridges both
        if let nsNumber = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(nsNumber) {
                return .bool(nsNumber.boolValue)
            }
        }
        switch value {
        case let s as String:
            return .string(s)
        case let i as Int:
            return .integer(i)
        case let d as Double:
            if d == d.rounded(.towardZero) && !d.isNaN && !d.isInfinite && abs(d) < Double(Int.max) {
                return .integer(Int(d))
            }
            return .float(d)
        case let arr as [Any]:
            return .list(arr.map { from(any: $0) })
        case let dict as [String: Any]:
            let entries = dict.sorted { $0.key < $1.key }
                .map { (key: $0.key, value: from(any: $0.value)) }
            return .dict(entries)
        default:
            return .string(String(describing: value))
        }
    }

    /// Convert back to a Foundation object suitable for plist/YAML serialization.
    func toAny() -> Any {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b
        case .integer(let i): return i
        case .float(let d): return d
        case .none: return ""
        case .list(let items): return items.map { $0.toAny() }
        case .dict(let entries):
            var dict: [String: Any] = [:]
            for entry in entries { dict[entry.key] = entry.value.toAny() }
            return dict
        }
    }
}

/// Parsed representation of `autopkg info <recipe>` output.
struct RecipeInfo {
    let description: String
    let identifier: String
    let munkiImportRecipe: String
    let hasCheckPhase: String
    let buildsPackage: String
    let recipeFilePath: String
    let parentRecipes: [String]
    let inputValues: [(key: String, value: InputValue)]

    /// Parse the output of `autopkg info <recipe>`.
    static func parse(from output: String) -> RecipeInfo {
        let lines = output.components(separatedBy: "\n")

        var description = ""
        var identifier = ""
        var munkiImport = ""
        var checkPhase = ""
        var buildsPackage = ""
        var filePath = ""
        var parentRecipes: [String] = []
        var inputValues: [(key: String, value: InputValue)] = []

        var inInputValues = false
        var currentKey: String?
        var currentValue: String = ""

        // Collect all input value lines, then parse as a Python dict
        var inputBlock = ""

        for line in lines {
            if line.hasPrefix("Input values:") {
                inInputValues = true
                continue
            }

            if inInputValues {
                inputBlock += line + "\n"
            } else {
                if let (key, value) = parseHeaderLine(line) {
                    saveHeaderField(
                        key: currentKey, value: currentValue,
                        description: &description, identifier: &identifier,
                        munkiImport: &munkiImport, checkPhase: &checkPhase,
                        buildsPackage: &buildsPackage, filePath: &filePath,
                        parentRecipes: &parentRecipes
                    )
                    currentKey = key
                    currentValue = value
                } else if currentKey != nil {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        currentValue += "\n" + trimmed
                    }
                }
            }
        }
        saveHeaderField(
            key: currentKey, value: currentValue,
            description: &description, identifier: &identifier,
            munkiImport: &munkiImport, checkPhase: &checkPhase,
            buildsPackage: &buildsPackage, filePath: &filePath,
            parentRecipes: &parentRecipes
        )

        // Parse the input block as a Python dict body
        inputValues = parseInputBlock(inputBlock)

        return RecipeInfo(
            description: description,
            identifier: identifier,
            munkiImportRecipe: munkiImport,
            hasCheckPhase: checkPhase,
            buildsPackage: buildsPackage,
            recipeFilePath: filePath,
            parentRecipes: parentRecipes,
            inputValues: inputValues
        )
    }

    // MARK: - Private Helpers

    private static func parseHeaderLine(_ line: String) -> (key: String, value: String)? {
        guard let colonRange = line.range(of: ":") else { return nil }
        let key = String(line[line.startIndex..<colonRange.lowerBound])
        guard !key.isEmpty, !key.hasPrefix(" "), !key.hasPrefix("'") else { return nil }
        let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func saveHeaderField(
        key: String?, value: String,
        description: inout String, identifier: inout String,
        munkiImport: inout String, checkPhase: inout String,
        buildsPackage: inout String, filePath: inout String,
        parentRecipes: inout [String]
    ) {
        guard let key else { return }
        switch key {
        case "Description": description = value
        case "Identifier": identifier = value
        case "Munki import recipe": munkiImport = value
        case "Has check phase": checkPhase = value
        case "Builds package": buildsPackage = value
        case "Recipe file path": filePath = value
        case "Parent recipe(s)":
            parentRecipes = value.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        default: break
        }
    }

    /// Parse the indented input values block as top-level Python dict entries.
    private static func parseInputBlock(_ block: String) -> [(key: String, value: InputValue)] {
        // Wrap in braces to make it a valid Python dict literal, then parse
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let dictString = "{\(trimmed)}"
        var index = dictString.startIndex
        if let parsed = parsePythonValue(dictString, index: &index) {
            if case .dict(let entries) = parsed {
                return entries
            }
        }
        // Fallback: simple line-by-line parsing
        return parseInputBlockFallback(block)
    }

    /// Fallback parser for simple key-value input lines.
    private static func parseInputBlockFallback(_ block: String) -> [(key: String, value: InputValue)] {
        var result: [(key: String, value: InputValue)] = []
        for line in block.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("'") else {
                if !trimmed.isEmpty, !result.isEmpty {
                    if case .string(let s) = result[result.count - 1].value {
                        result[result.count - 1].value = .string(s + "\n" + trimmed)
                    }
                }
                continue
            }
            guard let keyEnd = trimmed.range(of: "': ") ?? trimmed.range(of: "':") else { continue }
            let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<keyEnd.lowerBound])
            var value = String(trimmed[keyEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(",") { value = String(value.dropLast()).trimmingCharacters(in: .whitespaces) }
            if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result.append((key: key, value: .string(value)))
        }
        return result
    }

    // MARK: - Python Literal Parser

    /// Parse a Python literal value (string, int, float, bool, None, dict, list).
    private static func parsePythonValue(_ s: String, index: inout String.Index) -> InputValue? {
        skipWhitespace(s, index: &index)
        guard index < s.endIndex else { return nil }

        let ch = s[index]
        if ch == "{" { return parsePythonDict(s, index: &index) }
        if ch == "[" { return parsePythonList(s, index: &index) }
        if ch == "'" || ch == "\"" {
            // Handle Python implicit string concatenation: 'foo ' 'bar' => 'foo bar'
            guard case .string(var result) = parsePythonString(s, index: &index) else { return nil }
            while true {
                skipWhitespace(s, index: &index)
                guard index < s.endIndex, s[index] == "'" || s[index] == "\"" else { break }
                guard case .string(let next) = parsePythonString(s, index: &index) else { break }
                result += next
            }
            return .string(result)
        }
        // True, False, None
        if s[index...].hasPrefix("True") {
            index = s.index(index, offsetBy: 4)
            return .bool(true)
        }
        if s[index...].hasPrefix("False") {
            index = s.index(index, offsetBy: 5)
            return .bool(false)
        }
        if s[index...].hasPrefix("None") {
            index = s.index(index, offsetBy: 4)
            return .none
        }
        // Number
        return parsePythonNumber(s, index: &index)
    }

    private static func skipWhitespace(_ s: String, index: inout String.Index) {
        while index < s.endIndex && (s[index] == " " || s[index] == "\t" || s[index] == "\n" || s[index] == "\r") {
            index = s.index(after: index)
        }
    }

    private static func parsePythonString(_ s: String, index: inout String.Index) -> InputValue? {
        let quote = s[index]
        index = s.index(after: index)
        var result = ""
        while index < s.endIndex {
            let ch = s[index]
            if ch == "\\" && s.index(after: index) < s.endIndex {
                index = s.index(after: index)
                let escaped = s[index]
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "'": result.append("'")
                case "\"": result.append("\"")
                default:
                    result.append("\\")
                    result.append(escaped)
                }
                index = s.index(after: index)
            } else if ch == quote {
                index = s.index(after: index)
                return .string(result)
            } else {
                result.append(ch)
                index = s.index(after: index)
            }
        }
        return .string(result)
    }

    private static func parsePythonNumber(_ s: String, index: inout String.Index) -> InputValue? {
        let start = index
        if index < s.endIndex && (s[index] == "-" || s[index] == "+") {
            index = s.index(after: index)
        }
        var hasDigits = false
        var hasDot = false
        while index < s.endIndex {
            if s[index].isNumber {
                hasDigits = true
                index = s.index(after: index)
            } else if s[index] == "." && !hasDot {
                hasDot = true
                index = s.index(after: index)
            } else {
                break
            }
        }
        guard hasDigits else { index = start; return nil }
        let numStr = String(s[start..<index])
        if hasDot, let d = Double(numStr) { return .float(d) }
        if let i = Int(numStr) { return .integer(i) }
        return nil
    }

    private static func parsePythonDict(_ s: String, index: inout String.Index) -> InputValue? {
        guard index < s.endIndex, s[index] == "{" else { return nil }
        index = s.index(after: index)
        var entries: [(key: String, value: InputValue)] = []
        while true {
            skipWhitespace(s, index: &index)
            guard index < s.endIndex else { break }
            if s[index] == "}" { index = s.index(after: index); break }
            // Parse key
            guard let keyValue = parsePythonValue(s, index: &index) else { break }
            let key: String
            switch keyValue {
            case .string(let k): key = k
            default: key = keyValue.displayString
            }
            skipWhitespace(s, index: &index)
            // Expect ':'
            guard index < s.endIndex, s[index] == ":" else { break }
            index = s.index(after: index)
            // Parse value
            guard let value = parsePythonValue(s, index: &index) else { break }
            entries.append((key: key, value: value))
            skipWhitespace(s, index: &index)
            // Optional comma
            if index < s.endIndex && s[index] == "," {
                index = s.index(after: index)
            }
        }
        return .dict(entries)
    }

    private static func parsePythonList(_ s: String, index: inout String.Index) -> InputValue? {
        guard index < s.endIndex, s[index] == "[" else { return nil }
        index = s.index(after: index)
        var items: [InputValue] = []
        while true {
            skipWhitespace(s, index: &index)
            guard index < s.endIndex else { break }
            if s[index] == "]" { index = s.index(after: index); break }
            guard let value = parsePythonValue(s, index: &index) else { break }
            items.append(value)
            skipWhitespace(s, index: &index)
            if index < s.endIndex && s[index] == "," {
                index = s.index(after: index)
            }
        }
        return .list(items)
    }
}

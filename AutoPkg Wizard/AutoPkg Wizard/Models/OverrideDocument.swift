import Foundation
import Yams

/// Represents a parsed recipe override file, exposing its sections as structured `InputValue` entries.
/// Supports round-tripping back to plist or YAML.
struct OverrideDocument {
    /// Top-level metadata keys (Identifier, Description, ParentRecipe, etc.)
    var metadata: [(key: String, value: InputValue)]
    /// The `Input` dictionary entries — the primary editable section.
    var input: [(key: String, value: InputValue)]
    /// Any other top-level keys not in metadata or Input (e.g. Process, MinimumVersion).
    var other: [(key: String, value: InputValue)]

    /// The file format this was parsed from.
    let fileType: OverrideFileType

    /// Well-known top-level metadata keys (order matters for display).
    private static let metadataKeys: Set<String> = [
        "Identifier", "Description", "ParentRecipe",
        "ParentRecipeTrustInfo", "MinimumVersion",
    ]

    // MARK: - Parsing

    /// Parse an override file from its raw string content.
    static func parse(content: String, fileType: OverrideFileType) -> OverrideDocument? {
        guard let dict = parseToDictionary(content: content, fileType: fileType) else {
            return nil
        }
        return from(dictionary: dict, fileType: fileType)
    }

    /// Parse from a `[String: Any]` dictionary.
    static func from(dictionary dict: [String: Any], fileType: OverrideFileType) -> OverrideDocument {
        var metadata: [(key: String, value: InputValue)] = []
        var input: [(key: String, value: InputValue)] = []
        var other: [(key: String, value: InputValue)] = []

        // Preserve a stable key ordering: metadata keys first in a known order, then alphabetical
        let sortedKeys = dict.keys.sorted { a, b in
            let aIsMeta = metadataKeys.contains(a)
            let bIsMeta = metadataKeys.contains(b)
            if aIsMeta && !bIsMeta { return true }
            if !aIsMeta && bIsMeta { return false }
            return a < b
        }

        for key in sortedKeys {
            guard let value = dict[key] else { continue }
            let iv = InputValue.from(any: value)

            if key == "Input" {
                // Flatten the Input dict into entries
                if let inputDict = value as? [String: Any] {
                    input = inputDict.sorted { $0.key < $1.key }
                        .map { (key: $0.key, value: InputValue.from(any: $0.value)) }
                }
            } else if metadataKeys.contains(key) {
                metadata.append((key: key, value: iv))
            } else {
                other.append((key: key, value: iv))
            }
        }

        return OverrideDocument(metadata: metadata, input: input, other: other, fileType: fileType)
    }

    // MARK: - Serialization

    /// Serialize back to a string in the original format.
    func serialize() -> String? {
        let dict = toDictionary()

        switch fileType {
        case .plist:
            return serializePlist(dict)
        case .yaml:
            return serializeYAML(dict)
        case .unknown:
            return serializeYAML(dict)
        }
    }

    /// Build the full `[String: Any]` dictionary.
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for entry in metadata {
            dict[entry.key] = entry.value.toAny()
        }
        // Rebuild the Input dict
        var inputDict: [String: Any] = [:]
        for entry in input {
            inputDict[entry.key] = entry.value.toAny()
        }
        if !inputDict.isEmpty {
            dict["Input"] = inputDict
        }
        for entry in other {
            dict[entry.key] = entry.value.toAny()
        }
        return dict
    }

    // MARK: - Private

    private static func parseToDictionary(content: String, fileType: OverrideFileType) -> [String: Any]? {
        switch fileType {
        case .plist:
            guard let data = content.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = plist as? [String: Any] else { return nil }
            return dict
        case .yaml, .unknown:
            guard let node = try? Yams.compose(yaml: content),
                  let mapping = node.mapping else { return nil }
            return yamlMappingToDict(mapping)
        }
    }

    private static func yamlNodeToAny(_ node: Yams.Node) -> Any {
        switch node {
        case .scalar(let scalar):
            // Try to preserve types
            if let boolVal = Bool(scalar.string.lowercased()),
               (scalar.string == "true" || scalar.string == "false" ||
                scalar.string == "True" || scalar.string == "False") {
                return boolVal
            }
            if let intVal = Int(scalar.string) { return intVal }
            if let doubleVal = Double(scalar.string), scalar.string.contains(".") { return doubleVal }
            return scalar.string
        case .sequence(let sequence):
            return sequence.map { yamlNodeToAny($0) }
        case .mapping(let mapping):
            return yamlMappingToDict(mapping)
        @unknown default:
            return String(describing: node)
        }
    }

    private static func yamlMappingToDict(_ mapping: Yams.Node.Mapping) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in mapping {
            let keyStr = key.scalar?.string ?? String(describing: key)
            dict[keyStr] = yamlNodeToAny(value)
        }
        return dict
    }

    private func serializePlist(_ dict: [String: Any]) -> String? {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func serializeYAML(_ dict: [String: Any]) -> String? {
        // Use Yams to serialize, preserving a nice key order
        return try? Yams.dump(object: dict, allowUnicode: true)
    }
}

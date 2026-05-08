import SwiftUI
import Yams

@MainActor
@Observable
final class OverridesViewModel {
    private let cli = AutoPkgCLI.shared

    var overrides: [AutoPkgOverride] = []
    var selectedOverride: AutoPkgOverride?
    var selectedOverrideContents: String = ""
    var trustStatus: [String: TrustState] = [:]

    var isLoading = false
    var showError = false
    var errorMessage: String?
    var statusMessage: String?

    /// Validation error shown inline (not as an alert)
    var validationError: String?

    /// Parsed structured document for the selected override
    var document: OverrideDocument?

    /// Whether to show raw editor instead of structured view
    var showRawEditor = false

    enum TrustState: Sendable {
        case unknown
        case verifying
        case verified
        case failed(String)

        var icon: String {
            switch self {
            case .unknown: "questionmark.circle"
            case .verifying: "clock"
            case .verified: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: .secondary
            case .verifying: .blue
            case .verified: .green
            case .failed: .orange
            }
        }
    }

    func loadOverrides() {
        overrides = AutoPkgOverride.listOverrides(in: cli.overridesDirectory)
    }

    func selectOverride(_ override: AutoPkgOverride) {
        selectedOverride = override
        validationError = nil
        statusMessage = nil
        showRawEditor = false
        do {
            selectedOverrideContents = try override.contents()
            let fileType = OverrideFileType.detect(
                fileName: override.fileName,
                content: selectedOverrideContents
            )
            document = OverrideDocument.parse(content: selectedOverrideContents, fileType: fileType)
        } catch {
            selectedOverrideContents = "Error reading file: \(error.localizedDescription)"
            document = nil
        }
    }

    /// Update a single input key in the structured document.
    func updateInputValue(key: String, value: InputValue) {
        guard var doc = document else { return }
        if let idx = doc.input.firstIndex(where: { $0.key == key }) {
            doc.input[idx].value = value
        }
        document = doc
    }

    /// Update a metadata key in the structured document.
    func updateMetadataValue(key: String, value: InputValue) {
        guard var doc = document else { return }
        if let idx = doc.metadata.firstIndex(where: { $0.key == key }) {
            doc.metadata[idx].value = value
        }
        document = doc
    }

    /// Add a new input key.
    func addInputKey(_ key: String, value: InputValue) {
        guard var doc = document else { return }
        guard !key.isEmpty, !doc.input.contains(where: { $0.key == key }) else { return }
        doc.input.append((key: key, value: value))
        document = doc
    }

    /// Remove an input key by name.
    func removeInputKey(_ key: String) {
        guard var doc = document else { return }
        doc.input.removeAll { $0.key == key }
        document = doc
    }

    /// Replace the entire input array (used for reordering after add/remove within nested structures).
    func replaceInput(_ input: [(key: String, value: InputValue)]) {
        guard var doc = document else { return }
        doc.input = input
        document = doc
    }

    func saveOverrideContents() {
        guard let override = selectedOverride else { return }

        let contentToSave: String

        if showRawEditor {
            // Save from the raw text editor
            let fileType = OverrideFileType.detect(fileName: override.fileName, content: selectedOverrideContents)
            if let error = validateContent(selectedOverrideContents, fileType: fileType) {
                validationError = error
                return
            }
            contentToSave = selectedOverrideContents
        } else if let doc = document, let serialized = doc.serialize() {
            contentToSave = serialized
        } else {
            validationError = "Failed to serialize override document."
            return
        }

        validationError = nil
        do {
            try contentToSave.write(toFile: override.filePath, atomically: true, encoding: .utf8)
            selectedOverrideContents = contentToSave
            statusMessage = "Override saved."
            // Clear status after a delay
            Task {
                try? await Task.sleep(for: .seconds(3))
                if statusMessage == "Override saved." {
                    statusMessage = nil
                }
            }
        } catch {
            errorMessage = "Failed to save override: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Sync from raw editor back to structured document (when switching modes).
    func syncFromRawEditor() {
        guard let override = selectedOverride else { return }
        let fileType = OverrideFileType.detect(fileName: override.fileName, content: selectedOverrideContents)
        document = OverrideDocument.parse(content: selectedOverrideContents, fileType: fileType)
    }

    /// Sync from structured document to raw editor text.
    func syncToRawEditor() {
        if let doc = document, let serialized = doc.serialize() {
            selectedOverrideContents = serialized
        }
    }

    /// Validate plist or yaml content. Returns an error message if invalid, nil if valid.
    private func validateContent(_ content: String, fileType: OverrideFileType) -> String? {
        switch fileType {
        case .plist:
            guard let data = content.data(using: .utf8) else {
                return "Could not encode content as UTF-8."
            }
            do {
                _ = try PropertyListSerialization.propertyList(from: data, format: nil)
                return nil
            } catch {
                return "Invalid plist: \(error.localizedDescription)"
            }

        case .yaml:
            do {
                _ = try Yams.compose(yaml: content)
                return nil
            } catch {
                return "Invalid YAML: \(error.localizedDescription)"
            }

        case .unknown:
            return nil // Can't validate unknown formats
        }
    }

    func verifyTrust(for override: AutoPkgOverride) async {
        let name = override.recipeName
        trustStatus[override.id] = .verifying
        do {
            _ = try await cli.verifyTrustInfo(name)
            trustStatus[override.id] = .verified
        } catch let error as AutoPkgError {
            if case .commandFailed(_, _, let stderr) = error {
                trustStatus[override.id] = .failed(stderr)
            } else {
                trustStatus[override.id] = .failed(error.localizedDescription)
            }
        } catch {
            trustStatus[override.id] = .failed(error.localizedDescription)
        }
    }

    func updateTrust(for override: AutoPkgOverride) async {
        let name = override.recipeName
        do {
            _ = try await cli.updateTrustInfo(name)
            trustStatus[override.id] = .verified
            statusMessage = "Trust info updated for \(name)"
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func deleteOverride(_ override: AutoPkgOverride) {
        do {
            try FileManager.default.removeItem(atPath: override.filePath)
            if selectedOverride?.id == override.id {
                selectedOverride = nil
                selectedOverrideContents = ""
            }
            loadOverrides()
            NotificationCenter.default.post(name: .overridesDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

extension Notification.Name {
    static let overridesDidChange = Notification.Name("overridesDidChange")
}

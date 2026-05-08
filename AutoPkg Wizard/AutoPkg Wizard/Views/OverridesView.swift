import SwiftUI

struct OverridesView: View {
    @State private var viewModel = OverridesViewModel()
    @State private var isEditing = false
    @State private var selectedOverrides: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            overridesList
                .frame(minWidth: 250, maxHeight: .infinity, alignment: .top)
            detailPane
                .frame(minWidth: 300, maxHeight: .infinity)
        }
        .navigationTitle("Overrides")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        selectedOverrides.removeAll()
                    }
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .disabled(viewModel.overrides.isEmpty)
                    .help("Select overrides to remove")
                }

                Button {
                    viewModel.loadOverrides()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isEditing)
                .help("Refresh override list")
            }
        }
        .onAppear {
            viewModel.loadOverrides()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overridesDidChange)) { _ in
            viewModel.loadOverrides()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Override List

    private var overridesList: some View {
        VStack(spacing: 0) {
            if viewModel.overrides.isEmpty {
                ContentUnavailableView(
                    "No Overrides",
                    systemImage: "doc.on.doc",
                    description: Text("No recipe overrides found in\n\(AutoPkgCLI.shared.overridesDirectory)")
                )
            } else {
                List(viewModel.overrides, selection: Binding(
                    get: { viewModel.selectedOverride },
                    set: { override in
                        if !isEditing, let override {
                            viewModel.selectOverride(override)
                        }
                    }
                )) { override in
                    HStack {
                        if isEditing {
                            Button {
                                toggleSelection(override)
                            } label: {
                                Image(systemName: selectedOverrides.contains(override.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedOverrides.contains(override.id) ? .blue : .secondary)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                        }
                        OverrideRow(override: override, trustState: viewModel.trustStatus[override.id] ?? .unknown)
                        Spacer()
                        if !isEditing {
                            Button {
                                NSWorkspace.shared.selectFile(override.filePath, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(isEditing ? TapGesture().onEnded { toggleSelection(override) } : nil)
                    .contextMenu {
                        if !isEditing {
                            Button("Verify Trust Info") {
                                Task { await viewModel.verifyTrust(for: override) }
                            }
                            Button("Update Trust Info") {
                                Task { await viewModel.updateTrust(for: override) }
                            }
                            Divider()
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(override.filePath, inFileViewerRootedAtPath: "")
                            }
                            Divider()
                            Button("Delete Override", role: .destructive) {
                                viewModel.deleteOverride(override)
                            }
                        }
                    }
                    .tag(override)
                }
                .listStyle(.plain)
                .frame(maxHeight: .infinity, alignment: .top)

                if isEditing {
                    HStack {
                        Button(role: .destructive) {
                            deleteSelectedOverrides()
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                        .disabled(selectedOverrides.isEmpty)
                        Spacer()
                        Text("\(selectedOverrides.count) selected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        Group {
            if let override = viewModel.selectedOverride {
                VStack(alignment: .leading, spacing: 8) {
                    Text(override.fileName)
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    HStack {
                        let trustState = viewModel.trustStatus[override.id] ?? .unknown
                        trustBadge(trustState)
                        Spacer()

                        Picker("", selection: $viewModel.showRawEditor) {
                            Label("Structured", systemImage: "list.bullet").tag(false)
                            Label("Raw", systemImage: "doc.plaintext").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                        .onChange(of: viewModel.showRawEditor) { _, isRaw in
                            if isRaw {
                                viewModel.syncToRawEditor()
                            } else {
                                viewModel.syncFromRawEditor()
                            }
                        }

                        Button("Verify") {
                            Task { await viewModel.verifyTrust(for: override) }
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        Button("Update Trust") {
                            Task { await viewModel.updateTrust(for: override) }
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        Button("Save") {
                            viewModel.saveOverrideContents()
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .keyboardShortcut("s", modifiers: .command)
                    }
                    .padding(.horizontal)

                    if let status = viewModel.statusMessage {
                        Text(status).font(.caption).foregroundStyle(.green).padding(.horizontal)
                    }

                    if let validationError = viewModel.validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(validationError).font(.caption).foregroundStyle(.red)
                        }
                        .padding(.horizontal)
                    }

                    Divider()

                    if viewModel.showRawEditor {
                        SyntaxHighlightEditor(
                            text: $viewModel.selectedOverrideContents,
                            language: OverrideFileType.detect(
                                fileName: override.fileName,
                                content: viewModel.selectedOverrideContents
                            ).highlightrLanguage,
                            themeName: SyntaxThemeManager.shared.currentTheme(
                                for: colorScheme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
                            )
                        )
                        .id(override.id)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    } else if let doc = viewModel.document {
                        OverrideStructuredView(viewModel: viewModel, document: doc)
                            .id(override.id)
                            .padding(.bottom, 8)
                    } else {
                        ContentUnavailableView(
                            "Could Not Parse Override",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Switch to Raw mode to edit this file directly.")
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select an Override",
                    systemImage: "doc.text",
                    description: Text("Select an override from the list to view its contents.")
                )
            }
        }
    }

    @ViewBuilder
    private func trustBadge(_ state: OverridesViewModel.TrustState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon).foregroundStyle(state.color)
            switch state {
            case .unknown:
                Text("Not Checked").font(.caption).foregroundStyle(.secondary)
            case .verifying:
                Text("Verifying…").font(.caption).foregroundStyle(.blue)
            case .verified:
                Text("Verified").font(.caption).foregroundStyle(.green)
            case .failed(let message):
                Text("Failed").font(.caption).foregroundStyle(.orange).help(message)
            }
        }
    }

    private func toggleSelection(_ override: AutoPkgOverride) {
        if selectedOverrides.contains(override.id) {
            selectedOverrides.remove(override.id)
        } else {
            selectedOverrides.insert(override.id)
        }
    }

    private func deleteSelectedOverrides() {
        let toDelete = viewModel.overrides.filter { selectedOverrides.contains($0.id) }
        for override in toDelete { viewModel.deleteOverride(override) }
        selectedOverrides.removeAll()
        isEditing = false
    }
}

// MARK: - Override Row

struct OverrideRow: View {
    let override: AutoPkgOverride
    let trustState: OverridesViewModel.TrustState

    var body: some View {
        HStack {
            Image(systemName: "doc.text").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(override.recipeName).font(.body).lineLimit(1)
                Text(override.fileName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if case .unknown = trustState {
                // Don't show anything for unchecked trust
            } else {
                Image(systemName: trustState.icon)
                    .foregroundStyle(trustState.color)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Structured Override View

struct OverrideStructuredView: View {
    @Bindable var viewModel: OverridesViewModel
    let document: OverrideDocument

    @State private var showAddKeySheet = false
    @State private var newKeyName = ""
    @State private var newKeyType = NewKeyType.string

    enum NewKeyType: String, CaseIterable {
        case string = "String"
        case integer = "Integer"
        case bool = "Boolean"
        case array = "Array"
        case dictionary = "Dictionary"

        var defaultValue: InputValue {
            switch self {
            case .string: return .string("")
            case .integer: return .integer(0)
            case .bool: return .bool(false)
            case .array: return .list([])
            case .dictionary: return .dict([])
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !document.metadata.isEmpty {
                    structuredSection("Metadata") {
                        ForEach(Array(document.metadata.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { Divider() }
                            EditableInputValueRow(
                                label: entry.key,
                                value: entry.value,
                                isReadOnly: entry.key == "ParentRecipeTrustInfo",
                                onUpdate: { newValue in
                                    viewModel.updateMetadataValue(key: entry.key, value: newValue)
                                }
                            )
                        }
                    }
                }

                if !document.input.isEmpty || true {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Input").font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Button {
                                newKeyName = ""
                                newKeyType = .string
                                showAddKeySheet = true
                            } label: {
                                Label("Add Key", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        structuredSection(nil) {
                            if document.input.isEmpty {
                                Text("No input keys").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(document.input.enumerated()), id: \.offset) { index, entry in
                                    if index > 0 { Divider() }
                                    HStack(alignment: .top) {
                                        EditableInputValueRow(
                                            label: entry.key,
                                            value: entry.value,
                                            onUpdate: { newValue in
                                                viewModel.updateInputValue(key: entry.key, value: newValue)
                                            },
                                            onDelete: {
                                                viewModel.removeInputKey(entry.key)
                                            }
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }

                if !document.other.isEmpty {
                    structuredSection("Other") {
                        ForEach(Array(document.other.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { Divider() }
                            EditableInputValueRow(
                                label: entry.key,
                                value: entry.value,
                                isReadOnly: true
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddKeySheet) {
            addKeySheet
        }
    }

    private var addKeySheet: some View {
        VStack(spacing: 12) {
            Text("Add Input Key").font(.headline)
            TextField("Key name", text: $newKeyName)
                .textFieldStyle(.roundedBorder)
            Picker("Type", selection: $newKeyType) {
                ForEach(NewKeyType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if document.input.contains(where: { $0.key == newKeyName }) && !newKeyName.isEmpty {
                Text("A key with this name already exists.")
                    .font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { showAddKeySheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    viewModel.addInputKey(newKeyName, value: newKeyType.defaultValue)
                    showAddKeySheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newKeyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || document.input.contains(where: { $0.key == newKeyName }))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func structuredSection<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title).font(.subheadline).fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Editable Input Value Row (recursive)

struct EditableInputValueRow: View {
    let label: String
    let value: InputValue
    var isReadOnly: Bool = false
    var onUpdate: ((InputValue) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showAddDictKey = false
    @State private var newDictKeyName = ""

    var body: some View {
        switch value {
        case .dict(let entries):
            dictRow(entries: entries)
        case .list(let items):
            listRow(items: items)
        case .bool(let b):
            boolRow(b)
        case .string(let s) where s.contains("\n"):
            multilineStringRow(s)
        default:
            defaultRow()
        }
    }

    // MARK: - Dict

    @ViewBuilder
    private func dictRow(entries: [(key: String, value: InputValue)]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { Divider() }
                    EditableInputValueRow(
                        label: entry.key,
                        value: entry.value,
                        isReadOnly: isReadOnly,
                        onUpdate: { newValue in
                            var updated = entries
                            updated[index].value = newValue
                            onUpdate?(.dict(updated))
                        },
                        onDelete: isReadOnly ? nil : {
                            var updated = entries
                            updated.remove(at: index)
                            onUpdate?(.dict(updated))
                        }
                    )
                }
                if !isReadOnly {
                    addDictKeyRow(entries: entries)
                }
            }
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("(\(entries.count) key\(entries.count == 1 ? "" : "s"))")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                deleteButton()
            }
        }
    }

    @ViewBuilder
    private func addDictKeyRow(entries: [(key: String, value: InputValue)]) -> some View {
        Divider()
        if showAddDictKey {
            HStack(spacing: 4) {
                TextField("Key name", text: $newDictKeyName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 200)
                Button {
                    guard !newDictKeyName.isEmpty,
                          !entries.contains(where: { $0.key == newDictKeyName }) else { return }
                    var updated = entries
                    updated.append((key: newDictKeyName, value: .string("")))
                    onUpdate?(.dict(updated))
                    newDictKeyName = ""
                    showAddDictKey = false
                } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(newDictKeyName.isEmpty || entries.contains(where: { $0.key == newDictKeyName }))
                Button {
                    newDictKeyName = ""
                    showAddDictKey = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                showAddDictKey = true
            } label: {
                Label("Add Key", systemImage: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - List

    @ViewBuilder
    private func listRow(items: [InputValue]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    if item.isComplex {
                        EditableInputValueRow(
                            label: "[\(index)]",
                            value: item,
                            isReadOnly: isReadOnly,
                            onUpdate: { newValue in
                                var updated = items
                                updated[index] = newValue
                                onUpdate?(.list(updated))
                            },
                            onDelete: isReadOnly ? nil : {
                                var updated = items
                                updated.remove(at: index)
                                onUpdate?(.list(updated))
                            }
                        )
                    } else {
                        HStack(spacing: 4) {
                            editableLeaf(item, at: index, inList: items)
                            if !isReadOnly {
                                Button {
                                    var updated = items
                                    updated.remove(at: index)
                                    onUpdate?(.list(updated))
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.7))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Remove item")
                            }
                        }
                    }
                }
                if !isReadOnly {
                    addListItemRow(items: items)
                }
            }
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("(\(items.count) item\(items.count == 1 ? "" : "s"))")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                deleteButton()
            }
        }
    }

    @ViewBuilder
    private func addListItemRow(items: [InputValue]) -> some View {
        Divider()
        Menu {
            Button("String") {
                var updated = items
                updated.append(.string(""))
                onUpdate?(.list(updated))
            }
            Button("Dictionary") {
                var updated = items
                updated.append(.dict([]))
                onUpdate?(.list(updated))
            }
        } label: {
            Label("Add Item", systemImage: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Bool

    @ViewBuilder
    private func boolRow(_ b: Bool) -> some View {
        if isReadOnly {
            readOnlyRow(label: label, text: b ? "True" : "False")
        } else {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { b },
                    set: { onUpdate?(.bool($0)) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                deleteButton()
            }
        }
    }

    // MARK: - Multi-line String

    @ViewBuilder
    private func multilineStringRow(_ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                deleteButton()
            }
            if isReadOnly {
                ScrollView {
                    Text(s)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .frame(maxHeight: min(CGFloat(s.components(separatedBy: "\n").count + 1) * 14, 200))
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                MultilineTextField(initialText: s, onChange: { newText in
                    onUpdate?(.string(newText))
                })
            }
        }
    }

    // MARK: - Default (simple value)

    @ViewBuilder
    private func defaultRow() -> some View {
        if isReadOnly {
            readOnlyRow(label: label, text: value.displayString)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    deleteButton()
                }
                TextField("", text: Binding(
                    get: { value.displayString },
                    set: { newText in
                        onUpdate?(parseEditedValue(newText, original: value))
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func deleteButton() -> some View {
        if let onDelete, !isReadOnly {
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Remove \(label)")
        }
    }

    @ViewBuilder
    private func editableLeaf(_ item: InputValue, at index: Int, inList items: [InputValue]) -> some View {
        if isReadOnly {
            Text(item.displayString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        } else {
            TextField("", text: Binding(
                get: { item.displayString },
                set: { newText in
                    var updated = items
                    updated[index] = parseEditedValue(newText, original: item)
                    onUpdate?(.list(updated))
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder
    private func readOnlyRow(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "—" : text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func parseEditedValue(_ text: String, original: InputValue) -> InputValue {
        switch original {
        case .integer:
            if let i = Int(text) { return .integer(i) }
            return .string(text)
        case .float:
            if let d = Double(text) { return .float(d) }
            return .string(text)
        case .bool:
            let lower = text.lowercased()
            if lower == "true" || lower == "yes" || lower == "1" { return .bool(true) }
            if lower == "false" || lower == "no" || lower == "0" { return .bool(false) }
            return .string(text)
        default:
            return .string(text)
        }
    }
}

// MARK: - Multi-line Text Editor

struct MultilineTextField: View {
    let initialText: String
    let onChange: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.caption, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: max(60, lineHeight), maxHeight: 300)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .onAppear { text = initialText }
            .onChange(of: initialText) { _, newValue in text = newValue }
            .onChange(of: text) { _, newValue in onChange(newValue) }
    }

    /// Estimate height based on line count.
    private var lineHeight: CGFloat {
        let lineCount = initialText.components(separatedBy: "\n").count
        return CGFloat(min(lineCount + 1, 20)) * 14
    }
}

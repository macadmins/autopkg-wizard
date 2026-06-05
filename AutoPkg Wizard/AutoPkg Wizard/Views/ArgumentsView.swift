import SwiftUI
import UniformTypeIdentifiers

struct ArgumentsView: View {
    @State private var viewModel = ArgumentsViewModel()

    var body: some View {
        Form {
            // MARK: - Verbosity
            Section {
                Picker("Verbosity Level", selection: Binding(
                    get: { viewModel.config.verbosity },
                    set: { viewModel.setVerbosity($0) }
                )) {
                    Text("Quiet (no verbose output)").tag(0)
                    Text("Normal (-v)").tag(1)
                    Text("Verbose (-vv)").tag(2)
                    Text("Very Verbose (-vvv)").tag(3)
                    Text("Debug (-vvvv)").tag(4)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Verbosity")
            } footer: {
                Text("Controls the amount of output from autopkg. Higher levels produce more diagnostic information.")
            }

            // MARK: - Pre-Processors
            Section {
                preProcessorsList
                AddItemField(
                    label: "Processor name (e.g. com.example.MyPreProcessor)",
                    buttonLabel: "Add Pre-Processor"
                ) { name in viewModel.addPreProcessor(name) }
            } header: {
                HStack {
                    Text("Pre-Processors")
                    Spacer()
                    Text("\(viewModel.config.preProcessors.count)").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Pre-processors run before each recipe. Each entry becomes a --pre argument.")
            }

            // MARK: - Post-Processors
            Section {
                postProcessorsList
                AddItemField(
                    label: "Processor name (e.g. com.example.MyPostProcessor)",
                    buttonLabel: "Add Post-Processor"
                ) { name in viewModel.addPostProcessor(name) }
            } header: {
                HStack {
                    Text("Post-Processors")
                    Spacer()
                    Text("\(viewModel.config.postProcessors.count)").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Post-processors run after each recipe. Each entry becomes a --post argument.")
            }

            // MARK: - Key-Value Pairs
            Section {
                keyValuePairsList
                AddKeyValueField { key, value in viewModel.addKeyValuePair(key: key, value: value) }
            } header: {
                HStack {
                    Text("Key-Value Pairs")
                    Spacer()
                    Text("\(viewModel.config.keyValuePairs.count)").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Key-value pairs override recipe input variables. Each entry becomes a --key=KEY=VALUE argument.")
            }

            // MARK: - Source Packages
            Section {
                sourcePackagesList
                Button {
                    chooseSourcePackage()
                } label: {
                    Label("Add Package…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            } header: {
                HStack {
                    Text("Source Packages")
                    Spacer()
                    Text("\(viewModel.config.sourcePackages.count)").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("A source package to pass to autopkg run. Only one can be active at a time (--pkg argument).")
            }

            // MARK: - Command Preview
            Section("Command Preview") {
                Text(viewModel.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let status = viewModel.statusMessage {
                Section {
                    Text(status).font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Arguments")
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private var preProcessorsList: some View {
        if viewModel.config.preProcessors.isEmpty {
            Text("No pre-processors configured.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.config.preProcessors) { item in
                ToggleableItemRow(
                    item: item, icon: "gearshape", iconColor: .blue,
                    onToggle: { viewModel.togglePreProcessor(id: item.id) },
                    onDelete: { withAnimation { viewModel.removePreProcessor(id: item.id) } }
                )
            }
        }
    }

    @ViewBuilder
    private var postProcessorsList: some View {
        if viewModel.config.postProcessors.isEmpty {
            Text("No post-processors configured.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.config.postProcessors) { item in
                ToggleableItemRow(
                    item: item, icon: "gearshape.2", iconColor: .orange,
                    onToggle: { viewModel.togglePostProcessor(id: item.id) },
                    onDelete: { withAnimation { viewModel.removePostProcessor(id: item.id) } }
                )
            }
        }
    }

    @ViewBuilder
    private var keyValuePairsList: some View {
        if viewModel.config.keyValuePairs.isEmpty {
            Text("No key-value pairs configured.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.config.keyValuePairs) { pair in
                KeyValuePairRow(
                    pair: pair,
                    onToggle: { viewModel.toggleKeyValuePair(id: pair.id) },
                    onUpdate: { id, key, value in viewModel.updateKeyValuePair(id: id, key: key, value: value) },
                    onDelete: { id in withAnimation { viewModel.removeKeyValuePair(id: id) } }
                )
            }
        }
    }

    @ViewBuilder
    private var sourcePackagesList: some View {
        if viewModel.config.sourcePackages.isEmpty {
            Text("No source packages configured.").font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.config.sourcePackages) { item in
                HStack {
                    Button {
                        if item.isEnabled {
                            viewModel.disableSourcePackage(id: item.id)
                        } else {
                            viewModel.enableSourcePackage(id: item.id)
                        }
                    } label: {
                        Image(systemName: item.isEnabled ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isEnabled ? "Disable this package" : "Enable this package (disables others)")

                    Image(systemName: "shippingbox")
                        .foregroundStyle(item.isEnabled ? .green : .secondary)
                        .font(.caption)

                    Text(item.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(item.isEnabled ? .primary : .secondary)
                        .lineLimit(1).truncationMode(.middle)

                    Spacer()

                    Button {
                        withAnimation { viewModel.removeSourcePackage(id: item.id) }
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove source package")
                }
            }
        }
    }

    private func chooseSourcePackage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Source Package"
        panel.allowedContentTypes = [.package, .init(filenameExtension: "pkg")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let lastDir = UserDefaults.standard.string(forKey: "lastSourcePackageDirectory") {
            panel.directoryURL = URL(fileURLWithPath: lastDir)
        }
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: "lastSourcePackageDirectory")
            viewModel.addSourcePackage(url.path)
        }
    }
}

// MARK: - Toggleable Item Row

struct ToggleableItemRow: View {
    let item: ArgumentsConfig.ToggleableItem
    let icon: String
    let iconColor: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button { onToggle() } label: {
                Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isEnabled ? "Disable" : "Enable")

            Image(systemName: icon)
                .foregroundStyle(item.isEnabled ? iconColor : .secondary)
                .font(.caption)

            Text(item.name)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(item.isEnabled ? .primary : .secondary)

            Spacer()

            Button { onDelete() } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
    }
}

// MARK: - Add Item Field

struct AddItemField: View {
    let label: String
    let buttonLabel: String
    let onAdd: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { addItem() }
                Button(buttonLabel) { addItem() }
                    .buttonStyle(.bordered)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addItem() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        text = ""
    }
}

// MARK: - Add Key-Value Field

struct AddKeyValueField: View {
    let onAdd: (String, String) -> Void
    @State private var key = ""
    @State private var value = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("KEY", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 120)
                .onSubmit { addPair() }
            Text("=").foregroundStyle(.secondary)
            TextField("VALUE", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { addPair() }
            Button("Add") { addPair() }
                .buttonStyle(.bordered)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func addPair() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        onAdd(trimmedKey, value)
        key = ""; value = ""
    }
}

// MARK: - Key-Value Pair Row

struct KeyValuePairRow: View {
    let pair: ArgumentsConfig.KeyValuePair
    let onToggle: () -> Void
    let onUpdate: (UUID, String, String) -> Void
    let onDelete: (UUID) -> Void
    @State private var isEditing = false
    @State private var editKey: String = ""
    @State private var editValue: String = ""

    var body: some View {
        HStack {
            Button { onToggle() } label: {
                Image(systemName: pair.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(pair.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(pair.isEnabled ? "Disable" : "Enable")

            Image(systemName: "key")
                .foregroundStyle(pair.isEnabled ? .purple : .secondary)
                .font(.caption)

            if isEditing {
                TextField("KEY", text: $editKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 100)
                Text("=").foregroundStyle(.secondary)
                TextField("VALUE", text: $editValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button {
                    onUpdate(pair.id, editKey, editValue)
                    isEditing = false
                } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(editKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    isEditing = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(pair.key)
                    .font(.system(.body, design: .monospaced)).fontWeight(.medium)
                    .foregroundStyle(pair.isEnabled ? .primary : .secondary)
                Text("=").foregroundStyle(.secondary)
                Text(pair.value)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    editKey = pair.key; editValue = pair.value; isEditing = true
                } label: {
                    Image(systemName: "pencil").foregroundStyle(.blue)
                }
                .buttonStyle(.plain).help("Edit key-value pair")
                Button { onDelete(pair.id) } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain).help("Remove key-value pair")
            }
        }
    }
}

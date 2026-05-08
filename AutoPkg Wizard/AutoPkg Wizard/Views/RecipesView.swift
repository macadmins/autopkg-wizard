import SwiftUI

struct RecipesView: View {
    @State private var viewModel = RecipesViewModel()
    @State private var isEditing = false
    @State private var selectedRecipes: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.recipeList.isEmpty {
                ContentUnavailableView(
                    "No Recipes in List",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add recipes to your recipe list to get started.\nRecipe list: \(AutoPkgCLI.shared.recipeListPath)")
                )
            } else {
                recipeListView
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        selectedRecipes.removeAll()
                    }
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .disabled(viewModel.recipeList.isEmpty)
                    .help("Select recipes to remove")
                }

                Button {
                    viewModel.runAllRecipes()
                } label: {
                    Label("Run All", systemImage: "play.fill")
                }
                .disabled(viewModel.recipeList.isEmpty || viewModel.isRunning || isEditing)
                .help("Run all recipes in the list")

                Button {
                    viewModel.showAddSheet = true
                } label: {
                    Label("Add Recipe", systemImage: "plus")
                }
                .disabled(isEditing)
                .help("Add a recipe to the list")
            }
        }
        .onAppear {
            viewModel.loadRecipeList()
            viewModel.loadOverrides()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overridesDidChange)) { _ in
            viewModel.loadOverrides()
        }
        .sheet(isPresented: $viewModel.showAddSheet) {
            AddRecipeSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showRunLog) {
            RunLogSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showRecipeInfo) {
            RecipeInfoSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var recipeListView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(viewModel.recipeList, id: \.self) { recipe in
                        HStack {
                            if isEditing {
                                Button {
                                    toggleSelection(recipe)
                                } label: {
                                    Image(systemName: selectedRecipes.contains(recipe) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedRecipes.contains(recipe) ? .blue : .secondary)
                                        .imageScale(.large)
                                }
                                .buttonStyle(.plain)
                            }
                            RecipeRow(name: recipe)
                            Spacer()
                            if !isEditing {
                                Button {
                                    viewModel.fetchRecipeInfo(recipe)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Info for \(recipe)")

                                if viewModel.creatingOverrideFor == recipe {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button {
                                        Task { await viewModel.makeOverride(recipe) }
                                    } label: {
                                        Image(systemName: "document.on.document")
                                            .foregroundStyle(viewModel.hasOverride(recipe) ? .green.opacity(0.6) : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(viewModel.hasOverride(recipe) ? "Override exists for \(recipe)" : "Create override for \(recipe)")
                                    .disabled(viewModel.hasOverride(recipe))
                                }

                                if viewModel.isRunning && viewModel.runningRecipe == recipe {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button {
                                        viewModel.runSingleRecipe(recipe)
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Run \(recipe)")
                                    .disabled(viewModel.isRunning)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditing { toggleSelection(recipe) }
                        }
                        .contextMenu {
                            if !isEditing {
                                Button("Remove from List", role: .destructive) {
                                    viewModel.removeRecipe(recipe)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !isEditing {
                                Button("Remove", role: .destructive) {
                                    viewModel.removeRecipe(recipe)
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        if !isEditing { viewModel.moveRecipes(from: source, to: destination) }
                    }
                } header: {
                    HStack {
                        Text("\(viewModel.recipeList.count) recipe\(viewModel.recipeList.count == 1 ? "" : "s") in list")
                        Spacer()
                        Text(AutoPkgCLI.shared.recipeListPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if isEditing {
                HStack {
                    Button(role: .destructive) {
                        deleteSelectedRecipes()
                    } label: {
                        Label("Remove Selected", systemImage: "trash")
                    }
                    .disabled(selectedRecipes.isEmpty)
                    Spacer()
                    Text("\(selectedRecipes.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func toggleSelection(_ recipe: String) {
        if selectedRecipes.contains(recipe) {
            selectedRecipes.remove(recipe)
        } else {
            selectedRecipes.insert(recipe)
        }
    }

    private func deleteSelectedRecipes() {
        for recipe in selectedRecipes { viewModel.removeRecipe(recipe) }
        selectedRecipes.removeAll()
        isEditing = false
    }
}

// MARK: - Recipe Row

struct RecipeRow: View {
    let name: String

    var body: some View {
        HStack {
            Image(systemName: recipeIcon)
                .foregroundStyle(recipeColor)
                .frame(width: 20)
            Text(name).font(.body)
        }
        .padding(.vertical, 1)
    }

    private var recipeIcon: String {
        if name.hasSuffix(".jamf") { return "server.rack" }
        if name.hasSuffix(".munki") { return "shippingbox" }
        if name.hasSuffix(".download") { return "arrow.down.circle" }
        if name.hasSuffix(".pkg") { return "shippingbox.fill" }
        if name.hasSuffix(".install") { return "square.and.arrow.down" }
        return "doc.text"
    }

    private var recipeColor: Color {
        if name.hasSuffix(".jamf") { return .blue }
        if name.hasSuffix(".munki") { return .orange }
        if name.hasSuffix(".download") { return .green }
        if name.hasSuffix(".pkg") { return .purple }
        if name.hasSuffix(".install") { return .teal }
        return .secondary
    }
}

// MARK: - Add Recipe Sheet

struct AddRecipeSheet: View {
    @Bindable var viewModel: RecipesViewModel
    @State private var selectedTab = 0
    @State private var manualRecipeName = ""
    @State private var selectedAvailableRecipe: AutoPkgRecipe?
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Recipe to List").font(.headline)

            TabView(selection: $selectedTab) {
                availableRecipesTab
                    .tabItem { Label("Available Recipes", systemImage: "list.bullet") }
                    .tag(0)
                searchTab
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(1)
                manualTab
                    .tabItem { Label("Manual Entry", systemImage: "pencil") }
                    .tag(2)
            }
            .frame(height: 350)

            HStack {
                Button("Done") { viewModel.showAddSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await viewModel.loadAvailableRecipes() }
    }

    private var availableRecipesTab: some View {
        VStack(spacing: 8) {
            TextField("Filter recipes…", text: $filterText).textFieldStyle(.roundedBorder)
            let filtered = filteredAvailableRecipes
            if viewModel.isLoading {
                ProgressView("Loading available recipes…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: filterText).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, selection: $selectedAvailableRecipe) { recipe in
                    HStack {
                        Text(recipe.name).font(.body)
                        Spacer()
                        if viewModel.isInRecipeList(recipe.name) {
                            Text("In List").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Add") { viewModel.addRecipe(recipe.name) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var filteredAvailableRecipes: [AutoPkgRecipe] {
        filterText.isEmpty ? viewModel.availableRecipes :
            viewModel.availableRecipes.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    private var searchTab: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search for recipes…", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.performSearch() } }
                Button("Search") { Task { await viewModel.performSearch() } }
                    .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if viewModel.isSearching {
                ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView(
                    "Search for Recipes", systemImage: "magnifyingglass",
                    description: Text("Search for recipes available on GitHub.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.searchResults) { result in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(result.name).font(.body)
                            Text(result.repo).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.isInRecipeList(result.name) {
                            Text("In List").font(.caption).foregroundStyle(.secondary)
                        } else if viewModel.addingRepoForResult == result.id {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text(viewModel.repoAddStatus ?? "Adding…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Add") { Task { await viewModel.addRecipeFromSearchResult(result) } }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(viewModel.addingRepoForResult != nil)
                        }
                    }
                }
            }
        }
    }

    private var manualTab: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Enter a recipe identifier manually (e.g. \"Firefox.jamf\")")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Recipe identifier", text: $manualRecipeName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addManualRecipe() }
            Button("Add to List") { addManualRecipe() }
                .disabled(manualRecipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(.horizontal)
    }

    private func addManualRecipe() {
        let name = manualRecipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        viewModel.addRecipe(name)
        manualRecipeName = ""
    }
}

// MARK: - Run Log Sheet

struct RunLogSheet: View {
    @Bindable var viewModel: RecipesViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recipe Run Output").font(.headline)
                Spacer()
                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Running…").font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(viewModel.runLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(lineColor(for: line))
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: viewModel.runLog.count) { _, _ in
                    if let last = viewModel.runLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.runLog.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Close") { viewModel.showRunLog = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isRunning)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("⚠️") || line.contains("WARNING") { return .orange }
        if line.hasPrefix("ERROR") || line.contains("ERROR") { return .red }
        if line.hasPrefix("✅") { return .green }
        return .primary
    }
}

// MARK: - Recipe Info Sheet

struct RecipeInfoSheet: View {
    @Bindable var viewModel: RecipesViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recipe Info: \(viewModel.recipeInfoName)").font(.headline)
                Spacer()
                if viewModel.isLoadingInfo { ProgressView().controlSize(.small) }
            }
            if viewModel.isLoadingInfo && viewModel.recipeInfoParsed == nil {
                ProgressView("Loading info…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = viewModel.recipeInfoParsed {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        infoSection {
                            infoRow("Description", value: info.description)
                            Divider()
                            infoRow("Identifier", value: info.identifier)
                            Divider()
                            infoRow("Recipe file path", value: info.recipeFilePath)
                        }
                        infoSection {
                            infoRow("Munki import recipe", value: info.munkiImportRecipe)
                            Divider()
                            infoRow("Has check phase", value: info.hasCheckPhase)
                            Divider()
                            infoRow("Builds package", value: info.buildsPackage)
                        }
                        if !info.parentRecipes.isEmpty {
                            infoSection {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Parent recipe(s)").font(.caption).foregroundStyle(.secondary)
                                    ForEach(info.parentRecipes, id: \.self) { parent in
                                        Text(parent).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        if !info.inputValues.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Input Values").font(.subheadline).fontWeight(.semibold)
                                infoSection {
                                    ForEach(Array(info.inputValues.enumerated()), id: \.offset) { index, entry in
                                        if index > 0 { Divider() }
                                        InputValueRow(label: entry.key, value: entry.value)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            } else {
                ScrollView {
                    Text(viewModel.recipeInfoRaw)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.recipeInfoRaw, forType: .string)
                }
                .disabled(viewModel.recipeInfoRaw.isEmpty)
                Spacer()
                Button("Close") { viewModel.showRecipeInfo = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }

    private func infoSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Input Value Row (recursive)

struct InputValueRow: View {
    let label: String
    let value: InputValue
    var indentLevel: Int = 0

    var body: some View {
        switch value {
        case .dict(let entries):
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { Divider() }
                        InputValueRow(label: entry.key, value: entry.value, indentLevel: indentLevel + 1)
                    }
                }
                .padding(.leading, 4)
            } label: {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        case .list(let items):
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        if item.isComplex {
                            InputValueRow(label: "[\(index)]", value: item, indentLevel: indentLevel + 1)
                        } else {
                            InputValueLeaf(text: item.displayString)
                        }
                    }
                }
                .padding(.leading, 4)
            } label: {
                HStack(spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text("(\(items.count) item\(items.count == 1 ? "" : "s"))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        case .string(let s) where s.contains("\n"):
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
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
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                InputValueLeaf(text: value.displayString)
            }
        }
    }
}

struct InputValueLeaf: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "—" : text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }
}

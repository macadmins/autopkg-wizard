import SwiftUI

@MainActor
@Observable
final class RecipesViewModel {
    private let cli = AutoPkgCLI.shared

    // Current recipe list (from file)
    var recipeList: [String] = []
    var availableRecipes: [AutoPkgRecipe] = []
    var searchResults: [AutoPkgSearchResult] = []
    var searchQuery = ""

    var isLoading = false
    var isSearching = false
    var isRunning = false
    var showAddSheet = false
    var showRunLog = false
    var showError = false
    var errorMessage: String?

    var runLog: [String] = []

    /// Tracks which search result is currently having its repo added
    var addingRepoForResult: String?
    /// Status message shown while adding a repo for a search result
    var repoAddStatus: String?

    // MARK: - Override State

    /// Set of recipe names that have an existing override (stripped, lowercased for matching)
    var existingOverrides: Set<String> = []
    /// Full list of override files (used to compute overridesNotInList)
    var overridesList: [AutoPkgOverride] = []
    /// The recipe currently having an override created
    var creatingOverrideFor: String?

    /// Overrides whose recipe name is not present in the current recipe list.
    var overridesNotInList: [AutoPkgOverride] {
        overridesList.filter { !isInRecipeList($0.recipeName) }
    }

    // MARK: - Make-Override Sheet State

    /// The parent recipe name for which we're about to create an override
    var pendingOverrideParent: String?
    /// Whether to add the (possibly renamed) override name to the recipe list after creation
    var pendingOverrideAddToList: Bool = false
    /// Whether the make-override naming sheet is visible
    var showMakeOverrideSheet: Bool = false

    // MARK: - Recipe List Management

    /// Strip recipe file suffixes (.recipe, .recipe.yaml, .recipe.plist) from a name.
    /// AutoPkg recipe lists should use bare identifiers (e.g. "Firefox.munki") so that
    /// overrides can be resolved correctly.
    static func strippedRecipeName(_ name: String) -> String {
        var result = name
        for suffix in [".recipe.yaml", ".recipe.plist", ".recipe"] {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        return result
    }

    /// Check whether a recipe name (possibly including a file suffix) is already in the list.
    func isInRecipeList(_ name: String) -> Bool {
        let stripped = Self.strippedRecipeName(name)
        return recipeList.contains(where: { Self.strippedRecipeName($0) == stripped })
    }

    func loadRecipeList() {
        do {
            recipeList = try cli.readRecipeList()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        Task {
            await ensureMakeCatalogs()
        }
    }

    func saveRecipeList() {
        do {
            try cli.writeRecipeList(recipeList)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        Task {
            await ensureMakeCatalogs()
        }
    }

    func addRecipe(_ name: String) {
        let stripped = Self.strippedRecipeName(name)
        guard !stripped.isEmpty, !isInRecipeList(stripped) else { return }
        recipeList.append(stripped)
        saveRecipeList()
        if UserDefaults.standard.bool(forKey: "autoCreateOverride"), !hasOverride(stripped) {
            pendingOverrideParent = stripped
            pendingOverrideAddToList = true
            showMakeOverrideSheet = true
        }
    }

    func removeRecipes(at offsets: IndexSet) {
        recipeList.remove(atOffsets: offsets)
        saveRecipeList()
    }

    func removeRecipe(_ name: String) {
        recipeList.removeAll { $0 == name }
        saveRecipeList()
    }

    func moveRecipes(from source: IndexSet, to destination: Int) {
        recipeList.move(fromOffsets: source, toOffset: destination)
        saveRecipeList()
    }

    // MARK: - Overrides

    private static let makeCatalogsRecipe = "MakeCatalogs.munki"

    /// Scan the overrides directory and build the set of recipe names that have overrides.
    func loadOverrides() {
        let overrides = AutoPkgOverride.listOverrides(in: cli.overridesDirectory)
        overridesList = overrides
        existingOverrides = Set(overrides.map { $0.recipeName.lowercased() })
    }

    /// Check whether a recipe has an existing override.
    func hasOverride(_ recipeName: String) -> Bool {
        existingOverrides.contains(recipeName.lowercased())
    }

    /// Show the naming sheet before creating an override from the recipe list button.
    func requestMakeOverride(_ recipeName: String) {
        pendingOverrideParent = recipeName
        pendingOverrideAddToList = false
        showMakeOverrideSheet = true
    }

    /// Create an override for `parentRecipeName` using `overrideName` as the output name.
    /// If `updateListEntry` is true, the recipe list entry for `parentRecipeName` is replaced
    /// with `overrideName` (used when auto-creating on add, so the list tracks the override).
    func makeOverride(parent parentRecipeName: String, overrideName: String, updateListEntry: Bool) async {
        let name = overrideName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        creatingOverrideFor = parentRecipeName
        do {
            let customName = (name == parentRecipeName) ? nil : name
            _ = try await cli.makeOverride(parentRecipeName, name: customName)
            if updateListEntry, name != parentRecipeName,
               let idx = recipeList.firstIndex(of: parentRecipeName) {
                recipeList[idx] = name
                saveRecipeList()
            }
            loadOverrides()
            NotificationCenter.default.post(name: .overridesDidChange, object: nil)
        } catch {
            errorMessage = "Failed to create override for \(parentRecipeName): \(error.localizedDescription)"
            showError = true
        }
        creatingOverrideFor = nil
    }

    /// Called when an override file is renamed in the Overrides pane.
    func handleOverrideRenamed(oldName: String, newName: String) {
        guard oldName != newName else { return }
        if let idx = recipeList.firstIndex(of: oldName) {
            recipeList[idx] = newName
            saveRecipeList()
        }
        loadOverrides()
    }

    // MARK: - MakeCatalogs.munki management

    /// If any .munki recipes are in the list, ensure MakeCatalogs.munki is
    /// present at the very end, the autopkg/recipes repo is installed, and
    /// an override exists.  If no .munki recipes remain, remove it.
    func ensureMakeCatalogs() async {
        let hasMunki = recipeList.contains { name in
            name.hasSuffix(".munki") && name != Self.makeCatalogsRecipe
        }

        if hasMunki {
            // Remove from current position (if any) so we can re-append at the end
            recipeList.removeAll { $0 == Self.makeCatalogsRecipe }
            recipeList.append(Self.makeCatalogsRecipe)

            do {
                try cli.writeRecipeList(recipeList)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }

            // Ensure the autopkg/recipes repo is installed (contains MakeCatalogs)
            do {
                let installedRepos = try await cli.repoList()
                let repoInstalled = installedRepos.contains { repo in
                    let url = repo.url.lowercased().replacingOccurrences(of: ".git", with: "")
                    return url.hasSuffix("/autopkg/recipes")
                }
                if !repoInstalled {
                    _ = try await cli.repoAdd("recipes")
                }
            } catch {
                errorMessage = "Failed to add autopkg/recipes repo: \(error.localizedDescription)"
                showError = true
            }

            // Ensure an override exists
            if !hasOverride(Self.makeCatalogsRecipe) {
                do {
                    _ = try await cli.makeOverride(Self.makeCatalogsRecipe)
                    loadOverrides()
                    NotificationCenter.default.post(name: .overridesDidChange, object: nil)
                } catch {
                    // Override creation may fail if one already exists on disk
                    // but wasn't in our cache – reload and check
                    loadOverrides()
                }
            }
        } else {
            // No .munki recipes – remove MakeCatalogs if present
            let hadIt = recipeList.contains(Self.makeCatalogsRecipe)
            if hadIt {
                recipeList.removeAll { $0 == Self.makeCatalogsRecipe }
                do {
                    try cli.writeRecipeList(recipeList)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    // MARK: - Available Recipes

    func loadAvailableRecipes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            availableRecipes = try await cli.listRecipes()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Search

    func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await cli.search(query)
        } catch {
            // Search errors are often just "no results", don't show alert
            searchResults = []
        }
    }

    // MARK: - Add from Search (with auto repo-add)

    /// Add a recipe from a search result.  If the repo that contains the recipe
    /// is not yet installed, it is added automatically first.
    func addRecipeFromSearchResult(_ result: AutoPkgSearchResult) async {
        let strippedName = Self.strippedRecipeName(result.name)
        guard !strippedName.isEmpty, !isInRecipeList(strippedName) else { return }

        addingRepoForResult = result.id

        do {
            // Check whether the repo is already installed
            let installedRepos = try await cli.repoList()
            let repoSlug = result.repo.lowercased()
            let alreadyInstalled = installedRepos.contains { repo in
                let url = repo.url.lowercased()
                    .replacingOccurrences(of: ".git", with: "")
                let path = repo.path.lowercased()
                return url.hasSuffix("/\(repoSlug)")
                    || path.hasSuffix(repoSlug)
                    || url.hasSuffix("/autopkg/\(repoSlug)")
                    || path.contains("com.github.autopkg.\(repoSlug)")
            }

            if !alreadyInstalled {
                repoAddStatus = "Adding repo \(result.repo)…"
                _ = try await cli.repoAdd(result.repo)
                repoAddStatus = nil
            }

            addRecipe(strippedName)
        } catch {
            errorMessage = "Failed to add repo \"\(result.repo)\": \(error.localizedDescription)"
            showError = true
        }

        repoAddStatus = nil
        addingRepoForResult = nil
    }

    // MARK: - Run

    /// The individual recipe currently being run (nil when running all or idle)
    var runningRecipe: String?

    /// Recipe info state
    var showRecipeInfo = false
    var recipeInfoName: String = ""
    var recipeInfoRaw: String = ""
    var recipeInfoParsed: RecipeInfo?
    var isLoadingInfo = false

    func runAllRecipes() {
        isRunning = true
        runningRecipe = nil
        runLog = []
        showRunLog = true

        let (stream, task) = cli.runRecipeList()

        Task {
            for await line in stream {
                runLog.append(line)
            }
            let exitCode = await task.value
            if exitCode == 0 {
                runLog.append("")
                runLog.append("✅ All recipes completed successfully.")
            } else {
                runLog.append("")
                runLog.append("⚠️ Recipe run finished with exit code \(exitCode).")
            }
            // Extract and save the run summary
            if let summary = RunSummary.extract(from: runLog) {
                summary.save()
            }
            isRunning = false
        }
    }

    func runSingleRecipe(_ name: String) {
        isRunning = true
        runningRecipe = name
        runLog = []
        showRunLog = true

        let (stream, task) = cli.runRecipe(name)

        Task {
            for await line in stream {
                runLog.append(line)
            }
            let exitCode = await task.value
            if exitCode == 0 {
                runLog.append("")
                runLog.append("✅ \(name) completed successfully.")
            } else {
                runLog.append("")
                runLog.append("⚠️ \(name) finished with exit code \(exitCode).")
            }
            // Extract and save the run summary
            if let summary = RunSummary.extract(from: runLog) {
                summary.save()
            }
            isRunning = false
            runningRecipe = nil
        }
    }

    // MARK: - Recipe Info

    func fetchRecipeInfo(_ name: String) {
        recipeInfoName = name
        recipeInfoRaw = ""
        recipeInfoParsed = nil
        isLoadingInfo = true
        showRecipeInfo = true

        Task {
            do {
                let output = try await cli.recipeInfo(name)
                recipeInfoRaw = output
                recipeInfoParsed = RecipeInfo.parse(from: output)
            } catch {
                recipeInfoRaw = "Failed to get info for \(name):\n\(error.localizedDescription)"
                recipeInfoParsed = nil
            }
            isLoadingInfo = false
        }
    }
}

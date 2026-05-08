import Foundation

/// Represents a recipe that is available locally (from `autopkg list-recipes`)
struct AutoPkgRecipe: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String

    /// Parse output from `autopkg list-recipes`
    /// Each line is a recipe identifier, e.g. "Firefox.munki"
    static func parse(from output: String) -> [AutoPkgRecipe] {
        output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { AutoPkgRecipe(name: $0) }
    }
}

/// Represents a search result from `autopkg search`
struct AutoPkgSearchResult: Identifiable, Hashable, Sendable {
    var id: String { "\(repo)/\(name)" }
    let name: String
    let repo: String
    let path: String

    /// Parse output from `autopkg search <query>`
    /// Format (fixed-width columns):
    /// ```
    /// Name                  Repo               Path
    /// ----                  ----               ----
    /// Firefox.download      autopkg/recipes    Recipes/Firefox/Firefox.download.recipe
    /// Opera GX.munki        someuser/recipes   Recipes/Opera GX/Opera GX.munki.recipe
    /// ```
    /// Trailing informational lines (e.g. "To add a repo…") are ignored.
    static func parse(from output: String) -> [AutoPkgSearchResult] {
        let lines = output.components(separatedBy: "\n")
        // Find the header separator line (contains "----")
        guard let separatorIndex = lines.firstIndex(where: { $0.contains("----") }) else {
            return []
        }
        // Determine column positions from the header line above the separator
        let headerLine = separatorIndex > 0 ? lines[separatorIndex - 1] : ""
        let repoCol: Int
        let pathCol: Int
        if let repoRange = headerLine.range(of: "Repo"),
           let pathRange = headerLine.range(of: "Path") {
            repoCol = headerLine.distance(from: headerLine.startIndex, to: repoRange.lowerBound)
            pathCol = headerLine.distance(from: headerLine.startIndex, to: pathRange.lowerBound)
        } else {
            // Fallback: use separator line dashes to find column starts
            let sep = lines[separatorIndex]
            let segments = findColumnStarts(in: sep)
            guard segments.count >= 3 else { return [] }
            repoCol = segments[1]
            pathCol = segments[2]
        }

        // Take only lines up to the first empty line after the data rows
        let dataLines = lines.dropFirst(separatorIndex + 1)
        let endIndex = dataLines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        let relevantLines = endIndex != nil ? dataLines[dataLines.startIndex..<endIndex!] : dataLines[dataLines.startIndex..<dataLines.endIndex]

        return relevantLines
            .compactMap { line in
                // Skip lines that are too short to contain all columns
                guard line.count >= pathCol + 1 else { return nil }
                let nameEnd = min(repoCol, line.count)
                let name = String(line.prefix(nameEnd)).trimmingCharacters(in: .whitespaces)
                let repoEnd = min(pathCol, line.count)
                let repoStart = line.index(line.startIndex, offsetBy: repoCol)
                let repoEndIdx = line.index(line.startIndex, offsetBy: repoEnd)
                let repo = String(line[repoStart..<repoEndIdx]).trimmingCharacters(in: .whitespaces)
                let pathStart = line.index(line.startIndex, offsetBy: pathCol)
                let path = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !repo.isEmpty, !path.isEmpty else { return nil }
                return AutoPkgSearchResult(name: name, repo: repo, path: path)
            }
    }

    /// Find the starting character indices of dash-separated columns in a separator line.
    private static func findColumnStarts(in line: String) -> [Int] {
        var starts: [Int] = []
        var inDashes = false
        for (i, ch) in line.enumerated() {
            if ch == "-" {
                if !inDashes { starts.append(i) }
                inDashes = true
            } else {
                inDashes = false
            }
        }
        return starts
    }
}

/// Represents a recipe override file in ~/Library/AutoPkg/RecipeOverrides/
struct AutoPkgOverride: Identifiable, Hashable, Sendable {
    var id: String { filePath }
    let filePath: String
    let fileName: String

    /// The recipe name derived from the file name (strip recipe suffixes)
    var recipeName: String {
        var name = fileName
        for suffix in [".recipe.yaml", ".recipe.plist", ".recipe"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                return name
            }
        }
        return (name as NSString).deletingPathExtension
    }

    /// Read the file contents for display
    func contents() throws -> String {
        try String(contentsOfFile: filePath, encoding: .utf8)
    }

    /// List override files from the overrides directory
    static func listOverrides(in directory: String) -> [AutoPkgOverride] {
        let fm = FileManager.default
        let expandedDir = NSString(string: directory).expandingTildeInPath
        guard let files = try? fm.contentsOfDirectory(atPath: expandedDir) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".recipe") || $0.hasSuffix(".recipe.yaml") || $0.hasSuffix(".recipe.plist") }
            .sorted()
            .map { fileName in
                let fullPath = (expandedDir as NSString).appendingPathComponent(fileName)
                return AutoPkgOverride(filePath: fullPath, fileName: fileName)
            }
    }
}

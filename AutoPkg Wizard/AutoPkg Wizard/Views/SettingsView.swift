import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var autoPkgPath: String = AutoPkgCLI.shared.autoPkgPath
    @State private var recipeListPath: String = AutoPkgCLI.shared.recipeListPath
    @State private var overridesDirectory: String = AutoPkgCLI.shared.overridesDirectory
    @State private var isSaved = false

    @Bindable private var themeManager = SyntaxThemeManager.shared
    private var cli = AutoPkgCLI.shared

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            editorTab
                .tabItem { Label("Editor", systemImage: "paintbrush") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 380)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("AutoPkg Binary") {
                HStack {
                    TextField("Path to autopkg", text: $autoPkgPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
                        if panel.runModal() == .OK, let url = panel.url {
                            autoPkgPath = url.path
                        }
                    }
                }

                if FileManager.default.isExecutableFile(atPath: autoPkgPath) {
                    Label("Binary found", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Binary not found at this path", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Recipe List File") {
                HStack {
                    TextField("Recipe list path", text: $recipeListPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.plainText]
                        if panel.runModal() == .OK, let url = panel.url {
                            recipeListPath = url.path
                        }
                    }
                }
            }

            Section("Recipe Overrides Directory") {
                HStack {
                    TextField("Overrides directory", text: $overridesDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            overridesDirectory = url.path
                        }
                    }
                }
            }

            Section {
                HStack {
                    if isSaved {
                        Text("Settings saved.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Restore Defaults") {
                        autoPkgPath = "/usr/local/bin/autopkg"
                        recipeListPath = NSString(string: "~/Library/AutoPkg/recipe-list.txt").expandingTildeInPath
                        overridesDirectory = NSString(string: "~/Library/AutoPkg/RecipeOverrides").expandingTildeInPath
                    }

                    Button("Save") {
                        cli.autoPkgPath = autoPkgPath
                        cli.recipeListPath = recipeListPath
                        cli.overridesDirectory = overridesDirectory
                        isSaved = true
                        Task {
                            await cli.checkInstallation()
                            try? await Task.sleep(for: .seconds(2))
                            isSaved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Editor Tab

    private var editorTab: some View {
        Form {
            Section("Light Mode Theme") {
                Picker("Theme", selection: $themeManager.lightTheme) {
                    ForEach(themeManager.availableThemes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .labelsHidden()

                if !SyntaxThemeManager.recommendedLightThemes.contains(themeManager.lightTheme) {
                    Text("Recommended: \(SyntaxThemeManager.recommendedLightThemes.sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Dark Mode Theme") {
                Picker("Theme", selection: $themeManager.darkTheme) {
                    ForEach(themeManager.availableThemes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .labelsHidden()

                if !SyntaxThemeManager.recommendedDarkThemes.contains(themeManager.darkTheme) {
                    Text("Recommended: \(SyntaxThemeManager.recommendedDarkThemes.sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Defaults") {
                    themeManager.lightTheme = "xcode"
                    themeManager.darkTheme = "atom-one-dark"
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)

            Text("AutoPkg Wizard")
                .font(.title.bold())

            Text("A modern macOS interface for managing AutoPkg")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider().frame(width: 200)

            if cli.isInstalled {
                Label("AutoPkg \(cli.installedVersion)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("AutoPkg not installed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Link("AutoPkg on GitHub", destination: URL(string: "https://github.com/autopkg/autopkg")!)
                .font(.caption)

            Link("AutoPkg Wizard on GitHub", destination: URL(string: "https://github.com/grahampugh/autopkg-wizard")!)
                .font(.caption)

            Spacer()
        }
        .padding()
    }
}

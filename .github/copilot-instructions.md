# Copilot Instructions for AutoPkg Wizard

## Build & Test Commands

```bash
make              # Debug build (no code signing)
make release      # Release build with signing, notarization, pkg, dmg, and GitHub pre-release

# Run tests via xcodebuild
xcodebuild test \
  -project "AutoPkg Wizard/AutoPkg Wizard.xcodeproj" \
  -scheme "AutoPkg Wizard" \
  -destination "platform=macOS"

# Run a single test (Swift Testing framework)
xcodebuild test \
  -project "AutoPkg Wizard/AutoPkg Wizard.xcodeproj" \
  -scheme "AutoPkg Wizard" \
  -destination "platform=macOS" \
  -only-testing:"AutoPkg WizardTests/RecipesViewModelTests"
```

## Architecture

This is a macOS SwiftUI app (requires macOS 26.0+) that wraps the `autopkg` CLI binary. It does **not** embed or reimplement AutoPkg logic — it shells out to `/usr/local/bin/autopkg` via `Process` and parses stdout/stderr.

### Layer structure

- **Services/** — `AutoPkgCLI` is a `@MainActor @Observable` singleton that executes all autopkg commands and holds shared state (paths, installation status, running state). `LaunchAgentManager` handles scheduling via launchd.
- **ViewModels/** — One per view (e.g. `RecipesViewModel`, `ReposViewModel`). All are `@MainActor @Observable final class` with a reference to `AutoPkgCLI.shared`.
- **Models/** — Plain value types (`struct`, `Sendable`) that parse autopkg CLI output into typed data.
- **Views/** — SwiftUI views. Each major section has its own view file matching the sidebar items: Overview, Repos, Recipes, Overrides, Arguments, Schedule.

### Navigation

The app uses `NavigationSplitView` with a sidebar (`SidebarItem` enum) driving view selection. The entry point is `AutoPkg_WizardApp.swift`.

## Key Conventions

- All ViewModels and `AutoPkgCLI` use the `@MainActor @Observable` pattern (Swift Observation framework, not Combine/ObservableObject).
- Models are `Sendable` structs with `static func parse(from:)` methods that parse autopkg CLI text output.
- Tests use the Swift Testing framework (`import Testing`, `@Test func`, `#expect`) — not XCTest.
- The Xcode project lives at `AutoPkg Wizard/AutoPkg Wizard.xcodeproj`; note the spaces in directory names.
- Version is derived from `MARKETING_VERSION` in `project.pbxproj` — update it there, not in the Makefile.
- Code signing identities and notarization profile are configurable via environment variables (`SIGN_ID_APP`, `SIGN_ID_PKG`, `NOTARY_PROFILE`).

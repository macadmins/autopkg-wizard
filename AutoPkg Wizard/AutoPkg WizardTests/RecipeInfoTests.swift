import Testing
@testable import AutoPkg_Wizard

@Suite("RecipeInfo")
struct RecipeInfoTests {

    @Test func parsesHeaderFieldsAndInputValues() {
        let output = """
        Description:         Downloads the latest Firefox.
        Identifier:          com.github.autopkg.download.Firefox
        Munki import recipe: False
        Has check phase:     True
        Builds package:      False
        Recipe file path:    /Users/jane/Library/AutoPkg/RecipeRepos/com.github.autopkg.recipes/Firefox/Firefox.download.recipe
        Parent recipe(s):    None
        Input values:
            'NAME': 'Firefox',
            'LOCALE': 'en-US',
        """
        let info = RecipeInfo.parse(from: output)
        #expect(info.description == "Downloads the latest Firefox.")
        #expect(info.identifier == "com.github.autopkg.download.Firefox")
        #expect(info.munkiImportRecipe == "False")
        #expect(info.hasCheckPhase == "True")
        #expect(info.buildsPackage == "False")
        #expect(info.recipeFilePath.hasSuffix("Firefox.download.recipe"))
        #expect(info.parentRecipes == ["None"])
        #expect(info.inputValues.count == 2)
        #expect(info.inputValues[0].key == "NAME")
        #expect(info.inputValues[0].value == .string("Firefox"))
        #expect(info.inputValues[1].key == "LOCALE")
        #expect(info.inputValues[1].value == .string("en-US"))
    }

    @Test func parsesMultipleParentRecipesAcrossContinuationLines() {
        let output = """
        Description:         test
        Identifier:          com.example.child
        Parent recipe(s):    /path/parent.download.recipe
                             /path/grandparent.download.recipe
        Input values:
        """
        let info = RecipeInfo.parse(from: output)
        #expect(info.parentRecipes == [
            "/path/parent.download.recipe",
            "/path/grandparent.download.recipe",
        ])
    }

    @Test func parsesComplexPkginfoDict() {
        let output = """
        Description:         Imports Firefox into Munki.
        Identifier:          com.github.autopkg.munki.Firefox
        Munki import recipe: True
        Has check phase:     True
        Builds package:      False
        Recipe file path:    /Users/jane/Library/AutoPkg/RecipeOverrides/Firefox.munki.recipe
        Parent recipe(s):    /Users/jane/Library/AutoPkg/RecipeRepos/com.github.autopkg.recipes/Firefox/Firefox.download.recipe
        Input values:
            'NAME': 'Firefox',
            'pkginfo': {'catalogs': ['testing'],
                        'description': 'Mozilla Firefox is a free and open source web browser.',
                        'display_name': 'Mozilla Firefox',
                        'name': '%NAME%',
                        'unattended_install': True,
                        'items_to_copy': [{'destination_path': '/Applications',
                                           'source_item': 'Firefox.app'}],
                        'postinstall_script': '#!/bin/bash\\necho "done"\\n'},
            'MUNKI_REPO_SUBDIR': 'apps/firefox',
        """
        let info = RecipeInfo.parse(from: output)
        #expect(info.inputValues.count == 3)
        #expect(info.inputValues[0].key == "NAME")
        #expect(info.inputValues[0].value == .string("Firefox"))

        // pkginfo should be a dict
        guard case .dict(let pkginfo) = info.inputValues[1].value else {
            Issue.record("Expected pkginfo to be a dict")
            return
        }
        #expect(info.inputValues[1].key == "pkginfo")
        #expect(pkginfo.count == 7)

        // catalogs is a list
        if case .list(let catalogs) = pkginfo[0].value {
            #expect(catalogs == [.string("testing")])
        } else {
            Issue.record("Expected catalogs to be a list")
        }

        // unattended_install is a bool
        #expect(pkginfo[4].value == .bool(true))

        // items_to_copy is a list of dicts
        if case .list(let items) = pkginfo[5].value,
           case .dict(let firstItem) = items.first {
            #expect(firstItem[0].key == "destination_path")
            #expect(firstItem[0].value == .string("/Applications"))
        } else {
            Issue.record("Expected items_to_copy to be a list of dicts")
        }

        // postinstall_script has escaped newlines
        if case .string(let script) = pkginfo[6].value {
            #expect(script.contains("\n"))
            #expect(script.hasPrefix("#!/bin/bash"))
        } else {
            Issue.record("Expected postinstall_script to be a string")
        }

        #expect(info.inputValues[2].key == "MUNKI_REPO_SUBDIR")
        #expect(info.inputValues[2].value == .string("apps/firefox"))
    }

    @Test func parsesImplicitStringConcatenation() {
        let output = """
        Description:         test
        Identifier:          com.example.test
        Input values:
            'NAME': 'BlockBlock',
            'pkginfo': {'catalogs': ['testing'],
                        'description': 'BlockBlock provides continual protection by '
                                       'monitoring persistence locations. Any new '
                                       'persistent component will trigger a '
                                       'BlockBlock alert, allowing malicious items '
                                       'be blocked.',
                        'display_name': 'BlockBlock',
                        'name': '%NAME%'},
        """
        let info = RecipeInfo.parse(from: output)
        #expect(info.inputValues.count == 2)
        #expect(info.inputValues[0].value == .string("BlockBlock"))

        guard case .dict(let pkginfo) = info.inputValues[1].value else {
            Issue.record("Expected pkginfo to be a dict")
            return
        }
        #expect(pkginfo.count == 4)
        #expect(pkginfo[0].key == "catalogs")

        // description should be the full concatenated string
        #expect(pkginfo[1].key == "description")
        if case .string(let desc) = pkginfo[1].value {
            #expect(desc.hasPrefix("BlockBlock provides"))
            #expect(desc.hasSuffix("be blocked."))
            #expect(desc.contains("monitoring persistence locations"))
        } else {
            Issue.record("Expected description to be a string")
        }

        #expect(pkginfo[2].key == "display_name")
        #expect(pkginfo[2].value == .string("BlockBlock"))
        #expect(pkginfo[3].key == "name")
        #expect(pkginfo[3].value == .string("%NAME%"))
    }
}

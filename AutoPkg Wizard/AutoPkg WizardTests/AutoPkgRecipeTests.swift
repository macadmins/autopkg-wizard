import Testing
@testable import AutoPkg_Wizard

@Suite("AutoPkgRecipe")
struct AutoPkgRecipeTests {

    @Test func parsesRecipesAndDropsBlankLines() {
        let output = """
        Firefox.munki
        GoogleChrome.download

        Slack.pkg
        """
        let recipes = AutoPkgRecipe.parse(from: output)
        #expect(recipes.map(\.name) == ["Firefox.munki", "GoogleChrome.download", "Slack.pkg"])
    }

    @Test func parseEmptyOutputReturnsEmpty() {
        #expect(AutoPkgRecipe.parse(from: "").isEmpty)
    }
}

@Suite("AutoPkgSearchResult")
struct AutoPkgSearchResultTests {

    @Test func parsesTabularSearchOutput() {
        let output = """
        Name                  Repo               Path
        ----                  ----               ----
        Firefox.download      autopkg/recipes    Recipes/Firefox/Firefox.download.recipe
        Firefox.munki         autopkg/recipes    Recipes/Firefox/Firefox.munki.recipe
        """
        let results = AutoPkgSearchResult.parse(from: output)
        #expect(results.count == 2)
        #expect(results[0].name == "Firefox.download")
        #expect(results[0].repo == "autopkg/recipes")
        #expect(results[0].path == "Recipes/Firefox/Firefox.download.recipe")
    }

    @Test func parsesRecipeNamesWithSpaces() {
        let output = """
        Name                  Repo               Path
        ----                  ----               ----
        Opera.intune          user/recipes       Recipes/Opera/Opera.intune.recipe
        Opera GX.munki        user/recipes       Recipes/Opera GX/Opera GX.munki.recipe
        """
        let results = AutoPkgSearchResult.parse(from: output)
        #expect(results.count == 2)
        #expect(results[0].name == "Opera.intune")
        #expect(results[1].name == "Opera GX.munki")
        #expect(results[1].repo == "user/recipes")
        #expect(results[1].path == "Recipes/Opera GX/Opera GX.munki.recipe")
    }

    @Test func ignoresTrailingInformationalLines() {
        let output = """
        Name                                 Repo                    Path                                                             
        ----                                 ----                    ----                                                             
        Opera.intune.recipe                  almenscorner-recipes    Opera/Opera.intune.recipe                                        
        Opera GX.munki.recipe                dataJAR-recipes         Opera GX/Opera GX.munki.recipe                                   

        To add a new recipe repo, use `autopkg repo-add <repo name>`

        If you don't see the recipe you're looking for, try searching https://autopkgweb.com/ (maintained by @jannheider).

        """
        let results = AutoPkgSearchResult.parse(from: output)
        #expect(results.count == 2)
        #expect(results[0].name == "Opera.intune.recipe")
        #expect(results[1].name == "Opera GX.munki.recipe")
        #expect(results[1].repo == "dataJAR-recipes")
    }

    @Test func parseWithoutSeparatorReturnsEmpty() {
        let output = "no header here just random text"
        #expect(AutoPkgSearchResult.parse(from: output).isEmpty)
    }
}

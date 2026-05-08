# Makefile for AutoPkg Wizard
# Usage:
#   make			  - Debug build (.app only)
#   make release	  - Release build (.app + .pkg + .dmg + GitHub pre-release)
#   make pkg		  - Build installer .pkg from existing release .app
#   make dmg		  - Build distributable .dmg from existing release .app
#   make github	   - Create/update GitHub pre-release from existing .pkg and .dmg
#   make clean		- Remove build artifacts
#
#   Override signing/notarization options:
#   make release SIGN_ID_APP="Developer ID Application: Your Name" \
#				SIGN_ID_PKG="Developer ID Installer: Your Name" \
#				NOTARY_PROFILE=your-notarytool-profile
#   or export once:
#   export SIGN_ID_APP="Developer ID Application: Your Name"; \
#   export SIGN_ID_PKG="Developer ID Installer: Your Name"; \
#   export NOTARY_PROFILE=your-notarytool-profile; \
#   make release

SHELL		:= /bin/bash
APP_NAME	 := AutoPkg Wizard
APP_SLUG	 := AutoPkgWizard
BUNDLE_ID	:= com.grahamrpugh.AutoPkg-Wizard
PROJECT	  := AutoPkg Wizard/AutoPkg Wizard.xcodeproj
SCHEME	   := AutoPkg Wizard
VERSION	  := $(shell grep 'MARKETING_VERSION = ' "$(PROJECT)/project.pbxproj" | head -1 | sed 's/.*= //;s/;//;s/ //g')
TAG		  := v$(VERSION)

SIGN_ID_APP	?= Developer ID Application: Graham Pugh
SIGN_ID_PKG	?= Developer ID Installer: Graham Pugh
NOTARY_PROFILE ?= graham-notary-profile-autopkg-wizard
TEAM_ID		?= C96ALZKYH6

# Notes:
# - NOTARY_PROFILE is a keychain profile configured via `xcrun notarytool store-credentials graham-notary-profile --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>`
# - If you prefer inline credentials, replace `--keychain-profile $(NOTARY_PROFILE)` with your choice of `--apple-id/--team-id/--password`.

BUILD_DIR	:= $(CURDIR)/.build
OUTPUT_DIR   := output
RELEASE_APP  := $(BUILD_DIR)/Release/$(APP_NAME).app
DEBUG_APP	:= $(BUILD_DIR)/Debug/$(APP_NAME).app
PKG_NAME	 := $(APP_SLUG)-$(VERSION).pkg
PKG_PATH	 := $(OUTPUT_DIR)/$(PKG_NAME)
COMPONENT	:= $(OUTPUT_DIR)/$(APP_SLUG)-component.pkg
DMG_NAME	 := $(APP_SLUG)-$(VERSION).dmg
DMG_PATH	 := $(OUTPUT_DIR)/$(DMG_NAME)
DMG_STAGING  := $(OUTPUT_DIR)/dmg-staging

.PHONY: all debug release pkg dmg github clean clean-output _pkg _dmg sign notarize notarize-app notarize-pkg staple staple-app staple-pkg _sign_app _notarize_app _notarize_pkg _staple_app _staple_pkg _staple_artifacts

# Default target: debug build
all: debug

# --- Debug build -----------------------------------------------------------
debug:
	@echo "==> Building $(APP_NAME) (debug)…"
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination "platform=macOS" \
		SYMROOT="$(BUILD_DIR)" \
		CODE_SIGNING_ALLOWED=NO \
		build
	@echo "==> Debug app ready: $(DEBUG_APP)"

# --- Internal: sign the built app -----------------------------------------
_sign_app:
	@if [ ! -d "$(RELEASE_APP)" ]; then \
		echo "ERROR: Release app not found at $(RELEASE_APP)." >&2; \
		exit 1; \
	fi
	@echo "==> Signing embedded frameworks and libraries…"
	@find "$(RELEASE_APP)/Contents/Frameworks" -maxdepth 1 \
		\( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | \
		while IFS= read -r item; do \
			echo "	signing: $$item"; \
			/usr/bin/codesign --force --options runtime --timestamp \
				--sign "$(SIGN_ID_APP)" "$$item"; \
		done
	@echo "==> Signing app bundle with '$(SIGN_ID_APP)'…"
	@/usr/bin/codesign \
		--force --options runtime --timestamp \
		--sign "$(SIGN_ID_APP)" \
		"$(RELEASE_APP)"
	@echo "==> Verifying code signature…"
	@/usr/bin/codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP)"
	@/usr/bin/xcrun spctl --assess --type execute --verbose "$(RELEASE_APP)" || true

# --- Internal: notarize the signed app and staple --------------------------
_notarize_app:
	@if [ ! -d "$(RELEASE_APP)" ]; then \
		echo "ERROR: Release app not found at $(RELEASE_APP)." >&2; \
		exit 1; \
	fi
	@echo "==> Zipping app for notarization…"
	@mkdir -p "$(OUTPUT_DIR)"
	@/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(OUTPUT_DIR)/$(APP_SLUG).zip"
	@echo "==> Submitting app to Apple notarization service…"
	@submission_id=$$( \
		/usr/bin/xcrun notarytool submit "$(OUTPUT_DIR)/$(APP_SLUG).zip" \
			--keychain-profile "$(NOTARY_PROFILE)" \
			--output-format json \
		| /usr/bin/jq -r '.id' \
	); \
	echo "==> App Submission ID: $$submission_id"; \
	echo "$$submission_id" > "$(OUTPUT_DIR)/.app-submission-id"; \
	echo "	Submission ID saved to $(OUTPUT_DIR)/.app-submission-id"; \
	echo "	To check status: xcrun notarytool wait $$submission_id --keychain-profile $(NOTARY_PROFILE)"; \
	echo "	To staple later: make staple-app"; \
	/usr/bin/xcrun notarytool wait "$$submission_id" \
		--keychain-profile "$(NOTARY_PROFILE)"; \
	/usr/bin/xcrun notarytool log "$$submission_id" \
		--keychain-profile "$(NOTARY_PROFILE)"
	@rm -f "$(OUTPUT_DIR)/$(APP_SLUG).zip"

# --- Internal: staple the notarized app ------------------------------------
_staple_app:
	@if [ ! -d "$(RELEASE_APP)" ]; then \
		echo "ERROR: Release app not found at $(RELEASE_APP)." >&2; \
		exit 1; \
	fi
	@echo "==> Stapling notarization ticket to app…"
	@/usr/bin/xcrun stapler staple -v "$(RELEASE_APP)"

# --- Internal: notarize the signed pkg -------------------------------------
_notarize_pkg:
	@if [ ! -f "$(PKG_PATH)" ]; then \
		echo "ERROR: Package not found at $(PKG_PATH)." >&2; \
		exit 1; \
	fi
	@echo "==> Submitting pkg to Apple notarization service…"
	@submission_id=$$( \
		/usr/bin/xcrun notarytool submit "$(PKG_PATH)" \
			--keychain-profile "$(NOTARY_PROFILE)" \
			--output-format json \
		| /usr/bin/jq -r '.id' \
	); \
	echo "==> Pkg Submission ID: $$submission_id"; \
	echo "$$submission_id" > "$(OUTPUT_DIR)/.pkg-submission-id"; \
	echo "	Submission ID saved to $(OUTPUT_DIR)/.pkg-submission-id"; \
	echo "	To check status: xcrun notarytool wait $$submission_id --keychain-profile $(NOTARY_PROFILE)"; \
	echo "	To staple later: make staple-pkg"; \
	/usr/bin/xcrun notarytool wait "$$submission_id" \
		--keychain-profile "$(NOTARY_PROFILE)"; \
	/usr/bin/xcrun notarytool log "$$submission_id" \
		--keychain-profile "$(NOTARY_PROFILE)"

# --- Internal: staple the notarized pkg ------------------------------------
_staple_pkg:
	@if [ ! -f "$(PKG_PATH)" ]; then \
		echo "ERROR: Package not found at $(PKG_PATH)." >&2; \
		exit 1; \
	fi
	@echo "==> Stapling notarization ticket to pkg…"
	@/usr/bin/xcrun stapler staple -v "$(PKG_PATH)"

# --- Release build + sign + notarize + staple + pkg + dmg + GitHub release -
release: clean-output
	@echo "==> Building $(APP_NAME) $(VERSION) (release)…"
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
		-destination "platform=macOS" \
		SYMROOT="$(BUILD_DIR)" \
		build
	@echo ""
	@$(MAKE) --no-print-directory _sign_app
	@echo ""
	@$(MAKE) --no-print-directory _notarize_app
	@echo ""
	@$(MAKE) --no-print-directory _staple_app
	@echo ""
	@$(MAKE) --no-print-directory _pkg
	@echo ""
	@$(MAKE) --no-print-directory _notarize_pkg
	@echo ""
	@$(MAKE) --no-print-directory _staple_pkg
	@echo ""
	@$(MAKE) --no-print-directory _dmg
	@echo ""
	@$(MAKE) --no-print-directory github
	@echo ""
	@echo "==> Opening output folder…"
	@open "$(OUTPUT_DIR)"

# --- Sign and notarize only (from existing release app) --------------------
sign:
	@$(MAKE) --no-print-directory _sign_app

# Notarize app only (does not staple)
notarize-app:
	@$(MAKE) --no-print-directory _notarize_app

# Notarize pkg only (does not staple)
notarize-pkg:
	@$(MAKE) --no-print-directory _notarize_pkg

# Notarize both app and pkg (does not staple)
notarize: notarize-app
	@if [ -f "$(PKG_PATH)" ]; then \
		$(MAKE) --no-print-directory notarize-pkg; \
	else \
		echo "==> Pkg not found, skipping pkg notarization"; \
	fi

# Staple app only
staple-app:
	@$(MAKE) --no-print-directory _staple_app

# Staple pkg only
staple-pkg:
	@$(MAKE) --no-print-directory _staple_pkg

# Staple both app and pkg
staple: staple-app
	@if [ -f "$(PKG_PATH)" ]; then \
		$(MAKE) --no-print-directory staple-pkg; \
	else \
		echo "==> Pkg not found, skipping pkg stapling"; \
	fi

# --- Build pkg from existing release app -----------------------------------
pkg:
	@if [ ! -d "$(RELEASE_APP)" ]; then \
		echo "ERROR: Release app not found at $(RELEASE_APP)." >&2; \
		echo "	   Run 'make release' first." >&2; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory _pkg
	@echo "==> Opening output folder…"
	@open "$(OUTPUT_DIR)"

# --- Build dmg from existing release app -----------------------------------
dmg:
	@if [ ! -d "$(RELEASE_APP)" ]; then \
		echo "ERROR: Release app not found at $(RELEASE_APP)." >&2; \
		echo "	   Run 'make release' first." >&2; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory _dmg
	@echo "==> Opening output folder…"
	@open "$(OUTPUT_DIR)"

# --- Create / update GitHub pre-release ------------------------------------
github:
	@if [ ! -f "$(PKG_PATH)" ] && [ ! -f "$(DMG_PATH)" ]; then \
		echo "ERROR: Neither $(PKG_PATH) nor $(DMG_PATH) found." >&2; \
		echo "	   Run 'make release' first." >&2; \
		exit 1; \
	fi
	@echo "==> Preparing GitHub pre-release $(TAG)…"
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "==> Committing uncommitted changes…"; \
		git add -A && git commit -m "Release $(VERSION)"; \
	fi
	@if gh release view "$(TAG)" >/dev/null 2>&1; then \
		echo "==> Deleting existing release $(TAG)…"; \
		gh release delete "$(TAG)" --cleanup-tag --yes; \
		git tag -d "$(TAG)" 2>/dev/null || true; \
	fi
	@echo "==> Creating GitHub pre-release $(TAG)…"
	@git tag "$(TAG)"
	@git push origin "$(TAG)"
	@gh release create "$(TAG)" \
		$(if $(wildcard $(PKG_PATH)),"$(PKG_PATH)#$(PKG_NAME)") \
		$(if $(wildcard $(DMG_PATH)),"$(DMG_PATH)#$(DMG_NAME)") \
		--title "$(APP_NAME) $(VERSION)" \
		--prerelease \
		--generate-notes
	@echo "==> GitHub pre-release $(TAG) created."

# --- Internal: create the .pkg ---------------------------------------------
_pkg:
	@mkdir -p "$(OUTPUT_DIR)"
	@echo "==> Creating component package…"
	@pkgbuild \
		--component "$(RELEASE_APP)" \
		--install-location /Applications \
		--identifier "$(BUNDLE_ID)" \
		--version "$(VERSION)" \
		--sign "$(SIGN_ID_PKG)" \
		"$(COMPONENT)"
	@echo "==> Writing distribution XML…"
	@( \
		echo '<?xml version="1.0" encoding="utf-8"?>'; \
		echo '<installer-gui-script minSpecVersion="2">'; \
		echo '	<title>$(APP_NAME)</title>'; \
		echo '	<pkg-ref id="$(BUNDLE_ID)"/>'; \
		echo '	<options customize="never" require-scripts="false" rootVolumeOnly="true"/>'; \
		echo '	<choices-outline>'; \
		echo '		<line choice="default">'; \
		echo '			<line choice="$(BUNDLE_ID)"/>'; \
		echo '		</line>'; \
		echo '	</choices-outline>'; \
		echo '	<choice id="default"/>'; \
		echo '	<choice id="$(BUNDLE_ID)" visible="false">'; \
		echo '		<pkg-ref id="$(BUNDLE_ID)"/>'; \
		echo '	</choice>'; \
		echo '	<pkg-ref id="$(BUNDLE_ID)" version="$(VERSION)" onConclusion="none">$(notdir $(COMPONENT))</pkg-ref>'; \
		echo '</installer-gui-script>'; \
	) > "$(OUTPUT_DIR)/distribution.xml"
	@echo "==> Creating distribution installer package $(PKG_NAME)…"
	@productbuild \
		--distribution "$(OUTPUT_DIR)/distribution.xml" \
		--package-path "$(OUTPUT_DIR)" \
		--sign "$(SIGN_ID_PKG)" \
		"$(PKG_PATH)"
	@rm -f "$(COMPONENT)" "$(OUTPUT_DIR)/distribution.xml"
	@echo "==> Installer package ready: $(PKG_PATH)"

# --- Internal: create the .dmg ---------------------------------------------
_dmg:
	@mkdir -p "$(OUTPUT_DIR)"
	@rm -rf "$(DMG_STAGING)"
	@mkdir -p "$(DMG_STAGING)"
	@echo "==> Preparing DMG contents…"
	@cp -R "$(RELEASE_APP)" "$(DMG_STAGING)/$(APP_NAME).app"
	@ln -s /Applications "$(DMG_STAGING)/Applications"
	@echo "==> Creating disk image $(DMG_NAME)…"
	@hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(DMG_STAGING)" \
		-ov \
		-format UDZO \
		-imagekey zlib-level=9 \
		"$(DMG_PATH)"
	@rm -rf "$(DMG_STAGING)"
	@echo "==> Disk image ready: $(DMG_PATH)"

# --- Clean -----------------------------------------------------------------
clean:
	@echo "==> Cleaning all build artifacts…"
	@rm -rf "$(BUILD_DIR)" "$(OUTPUT_DIR)"
	@echo "==> Clean complete."

clean-output:
	@rm -rf "$(OUTPUT_DIR)"


# Aural build commands. Run from the repository root.
#
#   make test                                    run AuralCore's unit tests
#   make probe URI=spotify:track:...             play a URI through Soloist and print events
#   make probe SOLOIST=~/path/to/soloist URI=... use a Soloist executable outside Aural's default location
#   make probe                                   only connect and print events
#   make app                                     generate the Xcode project and build Aural.app
#   make run                                     build and launch Aural.app
#   make install                                 build a Release Aural.app and copy it to /Applications
#
# Building the app needs only Xcode. XcodeGen (which generates the Xcode
# project from App/project.yml) is downloaded by the first build, at a pinned
# version checked against its SHA-256.

CORE := AuralCore
SOLOIST ?=
URI ?=

APP_DIR := App
DERIVED := DerivedData
APP := $(DERIVED)/Build/Products/Debug/Aural.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Aural.app
INSTALL_DIR ?= /Applications

# XcodeGen release from GitHub, pinned by version and checksum.
XCODEGEN_VERSION := 2.46.0
XCODEGEN_SHA256 := 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
XCODEGEN_DIR := .build/tools/xcodegen-$(XCODEGEN_VERSION)
XCODEGEN := $(XCODEGEN_DIR)/xcodegen/bin/xcodegen

.PHONY: test probe build app run release install check-xcode project

build:
	cd $(CORE) && swift build

test:
	cd $(CORE) && swift test

probe:
	cd $(CORE) && swift run aural-probe $(if $(SOLOIST),--soloist $(SOLOIST)) $(if $(URI),play $(URI))

# Stops early with one clear sentence instead of xcodebuild's errors.
check-xcode:
	@xcode-select -p 2>/dev/null | grep -q "\.app/Contents/Developer" || { \
		echo ""; \
		echo "Aural needs Xcode to build. Install Xcode from the App Store and open it once, then run:"; \
		echo "  sudo xcode-select -s /Applications/Xcode.app"; \
		echo ""; exit 1; }
	@xcodebuild -version >/dev/null 2>&1 || { \
		echo ""; \
		echo "Xcode is not ready yet. Open Xcode once, accept its license and let it finish installing, then try again."; \
		echo ""; exit 1; }

$(XCODEGEN):
	@echo "Downloading XcodeGen $(XCODEGEN_VERSION)…"
	@rm -rf "$(XCODEGEN_DIR)" && mkdir -p "$(XCODEGEN_DIR)"
	@curl -fsSL -o "$(XCODEGEN_DIR)/xcodegen.zip" \
		"https://github.com/yonaskolb/XcodeGen/releases/download/$(XCODEGEN_VERSION)/xcodegen.zip"
	@echo "$(XCODEGEN_SHA256)  $(XCODEGEN_DIR)/xcodegen.zip" | shasum -a 256 -c --quiet - || { \
		echo "XcodeGen download does not match its checksum; not using it."; rm -rf "$(XCODEGEN_DIR)"; exit 1; }
	@unzip -q "$(XCODEGEN_DIR)/xcodegen.zip" -d "$(XCODEGEN_DIR)"
	@rm "$(XCODEGEN_DIR)/xcodegen.zip"

project: check-xcode $(XCODEGEN)
	cd $(APP_DIR) && ../$(XCODEGEN) generate --quiet

app: project
	xcodebuild -project $(APP_DIR)/Aural.xcodeproj -scheme Aural -configuration Debug \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

run: app
	open $(APP)

# Optimized build, signed like Debug (ad hoc, or your Personal Team when
# App/Config/Local.xcconfig sets one; see Config/Base.xcconfig).
release: project
	xcodebuild -project $(APP_DIR)/Aural.xcodeproj -scheme Aural -configuration Release \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

# Quits a running Aural first (it stops its Soloist on quit), then replaces the
# installed copy. Afterwards Aural opens from Launchpad, Spotlight or the Dock.
install: release
	-osascript -e 'quit app "Aural"' 2>/dev/null
	rm -rf "$(INSTALL_DIR)/Aural.app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/Aural.app"
	@echo "Installed $(INSTALL_DIR)/Aural.app"

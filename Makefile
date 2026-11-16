# Aural build commands. Run from the repository root.
#
#   make test                                    run AuralCore's unit tests
#   make probe URI=spotify:track:...             play a URI through Soloist and print events
#   make probe SOLOIST=~/path/to/soloist URI=... use a Soloist executable outside Aural's default location
#   make probe                                   only connect and print events
#   make app                                     generate the Xcode project and build Aural.app
#   make run                                     build and launch Aural.app
#   make install                                 build a Release Aural.app and copy it to /Applications

CORE := AuralCore
SOLOIST ?=
URI ?=

APP_DIR := App
DERIVED := DerivedData
APP := $(DERIVED)/Build/Products/Debug/Aural.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Aural.app
INSTALL_DIR ?= /Applications

.PHONY: test probe build app run release install

build:
	cd $(CORE) && swift build

test:
	cd $(CORE) && swift test

probe:
	cd $(CORE) && swift run aural-probe $(if $(SOLOIST),--soloist $(SOLOIST)) $(if $(URI),play $(URI))

app:
	cd $(APP_DIR) && xcodegen generate --quiet
	xcodebuild -project $(APP_DIR)/Aural.xcodeproj -scheme Aural -configuration Debug \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

run: app
	open $(APP)

# Optimized build, signed with the same Personal Team as Debug, so the Keychain
# entries (API key, Web API tokens) stay readable without prompts.
release:
	cd $(APP_DIR) && xcodegen generate --quiet
	xcodebuild -project $(APP_DIR)/Aural.xcodeproj -scheme Aural -configuration Release \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build

# Quits a running Aural first (it stops its Soloist on quit), then replaces the
# installed copy. Afterwards Aural opens from Launchpad, Spotlight or the Dock.
install: release
	-osascript -e 'quit app "Aural"' 2>/dev/null
	rm -rf "$(INSTALL_DIR)/Aural.app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/Aural.app"
	@echo "Installed $(INSTALL_DIR)/Aural.app"

# Aural build commands. Run from the repository root.
#
#   make test                                    run AuralCore's unit tests
#   make probe URI=spotify:track:...             play a URI through Soloist and print events
#   make probe SOLOIST=~/path/to/soloist URI=... use a Soloist executable outside Aural's default location
#   make probe                                   only connect and print events
#   make app                                     generate the Xcode project and build Aural.app
#   make run                                     build and launch Aural.app

CORE := AuralCore
SOLOIST ?=
URI ?=

APP_DIR := App
DERIVED := DerivedData
APP := $(DERIVED)/Build/Products/Debug/Aural.app

.PHONY: test probe build app run

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

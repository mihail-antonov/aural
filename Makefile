# Aural build commands. Run from the repository root.
#
#   make test                                    run AuralCore's unit tests
#   make probe URI=spotify:track:...             play a URI through Soloist and print events
#   make probe SOLOIST=~/path/to/soloist URI=... use a Soloist executable outside Aural's default location
#   make probe                                   only connect and print events

CORE := AuralCore
SOLOIST ?=
URI ?=

.PHONY: test probe build

build:
	cd $(CORE) && swift build

test:
	cd $(CORE) && swift test

probe:
	cd $(CORE) && swift run aural-probe $(if $(SOLOIST),--soloist $(SOLOIST)) $(if $(URI),play $(URI))

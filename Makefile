# Cendatur — everything builds through xcodebuild into Xcode's own
# DerivedData (the same product ⌘R makes; no side copies).
#
#   make          build the app (Release) and print the product's path
#   make test     run the unit tests
#   make probe    build + run the driver bring-up tool against the scanner
#                 (needs the scanner free — quit Cendatur first)
#   make clean    xcodebuild clean

PROJECT := Cendatur.xcodeproj

.PHONY: all app test probe clean

all: app

app:
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme Cendatur \
		-configuration Release build 2>&1 | grep -E "^\*\*|error:"
	@echo "App: $$(xcodebuild -project $(PROJECT) -scheme Cendatur \
		-configuration Release -showBuildSettings 2>/dev/null \
		| awk '/ BUILT_PRODUCTS_DIR =/{print $$3}')/Cendatur.app"

test:
	xcodebuild -project $(PROJECT) -scheme Cendatur test

probe:
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme DriverProbe \
		-configuration Release build 2>&1 | grep -E "^\*\*|error:"
	"$$(xcodebuild -project $(PROJECT) -scheme DriverProbe \
		-configuration Release -showBuildSettings 2>/dev/null \
		| awk '/ BUILT_PRODUCTS_DIR =/{print $$3}')/DriverProbe"

clean:
	xcodebuild -project $(PROJECT) -scheme Cendatur clean
	xcodebuild -project $(PROJECT) -scheme DriverProbe clean

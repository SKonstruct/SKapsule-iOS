SHELL := /bin/bash
.SHELLFLAGS = -ec
$(VERBOSE).SILENT:

SOURCEDIR   := $(shell printf "%q\n" "$(shell pwd)")
OUTPUTDIR   := $(SOURCEDIR)/artifacts
WORKINGDIR  := $(SOURCEDIR)/Natives/build
VERSION     := 0.1.0
BRANCH      := $(shell git branch --show-current 2>/dev/null || echo unknown)
COMMIT      := $(shell git log --oneline -1 2>/dev/null | cut -b 1-7 || echo unknown)

RELEASE ?= 0
TROLLSTORE_JIT_ENT ?= 0

ifeq (,$(BRANCH))
BRANCH := unknown
endif

ifeq (1,$(RELEASE))
CMAKE_BUILD_TYPE := Release
else
CMAKE_BUILD_TYPE := Debug
endif

SDKPATH ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
JOBS    ?= $(shell sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

ifndef SDKPATH
$(error SDKPATH not set. Install Xcode and the iOS SDK.)
endif

# Convenience for checking directories
METHOD_DIRCHECK = \
	if [ ! -d '$(1)' ]; then \
		mkdir -p $(1); \
	else \
		rm -rf $(1)/*; \
	fi

# Package the IPA
METHOD_PACKAGE = \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		IPA_SUFFIX="-trollstore.tipa"; \
	else \
		IPA_SUFFIX=".ipa"; \
	fi; \
	cd $(OUTPUTDIR); \
	zip --symlinks -r $(OUTPUTDIR)/com.skonstruct.skapsule-$(VERSION)$$IPA_SUFFIX Payload

all: clean native payload package

help:
	echo 'SKapsule-iOS Makefile'
	echo ''
	echo 'Usage:'
	echo '    make                  Build everything'
	echo '    make native           Build the native app'
	echo '    make payload          Assemble SKapsule.app'
	echo '    make package          Create .ipa/.tipa'
	echo '    make clean            Clean build dirs'
	echo '    make check            Dump variables'
	echo ''
	echo 'Variables:'
	echo '    RELEASE=1             Release build'
	echo '    TROLLSTORE_JIT_ENT=1  TrollStore entitlements'
	echo '    VERBOSE=1             Print commands'

check:
	echo "SOURCEDIR  = $(SOURCEDIR)"
	echo "SDKPATH    = $(SDKPATH)"
	echo "BRANCH     = $(BRANCH)"
	echo "COMMIT     = $(COMMIT)"
	echo "BUILD_TYPE = $(CMAKE_BUILD_TYPE)"
	echo "JOBS       = $(JOBS)"

native:
	echo '[SKapsule v$(VERSION)] native - start'
	mkdir -p $(WORKINGDIR)
	cd $(WORKINGDIR) && cmake \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCONFIG_BRANCH="$(BRANCH)" \
		-DCONFIG_COMMIT="$(COMMIT)" \
		-DCONFIG_RELEASE=$(RELEASE) \
		..
	cmake --build $(WORKINGDIR) --config $(CMAKE_BUILD_TYPE) -j$(JOBS)
	rm -f $(WORKINGDIR)/libawt_headless.dylib
	echo '[SKapsule v$(VERSION)] native - end'

payload: native
	echo '[SKapsule v$(VERSION)] payload - start'
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/Frameworks)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/libs)
	# Copy Info.plist
	cp $(SOURCEDIR)/Natives/Info.plist $(WORKINGDIR)/SKapsule.app/
	# Copy native dylibs
	-cp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/SKapsule.app/Frameworks/ 2>/dev/null
	# Stage into output
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/Payload)
	cp -R $(WORKINGDIR)/SKapsule.app $(OUTPUTDIR)/Payload/
	# Sign with ldid
	ldid -S $(OUTPUTDIR)/Payload/SKapsule.app
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(OUTPUTDIR)/Payload/SKapsule.app/SKapsule; \
	else \
		ldid -S$(SOURCEDIR)/entitlements.sideload.xml $(OUTPUTDIR)/Payload/SKapsule.app/SKapsule; \
	fi
	chmod -R 755 $(OUTPUTDIR)/Payload
	echo '[SKapsule v$(VERSION)] payload - end'

package: payload
	echo '[SKapsule v$(VERSION)] package - start'
	$(call METHOD_PACKAGE)
	echo '[SKapsule v$(VERSION)] package - end'

clean:
	echo '[SKapsule v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)
	rm -rf $(OUTPUTDIR)
	echo '[SKapsule v$(VERSION)] clean - end'

.PHONY: all clean check native payload package help

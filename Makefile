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
DEVICE_ID ?= 72FB4F78-56C5-592F-951B-58275C0F82AC

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

# Function to download and unpack Java runtimes.
METHOD_JAVA_UNPACK = \
	cd $(SOURCEDIR)/depends; \
	if [ ! -f "java-$(1)-openjdk/release" ] && [ -z "$$(ls jre$(1)-*.tar.xz 2>/dev/null)" ]; then \
		wget '$(2)' -q --show-progress; \
		unzip jre$(1)-ios-aarch64.zip && rm jre$(1)-ios-aarch64.zip; \
		mkdir -p java-$(1)-openjdk; \
		tar xvf jre$(1)-*.tar.xz -C java-$(1)-openjdk; \
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
	echo '    make jre              Download and unpack JRE'
	echo '    make payload          Assemble SKapsule.app'
	echo '    make package          Create .ipa/.tipa'
	echo '    make clean            Clean build dirs'
	echo '    make deploy           Install to device'
	echo '    make check            Dump variables'
	echo ''
	echo 'Variables:'
	echo '    RELEASE=1             Release build'
	echo '    TROLLSTORE_JIT_ENT=1  TrollStore entitlements'
	echo '    DEVICE_ID=...         Target device UDID'
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

jre: native
	echo '[SKapsule v$(VERSION)] jre - start'
	mkdir -p $(SOURCEDIR)/depends
	cd $(SOURCEDIR)/depends; \
	$(call METHOD_JAVA_UNPACK,21,'https://crystall1ne.dev/cdn/amethyst-ios/jre21-ios-aarch64.zip'); \
	if [ -n "$$(ls jre*.tar.xz 2>/dev/null)" ]; then rm $(SOURCEDIR)/depends/jre*.tar.xz; fi; \
	cd $(SOURCEDIR); \
	rm -rf $(SOURCEDIR)/depends/java-21-openjdk/{ASSEMBLY_EXCEPTION,bin,include,jre,legal,LICENSE,man,THIRD_PARTY_README,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}} 2>/dev/null || true; \
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/jre21); \
	cp -R $(SOURCEDIR)/depends/java-21-openjdk/* $(WORKINGDIR)/SKapsule.app/jre21/ 2>/dev/null || true; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(WORKINGDIR)/SKapsule.app/jre21/lib/ 2>/dev/null || true
	echo '[SKapsule v$(VERSION)] jre - end'

payload: jre
	echo '[SKapsule v$(VERSION)] payload - start'
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/Frameworks)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/libs)
	# Compile Assets
	xcrun actool $(SOURCEDIR)/Natives/Assets.xcassets \
		--compile $(WORKINGDIR)/SKapsule.app \
		--platform iphoneos \
		--minimum-deployment-target 14.0 \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null
	# Copy Info.plist
	cp $(SOURCEDIR)/Natives/Info.plist $(WORKINGDIR)/SKapsule.app/
	# Copy native dylibs
	-cp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/SKapsule.app/Frameworks/ 2>/dev/null
	# Stage assets (jars and submodules)
	$(SOURCEDIR)/scripts/stage-app-assets.sh
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

# Special target for Xcode POST_BUILD hook (skips native compilation)
xcode-payload:
	echo '[SKapsule v$(VERSION)] xcode-payload - start'
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/Frameworks)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/libs)
	# Stage JRE
	mkdir -p $(SOURCEDIR)/depends
	cd $(SOURCEDIR)/depends; \
	$(call METHOD_JAVA_UNPACK,21,'https://crystall1ne.dev/cdn/amethyst-ios/jre21-ios-aarch64.zip'); \
	if [ -n "$$(ls jre*.tar.xz 2>/dev/null)" ]; then rm $(SOURCEDIR)/depends/jre*.tar.xz; fi; \
	cd $(SOURCEDIR); \
	rm -rf $(SOURCEDIR)/depends/java-21-openjdk/{ASSEMBLY_EXCEPTION,bin,include,jre,legal,LICENSE,man,THIRD_PARTY_README,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}} 2>/dev/null || true; \
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/jre21); \
	cp -R $(SOURCEDIR)/depends/java-21-openjdk/* $(WORKINGDIR)/SKapsule.app/jre21/ 2>/dev/null || true
	# Copy Xcode-built native dylibs
	cp $(WORKINGDIR)/awt_xawt.dylib $(WORKINGDIR)/SKapsule.app/jre21/lib/libawt_xawt.dylib 2>/dev/null || true
	cp $(WORKINGDIR)/awt_headless.dylib $(WORKINGDIR)/SKapsule.app/jre21/lib/libawt_headless.dylib 2>/dev/null || true
	# Stage assets (jars and submodules)
	APP_DIR="$(WORKINGDIR)/SKapsule.app" $(SOURCEDIR)/scripts/stage-app-assets.sh
	# Codesign all dylibs using Xcode's identity (if running inside Xcode build phase)
	if [ -n "$${EXPANDED_CODE_SIGN_IDENTITY}" ]; then \
		echo "[SKapsule] Signing dylibs with EXPANDED_CODE_SIGN_IDENTITY: $${EXPANDED_CODE_SIGN_IDENTITY}"; \
		find $(WORKINGDIR)/SKapsule.app -type f -name "*.dylib" -exec /usr/bin/codesign --force --sign "$${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none {} + ; \
	elif [ -n "$${CODE_SIGN_IDENTITY}" ]; then \
		echo "[SKapsule] Signing dylibs with CODE_SIGN_IDENTITY: $${CODE_SIGN_IDENTITY}"; \
		find $(WORKINGDIR)/SKapsule.app -type f -name "*.dylib" -exec /usr/bin/codesign --force --sign "$${CODE_SIGN_IDENTITY}" --timestamp=none {} + ; \
	fi
	echo '[SKapsule v$(VERSION)] xcode-payload - end'

# Build using Xcode so that it properly codesigns, dropping the result in artifacts/Payload
xcode-build:
	echo '[SKapsule v$(VERSION)] xcode-build - start'
	xcrun xcodebuild -project SKapsule.xcodeproj -scheme SKapsule -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates CONFIGURATION_BUILD_DIR="$(OUTPUTDIR)/Payload" build
	echo '[SKapsule v$(VERSION)] xcode-build - end'

package: payload
	echo '[SKapsule v$(VERSION)] package - start'
	$(call METHOD_PACKAGE)
	echo '[SKapsule v$(VERSION)] package - end'

deploy: xcode-build
	echo '[SKapsule v$(VERSION)] deploy - start'
	xcrun devicectl device install app --device $(DEVICE_ID) $(OUTPUTDIR)/Payload/SKapsule.app
	xcrun devicectl device process launch --device $(DEVICE_ID) com.skonstruct.dev.SKapsule
	echo '[SKapsule v$(VERSION)] deploy - end'

clean:
	echo '[SKapsule v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)
	rm -rf $(OUTPUTDIR)
	echo '[SKapsule v$(VERSION)] clean - end'

.PHONY: all clean check native payload package deploy help

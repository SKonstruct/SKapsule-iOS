SHELL := /bin/bash
.SHELLFLAGS = -ec
$(VERBOSE).SILENT:

SOURCEDIR   := $(shell printf "%q\n" "$(shell pwd)")
OUTPUTDIR   := $(SOURCEDIR)/out/artifacts
WORKINGDIR  := $(SOURCEDIR)/Natives/build
# Derives from the latest reachable git tag (v1.4.0 -> 1.4.0) so the build can't claim a
# version the releases never had. Override with SK_VERSION for CI / shallow clones.
SK_VERSION  ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq (,$(SK_VERSION))
SK_VERSION  := 1.0.0
endif
VERSION     := $(SK_VERSION)
# CFBundleVersion; CI passes its run number so every build orders after the last.
SK_BUILD    ?= 1

# Must match `application-identifier` in the entitlements ldid signs with; the
# payload step verifies that and fails the build if they ever drift apart.
BUNDLE_ID   := com.skonstruct.skapsule
DEPLOYMENT_TARGET := 17.4
BRANCH      := $(shell git branch --show-current 2>/dev/null || echo unknown)
COMMIT      := $(shell git log --oneline -1 2>/dev/null | cut -b 1-7 || echo unknown)

RELEASE ?= 0
TROLLSTORE_JIT_ENT ?= 0
DEVICE_ID ?=

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

# Function to unpack Java runtimes from assets.
METHOD_JAVA_UNPACK = \
	cd $(SOURCEDIR)/out; \
	if [ ! -f "jre$(1)/release" ]; then \
		echo "Unpacking JRE $(1) from assets..."; \
		unzip -q $(SOURCEDIR)/assets/jre$(1)-ios-aarch64.zip -d .; \
	fi

# Unpack JRE, build stub dylibs, trim, copy into .app. Used by both 'jre' and
# 'xcode-payload' targets.
#
# The layout is the stock JDK one, with no symlinks: java.home is jre25, natives and
# `modules` are in jre25/lib, conf in jre25/conf, libjvm in jre25/lib/server. Checked by
# running this exact libjvm on a Mac (libs retagged with vtool, JLI_Launch from a small C
# host, -XshowSettings:properties): java.home = jre25 and sun.boot.library.path = jre25/lib.
# Any other layout fails with "Failed setting boot class path." because the VM wants
# <java.home>/lib/modules. The links this once created (app-root lib/conf, server/lib,
# per-dylib links) were not needed for that, and signing services rewrite every symlink
# in a bundle as a small text file holding the link target, which broke the JRE.
METHOD_STAGE_JRE = \
	set -e; \
	mkdir -p $(SOURCEDIR)/out; \
	cd $(SOURCEDIR)/out; \
	$(call METHOD_JAVA_UNPACK,25); \
	if [ -d "jre25/lib/zero" ]; then mv jre25/lib/zero jre25/lib/server; fi; \
	if [ -f "jre25/lib/jvm.cfg" ]; then echo "-server KNOWN" > jre25/lib/jvm.cfg; fi; \
	if [ -n "$$(ls jre*.tar.xz 2>/dev/null)" ]; then rm $(SOURCEDIR)/out/jre*.tar.xz; fi; \
	cd $(SOURCEDIR); \
	echo "[SKapsule] Building libawt_headless.dylib stub..."; \
	xcrun -sdk iphoneos clang -shared -arch arm64 \
		-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) \
		-I$(SOURCEDIR)/out/jre25/include \
		-I$(SOURCEDIR)/out/jre25/include/darwin \
		-miphoneos-version-min=17.4 \
		-o $(WORKINGDIR)/libawt_headless.dylib \
		$(SOURCEDIR)/Natives/awt_stubs.c; \
	echo "[SKapsule] Building libprefs.dylib stub..."; \
	xcrun -sdk iphoneos clang -shared -arch arm64 \
		-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) \
		-I$(SOURCEDIR)/out/jre25/include \
		-I$(SOURCEDIR)/out/jre25/include/darwin \
		-miphoneos-version-min=17.4 \
		-o $(WORKINGDIR)/libprefs.dylib \
		$(SOURCEDIR)/Natives/prefs_stubs.c; \
	echo "[SKapsule] Building libawt_xawt.dylib stub..."; \
	xcrun -sdk iphoneos clang -shared -arch arm64 \
		-isysroot $$(xcrun --sdk iphoneos --show-sdk-path) \
		-miphoneos-version-min=17.4 \
		-o $(WORKINGDIR)/libawt_xawt.dylib \
		$(SOURCEDIR)/Natives/awt_xawt/xawt_fake.m; \
	rm -rf $(SOURCEDIR)/out/jre25/{bin,include,jre,man,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}}; \
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/jre25); \
	cp -R $(SOURCEDIR)/out/jre25/* $(WORKINGDIR)/SKapsule.app/jre25/; \
	cp $(WORKINGDIR)/libawt_headless.dylib $(WORKINGDIR)/SKapsule.app/jre25/lib/libawt_headless.dylib; \
	cp $(WORKINGDIR)/libprefs.dylib $(WORKINGDIR)/SKapsule.app/jre25/lib/libprefs.dylib; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(WORKINGDIR)/SKapsule.app/jre25/lib/libawt_xawt.dylib; \
	find $(WORKINGDIR)/SKapsule.app -type l -delete


# Built-in JIT helper (Natives/JITHelper): an app extension linking StikJIT, which attaches a
# debugger to SKapsule so StikDebug is not needed. A separate process because a process
# cannot debug itself. Only the extension links StikJIT. The framework sits in the app's Frameworks/, as Xcode lays out shared ones:
# ldid cannot sign a framework nested inside an extension inside the app.
METHOD_STAGE_JITHELPER = \
	[ -f $(SOURCEDIR)/out/stikjit/StikJIT.framework/Info.plist ] || $(SOURCEDIR)/scripts/build-stikjit-ios.sh; \
	X=$(1)/PlugIns/SKJITHelper.appex; \
	rm -rf $$X $(1)/Frameworks/StikJIT.framework; mkdir -p $$X; \
	xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.4 -O -module-name SKJITHelper -application-extension \
		-F $(SOURCEDIR)/out/stikjit -framework StikJIT \
		-Xlinker -e -Xlinker _NSExtensionMain -Xlinker -rpath -Xlinker @executable_path/../../Frameworks \
		$(SOURCEDIR)/Natives/JITHelper/SKJITHelper.swift -o $$X/SKJITHelper; \
	cp -R $(SOURCEDIR)/out/stikjit/StikJIT.framework $(1)/Frameworks/; \
	rm -rf $(1)/Frameworks/StikJIT.framework/Headers $(1)/Frameworks/StikJIT.framework/Modules; \
	cp $(SOURCEDIR)/Natives/JITHelper/Info.plist $$X/Info.plist; \
	plutil -replace CFBundleIdentifier -string '$(BUNDLE_ID).jithelper' $$X/Info.plist; \
	plutil -replace CFBundleShortVersionString -string '$(VERSION)' $$X/Info.plist; \
	plutil -replace CFBundleVersion -string '$(SK_BUILD)' $$X/Info.plist; \
	plutil -replace MinimumOSVersion -string 17.4 $$X/Info.plist; \
	plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' $$X/Info.plist; \
	plutil -replace UIDeviceFamily -json '[1,2]' $$X/Info.plist; \
	plutil -replace DTPlatformName -string iphoneos $$X/Info.plist

# Package the IPA
METHOD_PACKAGE = \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		IPA_SUFFIX="-trollstore.tipa"; \
	else \
		IPA_SUFFIX=".ipa"; \
	fi; \
	cd $(OUTPUTDIR); \
	if [ -n "$$(find Payload -type l)" ]; then \
		echo "ERROR: symlinks in the bundle; signing services rewrite them as plain files:" >&2; \
		find Payload -type l >&2; \
		exit 1; \
	fi; \
	rm -f $(OUTPUTDIR)/com.skonstruct.skapsule-$(VERSION)$$IPA_SUFFIX; \
	zip -r $(OUTPUTDIR)/com.skonstruct.skapsule-$(VERSION)$$IPA_SUFFIX Payload

all: clean native payload package

help:
	echo 'SKapsule-iOS Makefile'
	echo ''
	echo 'Usage:'
	echo '    make                  Build everything'
	echo '    make native           Build the native app'
	echo '    make test             Run the host-side unit tests'
	echo '    make jre              Download and unpack JRE'
	echo '    make payload          Assemble SKapsule.app'
	echo '    make package          Create .ipa/.tipa'
	echo '    make clean            Clean build dirs'
	echo '    make deploy           Install to device'
	echo '    make check            Dump variables'
	echo '    make format           Auto-format source files'
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

SK_ASAN ?= OFF

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
		-DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DSK_ASAN=$(SK_ASAN) \
		-DCONFIG_VERSION="$(VERSION)" \
		-DCONFIG_BRANCH="$(BRANCH)" \
		-DCONFIG_COMMIT="$(COMMIT)" \
		-DCONFIG_RELEASE=$(RELEASE) \
		..
	cmake --build $(WORKINGDIR) --config $(CMAKE_BUILD_TYPE) -j$(JOBS)
	echo '[SKapsule v$(VERSION)] native - end'

jre: native
	echo '[SKapsule v$(VERSION)] jre - start'
	$(call METHOD_STAGE_JRE)
	echo '[SKapsule v$(VERSION)] jre - end'

payload: jre
	echo '[SKapsule v$(VERSION)] payload - start'
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/Frameworks)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/libs)
	# Compile Assets
	xcrun actool $(SOURCEDIR)/Natives/Assets.xcassets \
		--compile $(WORKINGDIR)/SKapsule.app \
		--platform iphoneos \
		--minimum-deployment-target 17.4 \
		--app-icon AppIcon \
		--output-partial-info-plist $(WORKINGDIR)/actool-info.plist
	# Copy Info.plist, then fill in what Xcode would normally expand for us.
	# Natives/Info.plist is an Xcode *template*: shipped as-is it leaves
	# CFBundleIdentifier as the literal "$$(PRODUCT_BUNDLE_IDENTIFIER)" and omits
	# the keys installd requires, so the resulting .ipa cannot be re-signed or
	# installed -- which is exactly how it failed with a signing service.
	cp $(SOURCEDIR)/Natives/Info.plist $(WORKINGDIR)/SKapsule.app/
	for ent in entitlements.sideload.xml entitlements.trollstore.xml; do \
		ent_id=$$(plutil -extract application-identifier raw -o - $(SOURCEDIR)/$$ent); \
		if [ "$$ent_id" != "$(BUNDLE_ID)" ]; then \
			echo "ERROR: BUNDLE_ID '$(BUNDLE_ID)' != $$ent application-identifier ($$ent_id)" >&2; \
			exit 1; \
		fi; \
	done
	# The icon entries actool computed (CFBundleIcons, CFBundleIcons~ipad). Without them the
	# icon files and Assets.car are in the bundle but nothing points at them, and the app
	# installs with the generic icon. Xcode does this merge itself.
	for k in CFBundleIcons CFBundleIcons~ipad; do \
		plutil -extract "$$k" json -o - $(WORKINGDIR)/actool-info.plist | \
			xargs -0 -I{} plutil -replace "$$k" -json '{}' $(WORKINGDIR)/SKapsule.app/Info.plist || exit 1; \
	done
	plutil -replace CFBundleIdentifier -string '$(BUNDLE_ID)' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace CFBundleShortVersionString -string '$(VERSION)' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace CFBundleVersion -string '$(SK_BUILD)' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace SKBuildStamp -string "$$(date '+%Y-%m-%d %H:%M:%S')" $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace MinimumOSVersion -string '$(DEPLOYMENT_TARGET)' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace UIDeviceFamily -json '[1,2]' $(WORKINGDIR)/SKapsule.app/Info.plist
	plutil -replace DTPlatformName -string 'iphoneos' $(WORKINGDIR)/SKapsule.app/Info.plist
	# Copy native dylibs
	-cp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/SKapsule.app/Frameworks/ 2>/dev/null
	# Stage assets (jars and submodules)
	$(SOURCEDIR)/scripts/stage-app-assets.sh
	# Built-in JIT helper extension
	$(call METHOD_STAGE_JITHELPER,$(WORKINGDIR)/SKapsule.app)
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
	# Clear only stale dylibs: Xcode has already embedded StikJIT.framework here by now.
	mkdir -p $(WORKINGDIR)/SKapsule.app/Frameworks
	find $(WORKINGDIR)/SKapsule.app/Frameworks -maxdepth 1 -name '*.dylib' -delete
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/SKapsule.app/libs)
	# Stage JRE
	$(call METHOD_STAGE_JRE)
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

# Build using Xcode so that it properly codesigns, dropping the result in out/artifacts/Payload
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
	test -n '$(DEVICE_ID)' || { echo 'Set DEVICE_ID=<device UDID>'; exit 1; }
	xcrun devicectl device install app --device $(DEVICE_ID) $(OUTPUTDIR)/Payload/SKapsule.app
	xcrun devicectl device process launch --device $(DEVICE_ID) com.skonstruct.dev.SKapsule
	echo '[SKapsule v$(VERSION)] deploy - end'

format:
	echo '[SKapsule v$(VERSION)] format - start'
	./scripts/format.sh
	echo '[SKapsule v$(VERSION)] format - end'

clean:
	echo '[SKapsule v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)
	rm -rf $(OUTPUTDIR)
	rm -rf $(SOURCEDIR)/out/jre25
	echo '[SKapsule v$(VERSION)] clean - end'

# Host-side tests of the logic that parses third-party input; they build for and run on the Mac.
test:
	echo '[SKapsule v$(VERSION)] test - start'
	mkdir -p $(WORKINGDIR)
	xcrun clang -fobjc-arc -Wall -framework Foundation -lz -I$(SOURCEDIR)/Natives \
		$(SOURCEDIR)/Natives/Tests/SKZipUtilsTests.m $(SOURCEDIR)/Natives/SKZipUtils.m -o $(WORKINGDIR)/sk-tests
	$(WORKINGDIR)/sk-tests
	xcrun clang -fobjc-arc -Wall -framework Foundation -I$(SOURCEDIR)/Natives \
		$(SOURCEDIR)/Natives/Tests/SKMouseButtonsTests.m -o $(WORKINGDIR)/sk-mouse-tests
	$(WORKINGDIR)/sk-mouse-tests
	echo '[SKapsule v$(VERSION)] test - end'

.PHONY: all clean check native test payload package deploy help format

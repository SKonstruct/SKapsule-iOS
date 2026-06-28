#!/bin/bash
set -e

# Build OpenJDK 25 for iOS arm64 using SKonstruct/openjdk-mobile

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT_DIR="$ROOT/out/jre25-build"
JRE_DEST="$ROOT/out/jre25"
ZIP_DEST="$ROOT/assets/jre25-ios-aarch64.zip"
MOBILE_REPO="$ROOT/../openjdk-mobile"

if [ -f "$ZIP_DEST" ]; then
    echo "JRE 25 ZIP ($ZIP_DEST) already exists. Skipping build."
    exit 0
fi

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

if [ ! -d "mobile" ]; then
    echo "Copying openjdk/mobile..."
    cp -R "$MOBILE_REPO/" mobile
fi

# We need libffi built for iOS. We can borrow it from the lwjgl3 submodule build.
LIBFFI_DIR="$ROOT/external/lwjgl3/libffi/build/Release-iphoneos"
if [ ! -f "$LIBFFI_DIR/libffi.a" ]; then
    echo "Error: libffi.a not found in lwjgl3. Please run scripts/build-lwjgl3-ios.sh first."
    exit 1
fi
LIBFFI_INC="$ROOT/external/lwjgl3/libffi/build_iphoneos-arm64/include"

# We need CUPS headers for the build to succeed.
if [ ! -d "cups-2.3.3" ]; then
    echo "Downloading CUPS headers..."
    curl -sL "https://github.com/apple/cups/releases/download/v2.3.3/cups-2.3.3-source.tar.gz" | tar xz
fi

# Find boot JDK
BOOT_JDK=""

check_jdk_version() {
    local jdk_path="$1"
    if [ -x "$jdk_path/bin/javac" ]; then
        local ver=$("$jdk_path/bin/javac" -version 2>&1)
        if [[ "$ver" == *"javac 26"* ]] || [[ "$ver" == *"javac 27"* ]] || [[ "$ver" == *"javac 28"* ]]; then
            return 0
        fi
    fi
    return 1
}

if command -v jenv >/dev/null 2>&1; then
    TEMP_JDK=$(jenv prefix)
    if check_jdk_version "$TEMP_JDK"; then
        BOOT_JDK="$TEMP_JDK"
        echo "Using Boot JDK from jenv: $BOOT_JDK"
    else
        echo "Boot JDK from jenv is not version 26, 27, or 28. Ignoring."
    fi
fi

if [ -z "$BOOT_JDK" ] && [ -n "$JAVA_HOME" ]; then
    if check_jdk_version "$JAVA_HOME"; then
        BOOT_JDK="$JAVA_HOME"
        echo "Using Boot JDK from JAVA_HOME: $BOOT_JDK"
    else
        echo "Boot JDK from JAVA_HOME is not version 26, 27, or 28. Ignoring."
    fi
fi

if [ -z "$BOOT_JDK" ]; then
    # Force boot JDK to use downloaded JDK 27 EA 24 as fallback
    if [ ! -d "jdk-27.jdk" ] || [ ! -x "jdk-27.jdk/Contents/Home/bin/javac" ]; then
        echo "Downloading Boot JDK 27..."
        rm -rf "jdk-27.jdk"
        if ! curl -sL "https://download.java.net/java/early_access/jdk27/24/GPL/openjdk-27-ea+24_macos-aarch64_bin.tar.gz" | tar xz; then
            echo "Error: Failed to download or extract Boot JDK 27."
            rm -rf "jdk-27.jdk"
            exit 1
        fi
    fi
    BOOT_JDK="$OUT_DIR/jdk-27.jdk/Contents/Home"
fi

if [ ! -d "$BOOT_JDK" ]; then
    echo "Could not find Boot JDK in $BOOT_JDK"
    exit 1
fi

echo "Using BOOT_JDK=$BOOT_JDK"

echo "Configuring OpenJDK for iOS (aarch64-macos-ios)..."
cd mobile

bash configure \
    --openjdk-target=aarch64-macos-ios \
    --with-sysroot=$(xcrun --sdk iphoneos --show-sdk-path) \
    --with-libffi-include="$LIBFFI_INC" \
    --with-libffi-lib="$LIBFFI_DIR" \
    --with-cups-include="$OUT_DIR/cups-2.3.3" \
    --with-boot-jdk="$BOOT_JDK" \
    --disable-warnings-as-errors \
    --with-native-debug-symbols=none

echo "Building JDK images..."
make clean
make images

echo "Creating JRE..."
JDK_IMAGE=$(find build -type d -name "jdk" | grep images | head -1)

if [ -z "$JDK_IMAGE" ] || [ ! -d "$JDK_IMAGE" ]; then
    echo "Error: Could not find built JDK image."
    exit 1
fi

rm -rf "$JRE_DEST"
cp -R "$JDK_IMAGE" "$JRE_DEST"

# Strip unnecessary JDK tools to save space
rm -rf "$JRE_DEST/bin"/*
rm -rf "$JRE_DEST/lib/src.zip"
rm -rf "$JRE_DEST/demo" 2>/dev/null || true
rm -rf "$JRE_DEST/man" 2>/dev/null || true

echo "Zipping JRE 25..."
mkdir -p "$ROOT/Natives/resources"
cd "$ROOT/out"
rm -f "$ZIP_DEST"
zip -r9 "$ZIP_DEST" jre25/ > /dev/null

echo "JRE 25 built and staged at $ZIP_DEST"

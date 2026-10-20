#!/usr/bin/env bash

# Code formatting script for SKapsule-iOS.
# Formats:
# - C/Objective-C (.h, .m, .c) via clang-format
# - Shell scripts (.sh) via shfmt
# - Markdown, JSON, YAML (.md, .json, .yml, .yaml) via prettier
# Excludes the external/ directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "=== Auto-formatting SKapsule-iOS ==="

# 1. Format C and Objective-C files
echo "Formatting C/Objective-C files..."
# Find C/Objective-C files excluding build and external dirs
C_FILES=$(find Natives -type f \( -name "*.h" -o -name "*.m" -o -name "*.c" \) \
    -not -path "*/build/*" \
    -not -path "*/build_xcode/*" \
    -not -path "*/external/*" \
    2> /dev/null || true)

if [[ -n "$C_FILES" ]]; then
    # Run clang-format in-place using npx
    npx clang-format -i $C_FILES
    echo "Objective-C/C files formatted successfully."
else
    echo "No Objective-C/C files found to format."
fi

# 2. Format Shell Scripts
echo "Formatting shell scripts..."
# Find shell scripts excluding build, out, external, and internal build dirs
SH_FILES=$(find . -type f -name "*.sh" \
    -not -path "*/external/*" \
    -not -path "*/out/*" \
    -not -path "*/build/*" \
    -not -path "*/Natives/build/*" \
    -not -path "*/Natives/build_xcode/*" \
    2> /dev/null || true)

if [[ -n "$SH_FILES" ]]; then
    if ! command -v shfmt &> /dev/null; then
        if command -v brew &> /dev/null; then
            echo "shfmt not found. Installing via Homebrew..."
            brew install shfmt
        else
            echo "Warning: shfmt not found and brew is not available. Skipping shell script formatting."
            echo "Please install shfmt manually: 'brew install shfmt' or 'go install mvdan.cc/sh/v3/cmd/shfmt@latest'"
            SH_FILES=""
        fi
    fi

    if [[ -n "$SH_FILES" ]]; then
        shfmt -w $SH_FILES
        echo "Shell scripts formatted successfully."
    fi
else
    echo "No shell scripts found to format."
fi

# 3. Format Markdown, YAML, and JSON files using Prettier
echo "Formatting Markdown, YAML, and JSON files..."
npx prettier --write .

echo "=== Formatting complete ==="

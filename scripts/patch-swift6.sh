#!/bin/bash
# Patch UniFFI-generated Swift code for Swift 6 strict concurrency compatibility
# This script adds `nonisolated` keywords to pure/synchronous FFI functions
# since UniFFI doesn't yet support Swift 6 concurrency (tracked in issue #2448)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-swift-file>"
    exit 1
fi

SWIFT_FILE="$1"

if [ ! -f "$SWIFT_FILE" ]; then
    echo "Error: File not found: $SWIFT_FILE"
    exit 1
fi

echo "Patching $SWIFT_FILE for Swift 6 compatibility..."

# Create a temporary file for the patched content
TEMP_FILE=$(mktemp)

# Use sed to apply patches
# Note: Using -E for extended regex on macOS

sed -E '
# Patch internal rustCall function
s/^(private func rustCall<)/private nonisolated func rustCall</

# Patch internal rustCallWithError function
s/^(private func rustCallWithError<)/private nonisolated func rustCallWithError</

# Patch internal makeRustCall function
s/^(private func makeRustCall<)/private nonisolated func makeRustCall</

# Patch uniffiCheckCallStatus function
s/^(private func uniffiCheckCallStatus)/private nonisolated func uniffiCheckCallStatus/

# Patch uniffiEnsureInitialized function
s/^(private func uniffiEnsureInitialized)/private nonisolated func uniffiEnsureInitialized/

# Patch initializationResult global variable
s/^(private var initializationResult)/nonisolated(unsafe) private var initializationResult/

# Patch ALL public functions (that do not already have nonisolated)
s/^(public func )/public nonisolated func /

# Patch LocalizedError extension errorDescription
s/(public var errorDescription)/public nonisolated var errorDescription/

' "$SWIFT_FILE" > "$TEMP_FILE"

# Replace original file with patched version
mv "$TEMP_FILE" "$SWIFT_FILE"

echo "Swift 6 patches applied successfully."

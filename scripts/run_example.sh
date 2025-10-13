#!/bin/bash

# Define script and project directory locations.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd -P)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)

# Define the source directories and packages in arrays.
SOURCE_DIRECTORIES=(
    "$PROJECT_DIR/example"
)

# Join the array elements with a comma.
DIRS_STR=$(IFS=,; echo "${SOURCE_DIRECTORIES[*]}")

# Run the dart command with the provided specifications.
dart run bin/obfuscator.dart --src="$DIRS_STR" --out="$PROJECT_DIR/out"
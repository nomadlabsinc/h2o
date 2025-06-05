#!/usr/bin/env bash

# Pre-commit auto-formatter for H2O Crystal project
# Automatically fixes formatting issues on committed files

set -e

# Set locale to avoid encoding issues
export LC_ALL=C

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

echo "🔧 Auto-formatting staged files..."

# 1. Auto-format Crystal files
CRYSTAL_FILES=$(echo "$STAGED_FILES" | grep '\.cr$' || true)
if [ -n "$CRYSTAL_FILES" ]; then
    crystal tool format > /dev/null 2>&1
    # Re-add formatted files to staging area
    for file in $CRYSTAL_FILES; do
        if [ -f "$file" ]; then
            git add "$file"
        fi
    done
fi

# 2. Auto-fix trailing newlines on ALL staged files
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        # Add trailing newline if missing
        if [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
            echo >> "$file"
            git add "$file"
        fi
    fi
done

# 3. Auto-fix trailing whitespace on ALL staged files
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        # Remove trailing whitespace
        if grep -q '[ 	]$' "$file"; then
            sed -i '' 's/[ 	]*$//' "$file"
            git add "$file"
        fi
    fi
done

echo "✅ Formatting complete"


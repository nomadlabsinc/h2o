#!/usr/bin/env bash

# Pre-commit checks script for H2O Crystal project
# Ensures code quality standards from CLAUDE.md are met

set -e

echo "🔍 Running pre-commit checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track if any checks fail
CHECKS_FAILED=0

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        CHECKS_FAILED=1
    fi
}

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${YELLOW}⚠${NC} No staged files found"
    exit 0
fi

echo "📁 Checking staged files..."

# 1. Crystal tool format
echo "1. Checking Crystal code formatting..."
crystal tool format --check > /dev/null 2>&1
print_status $? "Crystal code formatting"

# 2. Check trailing newlines
echo "2. Checking trailing newlines..."
MISSING_NEWLINES=""
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        # Check if file should have trailing newline (text files)
        case "$file" in
            *.cr|*.yml|*.yaml|*.md|*.txt|*.conf|*.sh|*.json)
                if [ "$(tail -c1 "$file" | wc -l)" -eq 0 ]; then
                    MISSING_NEWLINES="$MISSING_NEWLINES $file"
                fi
                ;;
        esac
    fi
done

if [ -n "$MISSING_NEWLINES" ]; then
    echo -e "${RED}✗${NC} Files missing trailing newlines:$MISSING_NEWLINES"
    echo "  Run: find . -name \"*.cr\" -o -name \"*.yml\" -o -name \"*.yaml\" -o -name \"*.md\" -o -name \"*.txt\" -o -name \"*.conf\" -o -name \"*.sh\" -o -name \"*.json\" | xargs -I {} sh -c 'tail -c1 \"\$1\" | read -r _ || echo >> \"\$1\"' _ {}"
    CHECKS_FAILED=1
else
    print_status 0 "All files have trailing newlines"
fi

# 3. Check trailing whitespace
echo "3. Checking trailing whitespace..."
TRAILING_WHITESPACE=""
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        case "$file" in
            *.cr|*.yml|*.yaml|*.md|*.txt|*.conf|*.sh|*.json)
                if grep -q '[[:space:]]$' "$file"; then
                    TRAILING_WHITESPACE="$TRAILING_WHITESPACE $file"
                fi
                ;;
        esac
    fi
done

if [ -n "$TRAILING_WHITESPACE" ]; then
    echo -e "${RED}✗${NC} Files with trailing whitespace:$TRAILING_WHITESPACE"
    echo "  Run: find . -name \"*.cr\" -type f -exec sed -i '' 's/[[:space:]]*\$//' {} +"
    CHECKS_FAILED=1
else
    print_status 0 "No trailing whitespace found"
fi

# 4. Run Crystal specs (if Crystal files are staged)
CRYSTAL_FILES=$(echo "$STAGED_FILES" | grep '\.cr$' || true)
if [ -n "$CRYSTAL_FILES" ]; then
    echo "4. Running Crystal specs..."
    crystal spec > /dev/null 2>&1
    print_status $? "Crystal specs"
else
    echo "4. Skipping Crystal specs (no .cr files staged)"
fi

# 5. Check Crystal syntax (if Crystal files are staged)
if [ -n "$CRYSTAL_FILES" ]; then
    echo "5. Checking Crystal syntax..."
    crystal build --no-codegen src/h2o.cr > /dev/null 2>&1
    print_status $? "Crystal syntax check"
else
    echo "5. Skipping Crystal syntax check (no .cr files staged)"
fi

# Summary
echo ""
if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All pre-commit checks passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some pre-commit checks failed!${NC}"
    echo ""
    echo "Please fix the issues above and try committing again."
    echo ""
    echo "Quick fixes:"
    echo "• Format Crystal code: crystal tool format"
    echo "• Fix trailing newlines: find . -name \"*.cr\" -o -name \"*.yml\" -o -name \"*.yaml\" -o -name \"*.md\" -o -name \"*.txt\" -o -name \"*.conf\" -o -name \"*.sh\" -o -name \"*.json\" | xargs -I {} sh -c 'tail -c1 \"\$1\" | read -r _ || echo >> \"\$1\"' _ {}"
    echo "• Remove trailing whitespace: find . -name \"*.cr\" -type f -exec sed -i '' 's/[[:space:]]*\$//' {} +"
    echo "• Run tests: crystal spec"
    exit 1
fi

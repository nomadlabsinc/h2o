#!/usr/bin/env bash

# Setup script for Git hooks in H2O Crystal project
# This script installs the pre-commit hook that enforces CLAUDE.md standards

set -e

echo "🔧 Setting up Git hooks for H2O Crystal project..."

# Get the root directory of the git repository
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Error: This script must be run from within a git repository"
    exit 1
fi

# Ensure hooks directory exists
mkdir -p "$ROOT_DIR/.git/hooks"

# Create the pre-commit hook
cat > "$ROOT_DIR/.git/hooks/pre-commit" << 'EOF'
#!/usr/bin/env bash

# Git pre-commit hook for H2O Crystal project
# Calls the pre-commit checks script

# Get the root directory of the git repository
ROOT_DIR=$(git rev-parse --show-toplevel)

# Run the pre-commit checks script
exec "$ROOT_DIR/scripts/pre-commit-checks.sh"
EOF

# Make the hook executable
chmod +x "$ROOT_DIR/.git/hooks/pre-commit"

echo "✅ Git pre-commit hook installed successfully!"
echo ""
echo "The hook will automatically run before each commit to ensure:"
echo "• Crystal code is properly formatted"
echo "• All files have trailing newlines"
echo "• No trailing whitespace exists"
echo "• Crystal specs pass"
echo "• Crystal syntax is valid"
echo ""
echo "To skip the hook for a specific commit (not recommended):"
echo "  git commit --no-verify"
echo ""
echo "To test the hook now:"
echo "  ./scripts/pre-commit-checks.sh"

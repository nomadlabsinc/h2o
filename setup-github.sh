#!/bin/bash

# H2O GitHub Repository Setup Script
# This script helps set up the h2o repository on GitHub with proper configuration

set -e  # Exit on any error

echo "🚀 H2O GitHub Repository Setup"
echo "================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "shard.yml" ] || [ ! -d "src/h2o" ]; then
    echo -e "${RED}Error: This script must be run from the h2o project root directory${NC}"
    exit 1
fi

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo -e "${RED}Error: Git repository not initialized${NC}"
    exit 1
fi

# Step 1: Add remote origin (you'll need to create the repo first)
echo -e "${BLUE}Step 1: Setting up GitHub remote${NC}"
echo "First, create the repository at: https://github.com/nomadlabsinc/h2o"
echo "Make sure to:"
echo "  - Set it as PRIVATE"
echo "  - Don't initialize with README, .gitignore, or license (we have them)"
echo ""
read -p "Press Enter after creating the GitHub repository..."

# Check if origin already exists
if git remote get-url origin >/dev/null 2>&1; then
    echo -e "${YELLOW}Remote 'origin' already exists. Updating URL...${NC}"
    git remote set-url origin https://github.com/nomadlabsinc/h2o.git
else
    echo -e "${GREEN}Adding remote origin...${NC}"
    git remote add origin https://github.com/nomadlabsinc/h2o.git
fi

# Step 2: Push to GitHub
echo -e "${BLUE}Step 2: Pushing to GitHub${NC}"
echo "Pushing main branch to GitHub..."
git push -u origin main

echo -e "${GREEN}✅ Successfully pushed to GitHub!${NC}"

# Step 3: Set up branch protection (requires gh CLI or manual setup)
echo -e "${BLUE}Step 3: Setting up branch protection${NC}"
if command -v gh &> /dev/null; then
    echo "Using GitHub CLI to set up branch protection..."
    
    # Enable branch protection for main
    gh api repos/nomadlabsinc/h2o/branches/main/protection \
        --method PUT \
        --field required_status_checks='{"strict":true,"contexts":["test","lint","build"]}' \
        --field enforce_admins=false \
        --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":false}' \
        --field restrictions=null \
        --field allow_force_pushes=false \
        --field allow_deletions=false
    
    echo -e "${GREEN}✅ Branch protection configured!${NC}"
else
    echo -e "${YELLOW}GitHub CLI not found. Please manually set up branch protection:${NC}"
    echo "1. Go to: https://github.com/nomadlabsinc/h2o/settings/branches"
    echo "2. Click 'Add rule'"
    echo "3. Branch name pattern: main"
    echo "4. Enable:"
    echo "   ✅ Require a pull request before merging"
    echo "   ✅ Require approvals (1)"
    echo "   ✅ Dismiss stale reviews"
    echo "   ✅ Require status checks to pass"
    echo "   ✅ Require branches to be up to date"
    echo "   ✅ Require conversation resolution"
    echo "   ✅ Do not allow bypassing the above settings"
    echo ""
    read -p "Press Enter after setting up branch protection..."
fi

# Step 4: Create development branch
echo -e "${BLUE}Step 4: Creating development branch${NC}"
git checkout -b develop
git push -u origin develop
git checkout main

echo -e "${GREEN}✅ Development branch created!${NC}"

# Step 5: Final verification
echo -e "${BLUE}Step 5: Final verification${NC}"
echo "Repository URL: https://github.com/nomadlabsinc/h2o"
echo "Branch protection: Check GitHub repository settings"
echo "CI/CD workflows: Should run automatically on push"

echo ""
echo -e "${GREEN}🎉 Repository setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. All future work should be done on feature branches"
echo "2. Create PRs to merge changes into main"
echo "3. Ensure all CI checks pass before merging"
echo "4. Get approval before merging PRs"

echo ""
echo "Example workflow for future changes:"
echo "  git checkout develop"
echo "  git checkout -b feature/new-feature"
echo "  # Make changes"
echo "  git add ."
echo "  git commit -m 'Add new feature'"
echo "  git push -u origin feature/new-feature"
echo "  # Create PR on GitHub"
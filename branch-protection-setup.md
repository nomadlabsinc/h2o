# Branch Protection Setup Instructions

Since the GitHub API for branch protection requires specific formatting, please set up branch protection manually:

## Steps to Configure Branch Protection

1. **Go to Repository Settings**
   - Navigate to: https://github.com/nomadlabsinc/h2o/settings/branches

2. **Add Branch Protection Rule**
   - Click "Add rule"
   - Branch name pattern: `main`

3. **Configure Protection Settings**
   Please enable the following options:

   ✅ **Require a pull request before merging**
   - Required approving reviews: 1
   - ✅ Dismiss stale pull request approvals when new commits are pushed
   - ✅ Require review from code owners (if you have CODEOWNERS file)

   ✅ **Require status checks to pass before merging**
   - ✅ Require branches to be up to date before merging
   - Status checks to require:
     - `test` (from CI workflow)
     - `lint` (from CI workflow) 
     - `build` (from CI workflow)

   ✅ **Require conversation resolution before merging**

   ✅ **Restrict pushes that create files larger than 100 MB**

   ❌ **Do not allow bypassing the above settings** (keep unchecked for admins)

4. **Additional Settings (Optional)**
   - ✅ Require linear history
   - ✅ Require deployments to succeed before merging (if you set up deployments)

5. **Save Changes**
   - Click "Create" to save the branch protection rule

## Verification

After setting up, verify that:
- Direct pushes to `main` are blocked
- Pull requests require approval
- CI checks must pass before merging
- Force pushes are prevented

## Workflow for Future Development

```bash
# Create feature branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/my-new-feature

# Make changes and commit
git add .
git commit -m "Add new feature"

# Push and create PR
git push -u origin feature/my-new-feature
gh pr create --base main --title "Add new feature" --body "Description of changes"
```

This ensures all changes go through proper review and CI validation before being merged into the main branch.
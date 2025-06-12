#!/bin/bash
set -euo pipefail

# Monitor CI Script
RUN_ID="${1:-}"
if [ -z "$RUN_ID" ]; then
    echo "Fetching latest run ID..."
    RUN_ID=$(gh run list --branch fix-pending-tests-with-maximum-parallelization --limit 1 --json databaseId --jq '.[0].databaseId')
fi

echo "Monitoring CI run: $RUN_ID"
echo "Press Ctrl+C to stop monitoring"
echo

while true; do
    clear
    echo "=== CI Status Monitor ==="
    echo "Run ID: $RUN_ID"
    echo "Time: $(date)"
    echo

    # Get run status
    gh run view "$RUN_ID" || true

    # Check if completed
    STATUS=$(gh run view "$RUN_ID" --json status --jq '.status' 2>/dev/null || echo "unknown")
    CONCLUSION=$(gh run view "$RUN_ID" --json conclusion --jq '.conclusion' 2>/dev/null || echo "pending")

    echo
    echo "Status: $STATUS"
    echo "Conclusion: $CONCLUSION"

    if [ "$STATUS" = "completed" ]; then
        echo
        if [ "$CONCLUSION" = "success" ]; then
            echo "✅ CI run completed successfully!"
        else
            echo "❌ CI run failed with conclusion: $CONCLUSION"
            echo
            echo "Failed jobs:"
            gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion != "success") | "\(.name): \(.conclusion)"'
        fi
        break
    fi

    sleep 10
done

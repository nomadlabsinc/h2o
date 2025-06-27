#!/bin/bash
set -e

# This script is for one-time use to update the test files.

# For every .cr file in the spec directory
find spec -type f -name "*.cr" | while read file; do
  # Replace client.get("...") with client.get(".../index.html")
  # but only if the URL is a simple path like "/" or "/get"
  sed -i '' -E 's|client.get\("([^"]*)/"\)|client.get("\1/index.html")|g' "$file"
  sed -i '' -E 's|client.get\("([^"]*)/get"\)|client.get("\1/index.html")|g' "$file"
done

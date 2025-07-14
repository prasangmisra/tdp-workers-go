#!/bin/bash

GIT_DIR=$(git rev-parse --git-dir)

echo "Installing hooks..."

# Set git hookspath
git config --local core.hooksPath "$GIT_DIR/hooks"

# Create symlink to pre-commit script
ln -s ../../scripts/pre-commit.bash "$GIT_DIR/hooks/pre-commit"

echo "Done!"

#!/bin/bash

GIT_DIR=$(git rev-parse --git-dir)

echo "Installing hooks..."

# Set git hooks path
git config --local core.hooksPath "$GIT_DIR/hooks"

# Create symlink to pre-commit script
ln -s ../../githooks/pre-commit.bash "$GIT_DIR/hooks/pre-commit"
ln -s ../../githooks/pre-push.bash "$GIT_DIR/hooks/pre-push"

echo "Done!"

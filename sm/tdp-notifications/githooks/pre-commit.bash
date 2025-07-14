#!/bin/bash

echo "Running pre-commit hook"

# Run gofmt to format the code
echo "Running gofmt"

count=0
for i in $(gofmt -s -w -l $(find . -type f -name '*.go' | grep -v "/sm/")); do
    echo "reformatted $i"
    ((count++))
    git add "$i" 
done

echo "All done! ✨ 🍰 ✨"
echo "$count files reformatted."

echo
exit 0

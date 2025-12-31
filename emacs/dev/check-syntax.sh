#!/bin/bash
# Quick syntax validation for Elisp files

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file.el> [file2.el ...]"
    exit 1
fi

errors=0

for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "❌ File not found: $file"
        errors=$((errors + 1))
        continue
    fi

    echo -n "Checking $file... "

    # Check parentheses balance
    if ! emacs --batch --eval "(with-temp-buffer (insert-file-contents \"$file\") (emacs-lisp-mode) (check-parens))" 2>&1 | grep -q "Unmatched"; then
        echo "✅ OK"
    else
        echo "❌ FAILED - Unmatched bracket or quote"
        errors=$((errors + 1))
    fi
done

if [ $errors -eq 0 ]; then
    echo ""
    echo "✅ All files passed syntax check"
    exit 0
else
    echo ""
    echo "❌ $errors file(s) failed syntax check"
    exit 1
fi

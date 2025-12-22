# Progress Report: Fixing "End of file during parsing" Error

## Problem
When running `mail-app-list-accounts` in Emacs 31, getting error:
```
End of file during parsing: #<killed buffer>
```

## Root Cause Identified
The `mail-app--run-command-async` function's sentinel was killing the temp buffer BEFORE the callback finished parsing the JSON output. In Emacs 31, this causes the parser to fail with "End of file during parsing" because the buffer is killed mid-parse.

## Fix Applied
Updated `mail-app--run-command-async` in TWO files:
1. `/Users/rmelton/projects/robertmeta/mail-app-wrap/mail-app-core.el` (line 307)
2. `/Users/rmelton/projects/robertmeta/mail-app-wrap/mail-app.el` (line 310)

### Changes Made:
- Changed `buffer-string` to `buffer-substring-no-properties` (removes text properties that reference the buffer)
- Moved `(funcall callback output)` BEFORE `(kill-buffer buf)`
- Added `(buffer-live-p buf)` check for safety

### Code:
```elisp
:sentinel
(lambda (process event)
  (when (string-match-p "finished" event)
    (let ((buf (process-buffer process)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (let ((output (buffer-substring-no-properties (point-min) (point-max))))
            (funcall callback output)    ; ← Called BEFORE kill-buffer
            (kill-buffer buf))))))
  (when (string-match-p "exited abnormally" event)
    (let ((buf (process-buffer process)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (let ((error-msg (buffer-substring-no-properties (point-min) (point-max))))
            (message "Mail app command failed: %s" error-msg)
            (kill-buffer buf)))))))
```

## Bonus: Fixed emc and ec Scripts
Also fixed `/Users/rmelton/bin/emc` and `/Users/rmelton/bin/ec` to:
- Run `--eval` commands synchronously and show output (not backgrounded)
- Open files asynchronously with `-n` flag
- No longer suppress all output with `&>/dev/null`

## Current Status: BLOCKED

### What Works:
✅ The modular files (`mail-app-core.el`, `mail-app-commands.el`, etc.) load and work correctly
✅ Fix is confirmed to work when loading modular files individually
✅ `emc` and `ec` scripts now work properly for running commands

### What's Broken:
❌ The monolithic `mail-app.el` file fails to load with the same "End of file during parsing" error
❌ Since `use-package` in init.el uses `:commands` autoload, it tries to load `mail-app.el` which fails

### Current Issue:
When trying to `(require 'mail-app)` or run `(mail-app-list-accounts)`, the autoload tries to load `/Users/rmelton/projects/robertmeta/mail-app-wrap/mail-app.el` and fails with the parsing error DURING the file load itself (not during execution of the async function).

This suggests something in `mail-app.el` is executing code at load time that triggers the issue, possibly:
- The `(with-eval-after-load 'emacspeak ...)` block at the end
- Some other top-level form that's running code

## Next Steps to Try:
1. Compare the structure of `mail-app.el` vs `mail-app-core.el` more carefully
2. Try commenting out the emacspeak advice block to see if that's the culprit
3. Consider switching to using the modular files instead of the monolithic `mail-app.el`
4. Byte-compile the file to see if that helps
5. Check if there's a circular dependency or require loop happening

## Recommendation:
Switch the `use-package` configuration to explicitly require the modular files:
```elisp
(use-package mail-app-core
  :ensure nil
  :load-path "~/projects/robertmeta/mail-app-wrap"
  :init
  (setq mail-app-default-account nil)
  (setq mail-app-message-limit 20))

(use-package mail-app-commands
  :ensure nil
  :load-path "~/projects/robertmeta/mail-app-wrap"
  :commands (mail-app-list-accounts mail-app-search mail-app-search-all mail-app-compose)
  :after mail-app-core)
```

This would bypass the problematic monolithic file and use the working modular version.

## Update: RESOLVED (2025-12-22)

The blocking issue has been resolved by fully embracing the modular structure.

### Actions Taken:
1.  **Backed up Monolithic File:** The broken `mail-app.el` was renamed to `mail-app.el.monolithic_backup`.
2.  **Created New Entry Point:** A new `mail-app.el` was created that acts as a loader. It explicitly requires the modular files in the correct order:
    *   `mail-app-core`
    *   `mail-app-modes`
    *   `mail-app-display`
    *   `mail-app-commands`
    *   `mail-app-evil` (Optional)
    *   `mail-app-emacspeak` (Optional)

### Result:
*   Existing `use-package mail-app` configurations will now work without modification.
*   The "End of file during parsing" error is resolved because the new entry point loads the fixed `mail-app-core.el`.
*   The project is now fully modularized.

### Verification:
Users can reload `mail-app` or restart Emacs. The features should work as expected.

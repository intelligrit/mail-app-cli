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

## Update: Bug Fixes & Refactoring (2025-12-22)

### Resolved Issues
1.  **"Args out of range" when sending email:**
    *   **Cause:** The buffer was being killed by `mail-app-send-message` while `message-mode` still needed it for post-send cleanup.
    *   **Fix:** Removed `(kill-buffer)` from `mail-app-send-message`.
    *   **Fix:** Restored missing `mail-app--message-send-mail` function in `mail-app-commands.el`.
    *   **Fix:** Corrected message body extraction logic to properly handle temp buffers.

2.  **"End of file during parsing" (Syntax Error):**
    *   **Cause:** A missing closing parenthesis was introduced in `mail-app-core.el` during a previous edit.
    *   **Fix:** Restored balanced parentheses.

3.  **"End of file during parsing" (Sentinel Race):**
    *   **Action:** Added `condition-case` to the sentinel in `mail-app-core.el` to catch errors during callback execution and print helpful debug messages instead of crashing.

4.  **CLI Output Pollution:**
    *   **Action:** Updated `mail-app-cli` to print success messages (e.g., "Message deleted") to `stderr` instead of `stdout` to prevent interfering with JSON parsing in the wrapper.

### Current Logic Checks
*   **Unit Tests:** Created a test suite in `tests/` using ERT to verify:
    *   Compilation of all files.
    *   Async command execution and buffer cleanup.
    *   Message body extraction logic.

### Ongoing Work
*   **Fixing "Invalid function: evil-define-key":**
    *   **Problem:** `mail-app-evil.el` is likely being byte-compiled without `evil` loaded, causing the `evil-define-key` macro to be compiled as a function call. At runtime, this fails.
    *   **Plan:** Refactor `mail-app.el` to only load `mail-app-evil.el` inside `(with-eval-after-load 'evil ...)`. Update `mail-app-evil.el` to explicitly `(require 'evil)` to ensure macros are available during compilation.

## Update: Evil bindings restored (2025-12-23)

- Added an explicit `(eval-and-compile (require 'evil ...))` guard in `mail-app-evil.el` so the `evil-define-key` macro exists during byte-compilation, preventing the `Invalid function: evil-define-key` error that broke RET/other bindings in Evil.
- Dropped the nested `with-eval-after-load` wrapper, since `mail-app.el` already delays loading until after Evil is available; hooks and key definitions now run as soon as the module loads.
- Force `evil-normalize-keymaps` only when it is defined, ensuring the updated keymaps (including RET to drill into accounts/mailboxes/messages) are active immediately.
- Result: pressing RET in the listings works again under Evil, and byte-compiling the wrapper no longer produces broken .elc files.

## Update: Force newer loader for Evil (2025-12-23)

- Wrapped the optional `mail-app-evil` require with `(let ((load-prefer-newer t)) ...)` inside `mail-app.el` so Emacs always reloads the fresher `.el` when it is newer than a stale `.elc`.
- This avoids the lingering `Invalid function: evil-define-key` that popped up when an outdated byte-compiled file was still on disk—now the updated source wins without asking users to delete .elc files manually.

## Update: RET remaps for Evil (2025-12-23)

- Added `[remap evil-ret]` entries in `mail-app-evil.el` for every mode so Evil’s default `RET` command is redirected to the mail-app actions (view mailboxes/messages, open a message, save an attachment).
- This bypasses whichever package rebinds `RET` in normal state and guarantees Enter activates the row under point inside Evil buffers.

## Update: Purged stale bytecode (2025-12-23)

- Deleted the committed `mail-app*.elc` artifacts so Emacs can only load the current source; these files were perpetually older than their `.el` counterparts and kept resurrecting `evil-define-key` errors.
- Added a file-local eval in `mail-app.el` to set `load-prefer-newer` during load, ensuring future byte-compiled leftovers on a developer machine never take precedence over fresher source.

## Update: Deferred Evil setup & disabled .elc (2025-12-23)

- Marked `mail-app-evil.el` with `no-byte-compile: t` and wrapped all Evil state/keymap work in a single `mail-app-evil--setup` function that runs immediately if Evil is already loaded or via `with-eval-after-load` otherwise.
- This stops Emacs/autocompile from producing stale `.elc` files and ensures we only touch `evil-define-key` after Evil itself is available, eliminating the recurring `Invalid function: evil-define-key` crashes.

## Update: Scripted Evil RET check (2025-12-23)

- Added `dev/check-evil-bindings.el`, a standalone batch script that requires Evil, loads `mail-app`, and errors out if any mode lacks the `[remap evil-ret]` entry or if pressing RET resolves to the wrong command. Run it with `emacs -Q --batch -L . -l dev/check-evil-bindings.el` inside `mail-app-wrap` to verify the bindings in your actual configuration.

## Update: Persistent Sort Methods (2025-12-31)

Added configurable and persistent sort methods for accounts, mailboxes, and messages with automatic saving to custom-file.

### Features Added

1. **Accounts Sorting:**
   - Sort methods: `natural` (setup order) or `alpha` (alphabetical)
   - Keybinding: `o` to toggle between sort methods
   - Saves preference via `mail-app-default-accounts-sort-method`

2. **Mailboxes Sorting:**
   - Sort methods:
     - `default` - As returned by mail-app-cli
     - `smart` - INBOX first, then by unread count, then alphabetical (default)
     - `unread` - Pure unread count (descending)
     - `alpha` - Alphabetical by mailbox name
   - Keybinding: `o` to cycle through sort methods
   - Saves preference via `mail-app-default-mailboxes-sort-method`

3. **Messages Sorting:**
   - Sort methods: `date`, `subject`, `from`, `unread`
   - Keybindings: `o` to cycle sort key, `O` to reverse order
   - Saves preferences via:
     - `mail-app-default-messages-sort-method`
     - `mail-app-default-messages-sort-reverse`

### Implementation Details

- All sort preferences persist across Emacs sessions using `customize-save-variable`
- Buffer-local sort state is initialized from defcustom defaults on first display
- Renamed message sort key from `'read` to `'unread` for clarity (with backward compatibility)
- Updated Evil mode integration with mailboxes sort keybinding
- Sort method indicators shown in buffer headers

### Files Modified

- `mail-app-core.el`: Added defcustom variables, buffer-local state, and enhanced sort functions
- `mail-app-display.el`: Initialize sort state from defaults in format functions
- `mail-app-commands.el`: Updated sort commands to save preferences
- `mail-app-evil.el`: Added mailboxes sort keybinding to Evil mode

## Update: Automatic Mark-as-Read (2025-12-31)

Added automatic mark-as-read functionality when viewing messages.

### Features Added

- **Automatic Mark-as-Read:** When opening a message, it's automatically marked as read in Mail.app
- **Configurable:** Control via `mail-app-mark-as-read-on-view` defcustom (default: `t`)
- **Silent Operation:** Marking happens in background without refreshing the view buffer
- **Smart:** Only marks messages that are currently unread

### Configuration

To disable automatic mark-as-read, add to your init.el:
```elisp
(setq mail-app-mark-as-read-on-view nil)
```

### Files Modified

- `mail-app-core.el`: Added `mail-app-mark-as-read-on-view` defcustom
- `mail-app-commands.el`: Added automatic mark-as-read logic to `mail-app-view-message`

## Update: Mark Entire Mailbox as Read (2025-12-31)

Added ability to mark all unread messages in a mailbox as read from the mailboxes view.

### Features Added

- **Bulk Mark as Read:** Press `T` on any mailbox to mark all unread messages as read
- **Works from Mailboxes View:** No need to open the mailbox first
- **Confirmation:** Prompts before marking (e.g., "Mark all 523 unread messages in Spam as read?")
- **Progress Feedback:** Shows status and automatically refreshes when complete
- **Perfect for:** Spam, trash, archive, or any mailbox you want to clear

### Usage

1. Navigate to mailboxes view (`M-x mail-app-list-mailboxes`)
2. Move cursor to mailbox with unread messages
3. Press `T` (Shift+t)
4. Confirm the action
5. Wait for completion and see updated unread count

### Files Modified

- `mail-app-core.el`: Added `T` keybinding to mailboxes mode map
- `mail-app-commands.el`: Implemented `mail-app-mark-mailbox-as-read` function
- `mail-app-evil.el`: Added Evil mode keybinding
- `mail-app-display.el`: Updated command help text in mailboxes view


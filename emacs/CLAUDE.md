# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# mail-app-wrap Development Guide

## Project Overview

mail-app-wrap is an Emacs interface to mail-app-cli, providing a full-featured mail client experience within Emacs. It follows the established wrapper pattern used across other -wrap projects (twist-wrap, jira-wrap, reminders-wrap).

## Architecture

### Components

1. **CLI Wrapper** (`mail-app--run-command`)
   - Executes mail-app-cli commands via `call-process`
   - Returns stdout on success, raises error on failure
   - No shell escaping needed (direct process invocation)

2. **Data Parsing**
   - `mail-app--parse-mailboxes-output`: Parses tabular mailbox list
   - `mail-app--parse-messages-output`: Parses tabular message list
   - Both use regex to extract tab-separated fields
   - Returns list of plists (`:account`, `:name`, `:unread`, etc.)

3. **Display Formatting**
   - `mail-app--format-mailboxes`: Renders mailboxes with unread counts
   - `mail-app--format-messages`: Renders messages with flags/read status
   - `mail-app--format-message-view`: Displays full message content
   - Uses text properties to attach data to each line

4. **Buffer-Local State**
   - `mail-app-current-account`: Currently viewed account
   - `mail-app-current-mailbox`: Currently viewed mailbox
   - `mail-app-current-message-id`: Currently viewed message ID
   - Used for context when performing actions

5. **Four Major Modes**
   - `mail-app-accounts-mode`: View all accounts (Level 1)
   - `mail-app-mailboxes-mode`: View mailboxes for account (Level 2)
   - `mail-app-messages-mode`: View messages in a mailbox (Level 3)
   - `mail-app-message-view-mode`: View full message (Level 4)

6. **Emacspeak Integration**
   - Post-command hook for custom line speaking
   - Advice on interactive commands for audio feedback
   - Uses `emacspeak-icon` and `dtk-speak`

7. **Evil Mode Integration**
   - Sets initial state to `normal` for all modes
   - Defines vim-style keybindings (`gr`, `ZZ`, `ZQ`)
   - Clears `g` prefix to allow `gr` for refresh

### Data Flow

```
User Action (RET, g, f, etc.)
  ↓
Interactive Command (mail-app-list-messages, etc.)
  ↓
CLI Wrapper (mail-app--run-command)
  ↓
mail-app-cli (executes AppleScript/JXA)
  ↓
Mail.app (performs operation)
  ↓
Output (tabular text)
  ↓
Parser (mail-app--parse-*-output)
  ↓
Display Formatter (mail-app--format-*)
  ↓
Buffer with Text Properties
  ↓
User sees formatted display
```

### Text Properties Pattern

Each displayed line has two key properties:

1. **Data property** (e.g., `mail-app-message-data`)
   - Full plist of item data
   - Retrieved with `mail-app--get-message-at-point`
   - Used to perform actions on the item

2. **Speech property** (`emacspeak-speak`)
   - Human-readable description for screen readers
   - Spoken when navigating lines
   - Includes context (flags, unread status, etc.)

## Development Commands

### Testing from Emacs

```elisp
;; Load the file
(load-file "mail-app.el")

;; Test main entry point
(mail-app-list-mailboxes)

;; Test search
(mail-app-search "test query")

;; Test specific mailbox
(mail-app-list-messages "Gmail" "INBOX")
```

### Testing from Terminal

```bash
# Verify CLI works
mail-app-cli accounts list
mail-app-cli mailboxes list -a "Gmail"
mail-app-cli messages list -a "Gmail" -m "INBOX" -l 10

# Test search
mail-app-cli search "test query" -a "Gmail" -m "INBOX"

# Test attachments
mail-app-cli attachments list MESSAGE_ID -a "Gmail" -m "INBOX"
mail-app-cli attachments save MESSAGE_ID "filename.pdf" -a "Gmail" -m "INBOX"
```

### CLI Command Structure

IMPORTANT: All mail-app-cli commands follow this pattern:
```
mail-app-cli <noun> <verb> [args...] [flags...]
```

Examples:
- `mail-app-cli accounts list`
- `mail-app-cli mailboxes list -a "Gmail"`
- `mail-app-cli messages list -a "Gmail" -m "INBOX"`
- `mail-app-cli attachments list MESSAGE_ID -a "Gmail" -m "INBOX"`
- `mail-app-cli search "query" -a "Gmail"`

When calling from Emacs, the arguments are passed as a list:
```elisp
(mail-app--run-command "attachments" "list" message-id "-a" account "-m" mailbox)
```

## Known Constraints

### mail-app-cli Requirements

- Requires macOS (uses AppleScript/JXA)
- Requires Mail.app to be running
- Requires at least one configured account
- Message operations require both account and mailbox context

### Parsing Limitations

- Assumes tab-separated output format from CLI
- Subject/sender truncation happens at display time
- No JSON output mode (yet) - uses text parsing

### Buffer Management

- Creates new buffers for each view level
- Search results create separate buffers per query
- No automatic buffer cleanup (user must quit manually)

### Message Actions Context

- Flag, delete, archive, mark operations require:
  - `mail-app-current-account` (buffer-local)
  - `mail-app-current-mailbox` (buffer-local)
- These are set when viewing messages from a mailbox
- Search results may not have full context (future enhancement)

## Interactive Commands

### Entry Points

- `mail-app-list-mailboxes` - Main entry point, shows all mailboxes
- `mail-app-search` - Search across all email

### Navigation Commands

- `mail-app-view-messages-at-point` - View messages in mailbox at point
- `mail-app-view-message-at-point` - View full message at point
- `mail-app-refresh` - Refresh current view

### Message Actions (from list)

- `mail-app-flag-message-at-point` - Toggle flag
- `mail-app-delete-message-at-point` - Delete (with confirmation)
- `mail-app-archive-message-at-point` - Archive
- `mail-app-mark-message-at-point` - Toggle read/unread

### Message Actions (from view)

- `mail-app-flag-current-message` - Flag current message
- `mail-app-delete-current-message` - Delete current message (with confirmation)
- `mail-app-archive-current-message` - Archive current message
- `mail-app-mark-current-message` - Mark current message as unread

### Filters

- `mail-app-show-unread` - Toggle unread-only filter (in messages mode)

## Code Conventions

### Naming

- Public functions: `mail-app-*` (no double dash)
- Private functions: `mail-app--*` (double dash)
- Buffer-local variables: `mail-app-*` (defvar-local)
- Customization variables: `mail-app-*` (defcustom)
- Text properties: `mail-app-*-data` for data, `emacspeak-speak` for speech

### Function Prefixes

- `mail-app--run-command`: CLI wrapper
- `mail-app--parse-*`: Output parsers
- `mail-app--format-*`: Display formatters
- `mail-app--get-*`: Text property getters
- `mail-app--emacspeak-*`: Emacspeak helpers
- `mail-app-*`: Interactive commands

### Buffer Naming

- `*Mail.app Mailboxes*` - Mailboxes list
- `*Mail.app Messages: ACCOUNT/MAILBOX*` - Messages list
- `*Mail.app Message: ID*` - Message view
- `*Mail.app Search: QUERY*` - Search results

## Testing Checklist

When making changes, verify:

- [ ] Mailboxes list displays correctly
- [ ] Can navigate to messages list
- [ ] Can view individual messages
- [ ] Flag/delete/archive/mark actions work
- [ ] Search returns results
- [ ] Unread filter works
- [ ] Refresh updates display
- [ ] Emacspeak speaks lines correctly (if installed)
- [ ] Evil keybindings work (if installed)
- [ ] Error handling shows useful messages
- [ ] Confirmation prompts work for destructive actions

## Current Features

Implemented functionality:
- ✅ 4-level navigation (accounts → mailboxes → messages → message view)
- ✅ Marking and bulk operations (delete, archive, flag, mark as read/unread)
- ✅ Message composition via Emacs compose-mail
- ✅ Reply and reply-all functionality
- ✅ Sending via mail-app-cli
- ✅ Pagination with offset/limit
- ✅ Contextual search (current account/mailbox) and global search
- ✅ View cycling (plain text → full headers → attachments)
- ✅ Async operations (non-blocking UI)
- ✅ Full Emacspeak integration
- ✅ Evil mode keybindings

## Known Issues and Future Enhancements

Current bugs to fix:
- [ ] Attachments view not working properly (view cycling to attachments mode)

Potential improvements (not currently implemented):
- JSON output mode for more reliable parsing
- Attachment save functionality in Emacs
- Message threading
- Multiple mailbox selection
- Persistent filters/sorting
- Draft management
- Account-specific colors/faces
- Integration with org-mode (capture emails as TODOs)
- Configurable keybindings

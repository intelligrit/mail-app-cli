# mail-app-wrap

Emacs interface for the mail-app CLI tool, providing a full-featured interface to macOS Mail.app from within Emacs.

## Features

- View all mailboxes across all accounts
- Browse messages with filtering (unread, flagged)
- View full message details
- Search across all emails
- Flag, archive, delete, and mark messages
- Full Emacspeak integration with custom speech and audio icons
- Evil mode support with vim-like keybindings
- Three-level navigation: mailboxes → messages → message view

## Requirements

- Emacs 27.1 or later
- macOS with Mail.app configured
- [mail-app-cli](https://github.com/robertmeta/mail-app-cli) installed and in PATH
- Optional: Emacspeak for screen reader support
- Optional: Evil mode for vim keybindings

## Installation

1. Install mail-app-cli:
```bash
# From the mail-app-cli directory
go install
```

2. Clone this repository:
```bash
git clone https://github.com/robertmeta/mail-app-wrap.git
cd mail-app-wrap
```

3. Add to your Emacs configuration:
```elisp
(add-to-list 'load-path "/path/to/mail-app-wrap")
(require 'mail-app)
```

## Setup

Ensure Mail.app is configured with at least one account. The wrapper uses mail-app-cli which communicates directly with Mail.app via AppleScript.

### Configuration

Customize the following variables:

```elisp
;; Path to mail-app-cli (if not in PATH)
(setq mail-app-command "mail-app-cli")

;; Default account to use (nil prompts each time)
(setq mail-app-default-account "Gmail")

;; Number of messages to display
(setq mail-app-message-limit 50)
```

## Usage

### Main Entry Point

Start with:
```
M-x mail-app-list-mailboxes
```

This opens the mailboxes list showing all mailboxes across all accounts with unread and total message counts.

### Navigation

From the mailboxes list:
- Press `RET` on a mailbox to view its messages
- Press `s` to search across all email
- Press `q` to quit

From the messages list:
- Press `RET` on a message to view full details
- Press `u` to toggle showing only unread messages
- Press various keys to perform actions (see keybindings below)

From the message view:
- Read the full message content
- Perform actions on the current message
- Press `q` to return to messages list

## Keybindings

### Mailboxes Mode

| Key | Command | Description |
|-----|---------|-------------|
| `RET` | `mail-app-view-messages-at-point` | View messages in mailbox |
| `n` | `next-line` | Move to next line |
| `p` | `previous-line` | Move to previous line |
| `g` / `r` | `mail-app-refresh` | Refresh mailboxes list |
| `s` | `mail-app-search` | Search all email |
| `q` | `quit-window` | Quit window |
| `?` | `describe-mode` | Show help |

### Messages Mode

| Key | Command | Description |
|-----|---------|-------------|
| `RET` | `mail-app-view-message-at-point` | View full message |
| `n` | `next-line` | Move to next line |
| `p` | `previous-line` | Move to previous line |
| `g` / `r` | `mail-app-refresh` | Refresh messages list |
| `s` | `mail-app-search` | Search all email |
| `f` | `mail-app-flag-message-at-point` | Toggle flag on message |
| `d` | `mail-app-delete-message-at-point` | Delete message (with confirmation) |
| `a` | `mail-app-archive-message-at-point` | Archive message |
| `m` | `mail-app-mark-message-at-point` | Toggle read/unread status |
| `u` | `mail-app-show-unread` | Toggle unread filter |
| `q` | `quit-window` | Quit window |
| `?` | `describe-mode` | Show help |

### Message View Mode

| Key | Command | Description |
|-----|---------|-------------|
| `n` | `next-line` | Scroll down |
| `p` | `previous-line` | Scroll up |
| `f` | `mail-app-flag-current-message` | Flag current message |
| `d` | `mail-app-delete-current-message` | Delete current message (with confirmation) |
| `a` | `mail-app-archive-current-message` | Archive current message |
| `m` | `mail-app-mark-current-message` | Mark current message as unread |
| `q` | `quit-window` | Quit window |
| `?` | `describe-mode` | Show help |

### Evil Mode Keybindings

When Evil mode is active, all modes start in `normal` state with additional vim-style bindings:

- `j` / `k` - Navigate up/down (inherited from Evil normal mode)
- `gg` / `G` - Jump to top/bottom (inherited from Evil normal mode)
- `gr` - Refresh (vim convention for reload)
- `ZZ` / `ZQ` - Quit window (vim convention)

All standard keybindings from the tables above also work in Evil normal mode.

## Emacspeak Support

Full Emacspeak integration includes:

- **Custom line speaking**: Each line speaks relevant information (mailbox name, unread count, message subject, sender, etc.)
- **Audio icons**:
  - `open-object` when opening lists or views
  - `select-object` when flagging, archiving, or marking messages
  - `delete-object` when deleting messages
- **Context-aware speech**: Messages include flag status and other metadata in spoken output

## Customization

You can customize the package through `M-x customize-group RET mail-app RET`.

Available customization options:

- `mail-app-command`: Path to mail-app-cli executable
- `mail-app-default-account`: Default account to use (or nil to prompt)
- `mail-app-message-limit`: Maximum number of messages to display

## Troubleshooting

### mail-app-cli not found

If you get an error about mail-app-cli not being found:

1. Ensure mail-app-cli is installed: `go install` in the mail-app-cli directory
2. Check it's in your PATH: `which mail-app-cli`
3. Or set the full path: `(setq mail-app-command "/full/path/to/mail-app-cli")`

### Mail.app not responding

If commands fail or timeout:

1. Ensure Mail.app is running
2. Check Mail.app has at least one configured account
3. Try running `mail-app-cli accounts list` from terminal to verify CLI works

### Emacspeak not speaking

If you have Emacspeak installed but lines aren't being spoken:

1. Ensure Emacspeak is loaded before mail-app.el
2. Check `emacspeak-speak-mode` is enabled
3. Verify DTK server is running

## License

MIT License - see LICENSE file for details.

## Author

Robert Melton

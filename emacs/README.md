<p align="center">
  <img src="logo.png" alt="mail-app-wrap logo" width="400"/>
</p>

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
- `mail-app-cli` built and in PATH (`make install` or `go install` from repo root)
- Optional: Emacspeak for screen reader support
- Optional: Evil mode for vim keybindings

## Installation

### Direct load-path

Add the `emacs` directory to your Emacs configuration:

```elisp
(add-to-list 'load-path "/path/to/mail-app-cli/emacs")
(require 'mail-app)
```

### With Straight / Elpaca

```elisp
(use-package mail-app
  :straight (:type git :host github :repo "intelligrit/mail-app-cli" :files ("emacs/*.el")))
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
| `T` | `mail-app-mark-mailbox-as-read` | Mark every message in mailbox at point as read (one CLI call) |
| `R` | `mail-app-mark-special-read` | Mark all accounts' trash / junk / archive as read |
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
| `m` / `M` | `mail-app-toggle-mark-at-point` / `-backward` | Mark message for a bulk action |
| `x` | `mail-app-delete-marked` | Delete marked messages |
| `,a` `,f` `,j` `,v` `,r` `,u` | `mail-app-*-marked` | Archive / flag / junk / move / read / unread marked messages |
| `q` | `quit-window` | Quit window |
| `?` | `describe-mode` | Show help |

Bulk actions on marked messages are one `mail-app-cli` call regardless of how
many accounts the messages span, so marking fifty messages and pressing `x`
costs one Mail.app round trip, not fifty.

Archiving Gmail messages is not possible through Mail.app scripting; what
happens to them is governed by `mail-app-gmail-archive-action` (`skip` and
report by default, `delete` to Trash, or `read`).

### Message View Mode

| Key | Command | Description |
|-----|---------|-------------|
| `n` | `next-line` | Scroll down |
| `p` | `previous-line` | Scroll up |
| `v` | `mail-app-cycle-view` | Cycle view modes (plain → full → attachments) |
| `f` | `mail-app-flag-current-message` | Flag current message |
| `d` | `mail-app-delete-current-message` | Delete current message (with confirmation) |
| `a` | `mail-app-archive-current-message` | Archive current message |
| `t` | `mail-app-mark-current-message` | Mark current message as unread |
| `r` | `mail-app-reply-current-message` | Reply to current message |
| `R` | `mail-app-reply-all-current-message` | Reply all to current message |
| `s` / `RET` | `mail-app-save-attachment-at-point` | Save attachment at point (in attachments view) |
| `c` | `mail-app-compose` | Compose new message |
| `g` | `mail-app-refresh` | Refresh current view |
| `q` | `quit-window` | Quit window |
| `?` | `describe-mode` | Show help |

#### View Modes

When viewing a message, press `v` to cycle through:
- **Plain view**: Message content only
- **Full view**: Complete message with all headers
- **Attachments view**: List of attachments (if any)

In attachments view, navigate to an attachment and press `RET` or `s` to save it. You'll be prompted for a location (defaults to ~/Downloads).

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
- `mail-app-identities`: List of send identities with custom names, emails, full names, accounts, and signatures
- `mail-app-auto-discover-identities`: Auto-discover identities from Mail.app accounts and aliases (default: t)
- `mail-app-signatures`: Alist mapping account names or email addresses to signatures
- `mail-app-default-account`: Default account to use (or nil to prompt)
- `mail-app-message-limit`: Maximum number of messages to display
- `mail-app-mark-as-read-on-view`: Auto-mark messages as read when viewing (default: t)
- `mail-app-gmail-archive-action`: What archive does to Gmail messages: `skip` (default), `delete`, or `read`
- `mail-app-no-content-mailbox-regexp`: Mailboxes (Trash, Deleted Items, Spam, Junk...) whose bodies are never fetched even with content reading on; the unified trash/junk views are always excluded
- `mail-app-mailbox-counts`: Show total message counts in mailbox lists (default: nil; costs ~3s vs <1s)
- `mail-app-default-accounts-sort-method`: Default sort for accounts list
- `mail-app-default-mailboxes-sort-method`: Default sort for mailboxes list
- `mail-app-default-messages-sort-method`: Default sort for messages list

### Send Identities

`mail-app` supports multiple send identities (accounts, aliases, and custom sender names):

- **Zero-config auto-discovery**: Automatically discovers all accounts and configured email aliases from Mail.app.
- **Auto-matching on reply**: When replying or forwarding, `mail-app` inspects the incoming message's `To` and `Cc` headers and automatically selects the matching identity and From address.
- **Self-reply filtering**: Replying to all automatically omits your own identity email addresses from the recipient list.
- **Interactive switching in compose buffers**:
  - `C-c C-x i` or `C-c i`: Select an identity interactively via `completing-read`.
  - `C-c C-x c`: Cycle to the next identity with a single keypress.
  - Switches `From:` header, accounts, and updates signatures in-place without disturbing your draft.
  - `C-u c`: Prompt for identity before composing.

Example custom configuration in `~/.emacs.d/init.el`:

```elisp
(setq mail-app-identities
      '((:name "Work"
         :email "rmelton@skywarditsolutions.com"
         :full-name "Robert Melton"
         :account "Skyward"
         :signature "-- \nRobert Melton\nSkyward IT Solutions")
        (:name "Personal"
         :email "robert@robertmelton.com"
         :full-name "Robert Melton"
         :account "rmelton@fastmail.com email"
         :signature "-- \nRobert")))
```

## Troubleshooting

### "mail-app-cli X is older than ..." warning

The Elisp and the CLI evolve together. When the installed binary is older
than `mail-app-required-cli-version`, the first `mail-app-list-accounts` /
`mail-app-list-mailboxes` of the session warns. Rebuild and install the CLI:

```bash
cd ~/projects/intelligrit/mail-app-cli && make install
```

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
4. If even that hangs, Mail.app's scripting interface is wedged — usually by a
   message-body fetch (`--with-content`, i.e. `mail-app-read-message-content`)
   that stalled. Restart Mail.app. Avoid content fetching on large or junk
   mailboxes.

### Emacspeak not speaking

If you have Emacspeak installed but lines aren't being spoken:

1. Ensure Emacspeak is loaded before mail-app.el
2. Check `emacspeak-speak-mode` is enabled
3. Verify DTK server is running

## License

MIT License - see LICENSE file for details.

## Author

Robert Melton

# mail-app-cli

**An [Intelligrit Labs](https://intelligrit.com#labs) Project**

<p align="center">
  <img src="logo.png" alt="mail-app-cli logo" width="200">
</p>

A command-line interface for controlling macOS Mail.app. Provides complete scriptable access to accounts, mailboxes, messages, and attachments.

## Features

- List and manage Mail.app accounts
- Browse and manage mailboxes
- List, read, search, and manage messages
- Archive, move, delete, flag, and mark messages
- Send emails
- Manage attachments
- Fully scriptable - perfect for automation and building GUIs
- **Emacs Frontend**: Full-featured interactive Emacs mail client included in [`emacs/`](emacs/)

## Installation

### From Source

```bash
go install github.com/intelligrit/mail-app-cli@latest
```

### Build Locally

```bash
git clone https://github.com/intelligrit/mail-app-cli.git
cd mail-app-cli
go build -o mail-app-cli
```

## Usage

### Accounts

List all Mail.app accounts:

```bash
mail-app-cli accounts list
```

Show details for a specific account:

```bash
mail-app-cli accounts show "Gmail"
```

### Mailboxes

List all mailboxes:

```bash
mail-app-cli mailboxes list
```

List mailboxes for a specific account:

```bash
mail-app-cli mailboxes list --account "Gmail"
```

Include per-mailbox message totals (`TotalCount`; slower, enumerates each mailbox):

```bash
mail-app-cli mailboxes list --counts
```

### Messages

List messages in a mailbox:

```bash
mail-app-cli messages list --account "Gmail" --mailbox "INBOX"
```

List with filters:

```bash
# Show only unread messages
mail-app-cli messages list -a "Gmail" -m "INBOX" --unread

# Show only flagged messages
mail-app-cli messages list -a "Gmail" -m "INBOX" --flagged

# Show messages since a specific date
mail-app-cli messages list -a "Gmail" -m "INBOX" --since "2025-12-01"

# Show messages since a specific date and time
mail-app-cli messages list -a "Gmail" -m "INBOX" --since "2025-12-14 09:00:00"

# Combine filters
mail-app-cli messages list -a "Gmail" -m "INBOX" --unread --since "2025-12-01" --limit 10
```

> **`--with-content` caution:** fetching bodies can block Mail.app's entire
> scripting interface if a body is not cached locally (see PERFORMANCE.md).
> Use it on small, recently synced mailboxes, not from unattended jobs.

Every message includes `MessageID` (the RFC 5322 `Message-ID` header) for
free. Add `--with-headers` to `list` and the unified subcommands to also get
`InReplyTo` and `References`, parsed from the message's raw headers, for
building a threaded view; it is opt-in because bulk-fetching headers is
roughly 9x slower than the other list fields:

```bash
mail-app-cli messages list -a "Gmail" -m "INBOX" --with-headers
```

`messages show` always includes `InReplyTo`/`References` (it already pays
the cost of a single-message fetch for `Content`).

Show full message details:

```bash
mail-app-cli messages show <message-id> -a "Gmail" -m "INBOX"
```

Mark messages as read/unread (any number of IDs, one Mail.app round trip):

```bash
# Mark as read
mail-app-cli messages mark <message-id> [<message-id>...] -a "Gmail" -m "INBOX" --read

# Mark as unread
mail-app-cli messages mark <message-id> -a "Gmail" -m "INBOX" --read=false
```

Flag/unflag messages:

```bash
# Flag messages
mail-app-cli messages flag <message-id> [<message-id>...] -a "Gmail" -m "INBOX" --flagged

# Unflag a message
mail-app-cli messages flag <message-id> -a "Gmail" -m "INBOX" --flagged=false
```

Archive messages:

```bash
mail-app-cli messages archive <message-id> [<message-id>...] -a "Exchange" -m "Inbox"
```

> **Gmail limitation:** archiving is refused for Gmail accounts. Mail.app
> offers no safe scriptable archive for Gmail — scripted moves out of INBOX
> silently revert on the next sync, and the only workaround that sticks
> (bouncing the message through Trash) can permanently delete mail. Archive
> Gmail messages in Mail.app or Gmail itself, or use `messages delete` to
> send them to Trash.

Move messages to another mailbox (the last argument is the target):

```bash
mail-app-cli messages move <message-id> [<message-id>...] "Archive" -a "Gmail" -m "INBOX"
```

Delete messages:

```bash
mail-app-cli messages delete <message-id> [<message-id>...] -a "Gmail" -m "INBOX"
```

Deleting a message that is already in Trash removes it permanently.

All mutation commands accept multiple IDs and process them in a single
Mail.app call.

**Global IDs (no `--account`/`--mailbox`):** Mail.app message IDs are unique
across all accounts, so mutations can also be run with just IDs — from any mix
of accounts and mailboxes in one call. The output is then a JSON summary with a
per-message status:

```bash
mail-app-cli messages archive 399357 399364 401002
```

```json
{
  "results": [
    {"id": "399357", "account": "Gmail", "mailbox": "All Mail", "status": "skipped", "gmail": true,
     "error": "Gmail accounts cannot be archived via Mail.app scripting"},
    {"id": "399364", "account": "Exchange", "mailbox": "Inbox", "status": "ok"},
    {"id": "401002", "status": "missing"}
  ],
  "ok": 1, "missing": 1, "failed": 0, "skipped": 1
}
```

Statuses are `ok`, `missing`, `failed` (with `error`) and `skipped`. For
`archive`, `--gmail skip|delete|read` decides what happens to Gmail messages:
leave them and report `skipped` (default), move them to Trash, or mark them
read. `move` resolves the target mailbox inside each message's own account. Each ID is reported individually: a missing ID does not stop
the others, and the command exits non-zero listing the IDs that failed.

> **Note:** when a message is moved (archive, move, delete) Mail.app assigns it
> a **new ID** in the destination mailbox. Re-list the destination if you need
> to act on it again.

### Marking Whole Mailboxes as Read

Mark every message in a mailbox as read in one call:

```bash
mail-app-cli mailboxes mark-read -a "Gmail" -m "Spam"
```

Or hit the provider-independent special mailboxes across all accounts. Mail.app
resolves the names ("Trash" vs "Deleted Items", "Spam" vs "Junk Email") itself:

```bash
# Everything you never read anyway
mail-app-cli mailboxes mark-read --trash --junk --archive
mail-app-cli mailboxes mark-read --all            # same thing

# Only some accounts (repeatable)
mail-app-cli mailboxes mark-read --all -a "Skyward" -a "Intelligrit"

# See what would change first
mail-app-cli mailboxes mark-read --all --dry-run

# Mark unread instead
mail-app-cli mailboxes mark-read -a "Gmail" -m "INBOX" --unread
```

Output is a JSON array of `{account, mailbox, changed}` per mailbox touched.
`--archive` matches a mailbox literally named "Archive"; Gmail's "All Mail" is
skipped because it also holds every inbox message (pass `-m "All Mail"`
explicitly if you really want that).

### Sending Email

Send a message:

```bash
mail-app-cli send \
  --account "Gmail" \
  --to user@example.com \
  --subject "Hello" \
  --body "Message content here"
```

Send to multiple recipients:

```bash
mail-app-cli send \
  -a "Gmail" \
  -t user1@example.com \
  -t user2@example.com \
  -c cc@example.com \
  -s "Multi-recipient message" \
  --body "Content"
```

### Search

Search for messages across all mailboxes:

```bash
mail-app-cli search "important meeting"
```

Search with limit:

```bash
mail-app-cli search "project update" --limit 20
```

### Attachments

List attachments in a message:

```bash
mail-app-cli attachments list <message-id> -a "Gmail" -m "INBOX"
```

Save an attachment:

```bash
mail-app-cli attachments save <message-id> "document.pdf" -a "Gmail" -m "INBOX"
```

Save to a specific path:

```bash
mail-app-cli attachments save <message-id> "document.pdf" -a "Gmail" -m "INBOX" -o ~/Downloads/document.pdf
```

## JSON Output and jq

All commands output JSON format for easy parsing and scripting. The output is formatted with 2-space indentation for human readability while remaining machine-parseable.

### Pretty Printing

For even prettier output, pipe through `jq`:

```bash
mail-app-cli accounts list | jq
```

### jq Examples

#### Filter accounts by email domain

```bash
mail-app-cli accounts list | jq '.[] | select(.EmailAddress | endswith("@gmail.com"))'
```

#### Get only enabled accounts

```bash
mail-app-cli accounts list | jq '.[] | select(.Enabled==true) | .Name'
```

#### Count unread messages across all mailboxes

```bash
mail-app-cli mailboxes list | jq '[.[].UnreadCount] | add'
```

#### Find mailboxes with unread messages

```bash
mail-app-cli mailboxes list | jq '.[] | select(.UnreadCount > 0) | {account: .Account, name: .Name, unread: .UnreadCount}'
```

#### Get just the subject lines from messages

```bash
mail-app-cli messages list -a "Gmail" -m "INBOX" | jq '.[].Subject'
```

#### Filter unread messages from specific sender

```bash
mail-app-cli messages list -a "Gmail" -m "INBOX" | jq '.[] | select(.Read==false and (.Sender | contains("boss@company.com")))'
```

#### Search and format results as CSV

```bash
mail-app-cli search "important" | jq -r '.[] | [.Account, .Mailbox, .Subject, .Sender] | @csv'
```

#### Count messages by account

```bash
mail-app-cli search "project" | jq 'group_by(.Account) | map({account: .[0].Account, count: length})'
```

#### Get attachment names from a message

```bash
mail-app-cli attachments list <message-id> -a "Gmail" -m "INBOX" | jq '.[].Name'
```

#### Find large attachments (>1MB)

```bash
mail-app-cli attachments list <message-id> -a "Gmail" -m "INBOX" | jq '.[] | select(.FileSize > 1048576)'
```

### Scripting Examples

#### Check for unread messages

```bash
#!/bin/bash
unread=$(mail-app-cli messages list -a "Gmail" -m "INBOX" --unread | jq 'length')
if [ $unread -gt 0 ]; then
  echo "You have $unread unread messages"
fi
```

#### Archive all read messages (non-Gmail accounts)

```bash
#!/bin/bash
mail-app-cli messages list -a "Exchange" -m "Inbox" | jq -r '.[] | select(.Read==true) | .ID' \
  | xargs mail-app-cli messages archive -a "Exchange" -m "Inbox"
```

#### Daily unread summary

```bash
#!/bin/bash
echo "Today's Unread Email Summary"
echo "============================"
mail-app-cli mailboxes list | jq -r '.[] | select(.UnreadCount > 0) | "\(.Account)/\(.Name): \(.UnreadCount) unread"'
```

#### Save all attachments from a sender

```bash
#!/bin/bash
SENDER="colleague@company.com"
ACCOUNT="Gmail"
MAILBOX="INBOX"

# Find all messages from sender
mail-app-cli messages list -a "$ACCOUNT" -m "$MAILBOX" | jq -r ".[] | select(.Sender | contains(\"$SENDER\")) | .ID" | while read -r msg_id; do
  # Get attachments for each message
  mail-app-cli attachments list "$msg_id" -a "$ACCOUNT" -m "$MAILBOX" | jq -r '.[].Name' | while read -r att_name; do
    echo "Saving: $att_name from message $msg_id"
    mail-app-cli attachments save "$msg_id" "$att_name" -a "$ACCOUNT" -m "$MAILBOX" -o "~/Downloads/$att_name"
  done
done
```

## Project Structure

```
mail-app-cli/
├── cmd/              # Cobra command definitions
│   ├── root.go
│   ├── accounts.go
│   ├── mailboxes.go
│   ├── messages.go
│   ├── send.go
│   ├── search.go
│   └── attachments.go
├── pkg/
│   └── mail/        # Mail.app AppleScript/JXA client
│       └── client.go
└── main.go
```

## How It Works

The CLI uses AppleScript and JavaScript for Automation (JXA) to interact with Mail.app. This provides:

- Native integration with Mail.app
- Access to all Mail.app features
- No external dependencies or APIs required
- Works with all mail providers configured in Mail.app

## Requirements

- macOS (tested on macOS 12+)
- Mail.app configured with at least one account
- Go 1.21+ (for building from source)

## Development

### Prerequisites

- Go 1.21 or higher
- macOS with Mail.app

### Building

```bash
go build -o mail-app-cli
```

### Testing

```bash
# Test account listing
./mail-app-cli accounts list

# Test mailbox listing
./mail-app-cli mailboxes list

# Test message listing
./mail-app-cli messages list -a "Your Account" -m "INBOX" --limit 5
```

## Emacs Interface

An interactive Emacs frontend for `mail-app-cli` is included in [`emacs/`](emacs/). It provides mailbox navigation, threaded message browsing, reading, searching, flagging, archiving, Evil mode bindings, and Emacspeak screen reader integration.

To use it in your Emacs configuration:

```elisp
(add-to-list 'load-path "/path/to/mail-app-cli/emacs")
(require 'mail-app)
```

Or with `straight.el` / `elpaca`:

```elisp
(use-package mail-app
  :straight (:type git :host github :repo "intelligrit/mail-app-cli" :files ("emacs/*.el")))
```

See [`emacs/README.md`](emacs/README.md) for full configuration and keybinding documentation.

## Roadmap

Future enhancements:

- Rules management
- Smart mailbox operations
- Signatures management
- VIP contacts
- Export/import functionality
- IMAP folder synchronization
- Draft management

## Contributing

Contributions are welcome! This project follows standard Go conventions.

### Guidelines

1. Fork the repository
2. Create a feature branch
3. Make your changes following Go best practices
4. Write tests for new functionality
5. Ensure all tests pass
6. Commit your changes
7. Push to the branch
8. Open a Pull Request

## About Intelligrit Labs

mail-app-cli is developed by [Intelligrit Labs](https://intelligrit.com#labs), the R&D arm of Intelligrit LLC. We build tools for ourselves and release them for everyone. Intelligrit delivers AI-driven IT modernization for federal agencies.

## License

MIT License - see LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue on GitHub.

## Acknowledgments

- Built with Cobra CLI framework
- Uses AppleScript and JXA for Mail.app integration

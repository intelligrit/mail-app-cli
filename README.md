# mail-app-cli

A command-line interface for controlling macOS Mail.app. Provides complete scriptable access to accounts, mailboxes, messages, and attachments.

## Features

- List and manage Mail.app accounts
- Browse and manage mailboxes
- List, read, search, and manage messages
- Archive, move, delete, flag, and mark messages
- Send emails
- Manage attachments
- Git mail workflow support (mbox import/export for `git format-patch` and `git am`)
- Fully scriptable - perfect for automation and building GUIs

## Installation

### From Source

```bash
go install github.com/robertmeta/mail-app-cli@latest
```

### Build Locally

```bash
git clone https://github.com/robertmeta/mail-app-cli.git
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

Show full message details:

```bash
mail-app-cli messages show <message-id> -a "Gmail" -m "INBOX"
```

Mark message as read/unread:

```bash
# Mark as read
mail-app-cli messages mark <message-id> -a "Gmail" -m "INBOX" --read

# Mark as unread
mail-app-cli messages mark <message-id> -a "Gmail" -m "INBOX" --read=false
```

Flag/unflag a message:

```bash
# Flag a message
mail-app-cli messages flag <message-id> -a "Gmail" -m "INBOX" --flagged

# Unflag a message
mail-app-cli messages flag <message-id> -a "Gmail" -m "INBOX" --flagged=false
```

Archive a message:

```bash
mail-app-cli messages archive <message-id> -a "Gmail" -m "INBOX"
```

Move a message to another mailbox:

```bash
mail-app-cli messages move <message-id> "Archive" -a "Gmail" -m "INBOX"
```

Delete a message:

```bash
mail-app-cli messages delete <message-id> -a "Gmail" -m "INBOX"
```

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
mail-app-cli accounts list | jq '.[] | select(.emailAddress | endswith("@gmail.com"))'
```

#### Get only enabled accounts

```bash
mail-app-cli accounts list | jq '.[] | select(.enabled==true) | .name'
```

#### Count unread messages across all mailboxes

```bash
mail-app-cli mailboxes list | jq '[.[].unreadCount] | add'
```

#### Find mailboxes with unread messages

```bash
mail-app-cli mailboxes list | jq '.[] | select(.unreadCount > 0) | {account, name, unread: .unreadCount}'
```

#### Get just the subject lines from messages

```bash
mail-app-cli messages list -a "Gmail" -m "INBOX" | jq '.[].subject'
```

#### Filter unread messages from specific sender

```bash
mail-app-cli messages list -a "Gmail" -m "INBOX" | jq '.[] | select(.read==false and (.sender | contains("boss@company.com")))'
```

#### Search and format results as CSV

```bash
mail-app-cli search "important" | jq -r '.[] | [.account, .mailbox, .subject, .sender] | @csv'
```

#### Count messages by account

```bash
mail-app-cli search "project" | jq 'group_by(.account) | map({account: .[0].account, count: length})'
```

#### Get attachment names from a message

```bash
mail-app-cli attachments list <message-id> -a "Gmail" -m "INBOX" | jq '.[].name'
```

#### Find large attachments (>1MB)

```bash
mail-app-cli attachments list <message-id> -a "Gmail" -m "INBOX" | jq '.[] | select(.fileSize > 1048576)'
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

#### Archive all read messages

```bash
#!/bin/bash
mail-app-cli messages list -a "Gmail" -m "INBOX" | jq -r '.[] | select(.read==true) | .id' | while read -r msg_id; do
  mail-app-cli messages archive "$msg_id" -a "Gmail" -m "INBOX"
done
```

#### Daily unread summary

```bash
#!/bin/bash
echo "Today's Unread Email Summary"
echo "============================"
mail-app-cli mailboxes list | jq -r '.[] | select(.unreadCount > 0) | "\(.account)/\(.name): \(.unreadCount) unread"'
```

#### Save all attachments from a sender

```bash
#!/bin/bash
SENDER="colleague@company.com"
ACCOUNT="Gmail"
MAILBOX="INBOX"

# Find all messages from sender
mail-app-cli messages list -a "$ACCOUNT" -m "$MAILBOX" | jq -r ".[] | select(.sender | contains(\"$SENDER\")) | .id" | while read -r msg_id; do
  # Get attachments for each message
  mail-app-cli attachments list "$msg_id" -a "$ACCOUNT" -m "$MAILBOX" | jq -r '.[].name' | while read -r att_name; do
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

## Git Mail Workflow

mail-app-cli supports the git email workflow through mbox format import/export, making it a lightweight alternative to `git send-email` and compatible with `git am` for applying patches.

### Sending Patches (git format-patch → mail-app-cli)

Send patches created with `git format-patch` through Mail.app:

```bash
# Create patches from recent commits
git format-patch HEAD~3..HEAD

# Send all patches via Mail.app
mail-app-cli send --account "Gmail" --from-mbox 0001-*.patch

# Or pipe directly
git format-patch HEAD~3..HEAD --stdout | mail-app-cli send -a "Gmail" --from-mbox -

# Send a single patch
mail-app-cli send -a "Gmail" --from-mbox 0001-my-feature.patch

# Send as attachment (Recommended to prevent corruption)
# Mail.app may corrupt inline patches by stripping whitespace or adding format=flowed markers.
# Using --as-attachment ensures the patch file is preserved exactly as generated.
mail-app-cli send -a "Gmail" --from-mbox 0001-my-feature.patch --as-attachment
```

The `--from-mbox` flag reads patch files in mbox format (the format produced by `git format-patch`) and extracts:

- Recipients (To, Cc, Bcc)
- Subject line
- Message body
- Patch content

When using `--as-attachment`:
- The patch content is saved to a temporary file and attached to the email.
- The email body includes a note referencing the attachment.
- This prevents Mail.app from modifying the patch content (e.g., stripping whitespace).

This makes it a drop-in replacement for `git send-email` but using your configured Mail.app accounts.

### Receiving and Applying Patches (mail-app-cli → git am)

Apply patches received via email to your git repository:

```bash
# Find patch emails (search for common patch subject patterns)
mail-app-cli search "[PATCH" -a "Gmail" -m "INBOX"

# Export a single patch and apply it
mail-app-cli messages export <message-id> -a "Gmail" -m "INBOX" | git am

# Export multiple patches (e.g., a patch series) and apply them
mail-app-cli messages export <id1> <id2> <id3> -a "Gmail" -m "INBOX" | git am

# Save to a file first
mail-app-cli messages export <id1> <id2> <id3> -a "Gmail" -m "INBOX" > series.mbox
git am series.mbox
```

### Complete Workflow Example

```bash
# Scenario: You want to send a 3-patch series for review

# 1. Create your patches
git format-patch HEAD~3..HEAD
# Creates: 0001-first.patch, 0002-second.patch, 0003-third.patch

# 2. Send them via Mail.app
mail-app-cli send -a "Gmail" --from-mbox 0001-*.patch

# Recipient receives the patches, reviews them, and replies with feedback

# 3. Find the reply with updated patches
mail-app-cli search "[PATCH v2" -a "Gmail" -m "INBOX"

# 4. Export and apply the updated patches
mail-app-cli messages export <msg-id-v2-1> <msg-id-v2-2> <msg-id-v2-3> -a "Gmail" -m "INBOX" | git am
```

### Searching for Patch Series

Use search and jq to find and organize patch series:

```bash
# Find all patches for a specific feature
mail-app-cli search "[PATCH" -a "Gmail" -m "INBOX" | jq '.[] | select(.subject | contains("feature-name"))'

# Find patches by version (v2, v3, etc.)
mail-app-cli search "[PATCH v2" -a "Gmail" -m "INBOX"

# Export patches in order using jq
mail-app-cli search "[PATCH v2" -a "Gmail" -m "INBOX" | \
  jq -r 'sort_by(.subject) | .[].id' | \
  xargs mail-app-cli messages export -a "Gmail" -m "INBOX" > v2-series.mbox

git am v2-series.mbox
```

### Git Configuration

To make this workflow even smoother, you can create git aliases:

```bash
# Add to your ~/.gitconfig or .git/config
[alias]
  send-patches = "!f() { git format-patch \"$@\" --stdout | mail-app-cli send -a Gmail --from-mbox -; }; f"

# Usage
git send-patches HEAD~3..HEAD
git send-patches origin/main..HEAD
```

## Roadmap

Future enhancements:

- Rules management
- Smart mailbox operations
- Signatures management
- VIP contacts
- Batch operations
- IMAP folder synchronization
- Message threading support
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

## License

MIT License - see LICENSE file for details

## Support

For issues, questions, or contributions, please open an issue on GitHub.

## Acknowledgments

- Built with Cobra CLI framework
- Uses AppleScript and JXA for Mail.app integration

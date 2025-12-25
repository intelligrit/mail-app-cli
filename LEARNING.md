# Learning: Git Email Workflow and Mail.app Integration

This document captures findings from implementing git patch email workflows using macOS Mail.app via AppleScript.

## Git Email Workflow Requirements

### Message Format

**Plain text only** - HTML emails are rejected by git mailing lists

- Linux kernel mailing list and most git-based projects require plain text ([Basic Guide to Linux Mailing Lists](https://www.grant.pizza/blog/mailing-list-guide/))
- "The Git list rejects HTML email" ([Git MyFirstContribution](https://git-scm.com/docs/MyFirstContribution))
- Patches must NOT be sent as MIME attachments ([Git send-email docs](https://git-scm.com/docs/git-send-email))

### Content-Transfer-Encoding

Git send-email supports multiple encodings ([Git send-email documentation](https://git-scm.com/docs/git-send-email/2.9.5)):

- **8bit** (default): No Content-Transfer-Encoding header, assumes 8-bit clean transport
- **quoted-printable**: Valid but "makes the raw patch email file much harder to inspect manually"
- **base64**: Most fool-proof but "even more opaque"
- **7bit**: Fails on non-ASCII characters

**Key finding**: quoted-printable encoding is acceptable in git workflows, though not preferred.

### Unified Diff Format

Context lines in unified diff format ([Git diff-format](https://git-scm.com/docs/diff-format)):

- **Context lines** (unchanged): Start with exactly **1 space** character
- **Added lines**: Start with `+`
- **Removed lines**: Start with `-`
- **Hunk markers**: Start with `@@`

Example:
```diff
@@ -10,6 +10,7 @@ Description
 context line (unchanged)
-removed line
+added line
 another context line
```

**Critical**: The single leading space on context lines is mandatory for patch validity.

## Mail.app Behavior and Limitations

### Whitespace Stripping

**Mail.app strips single leading spaces from plain text emails**

- Single leading space: Stripped
- Two or more leading spaces: Preserved
- Source: [Apple Community - Mail strips leading whitespace](https://discussions.apple.com/thread/3168399)
- Additional confirmation: [Apple Community - Apple Mail deletes whitespace](https://discussions.apple.com/thread/254346888)

**Testing confirmed**: When sending via AppleScript with `content:` property, single leading spaces are removed from lines.

### Multipart/Alternative Generation

**Mail.app automatically creates multipart/alternative messages** (both text/plain and text/html parts) when sending via AppleScript.

Evidence from testing:
- Messages sent via AppleScript `content:` property
- Received as `Content-Type: multipart/alternative`
- Contains both `text/plain` and `text/html` parts
- Spam filter headers show `HTML_MESSAGE` flag

**No AppleScript control found** to force plain-text-only (single part) messages.

### Format=Flowed Quote Markers

**Mail.app adds `>` quote prefixes** to content that it interprets as quoted/forwarded.

Testing showed:
- Sent message source contains lines starting with `> `
- Appears in both sent folder and received messages
- Related to format=flowed text formatting
- MailFlow plugin mentioned as potential solution ([MailFlow GitHub](https://github.com/arachsys/mailflow))

### AppleScript Limitations

**No message format control via AppleScript properties:*

- `message format` property does not exist
- `properties {content: "..."}` creates rich text by default
- Cannot set `Content-Transfer-Encoding` headers
- Cannot disable HTML alternative generation
- System Events menu clicking requires `visible:true` windows

## Attempted Solutions

### 1. Double Leading Spaces Strategy

**Approach**: Add extra space to context lines to compensate for Mail.app stripping.

Implementation:
```go
func doubleLeadingSpaces(body string) string {
    lines := strings.Split(body, "\n")
    inHunk := false
    for i, line := range lines {
        if strings.HasPrefix(line, "@@") {
            inHunk = true
        }
        if strings.HasPrefix(line, "diff ") {
            inHunk = false
        }
        // Only double spaces on context lines inside hunks
        if inHunk && len(line) > 0 && line[0] == ' ' {
            lines[i] = " " + line
        }
    }
    return strings.Join(lines, "\n")
}
```

**Result**: Doubled spaces (2 spaces) are preserved in sent messages, but:
- Still creates multipart/alternative
- Still adds format=flowed quote markers (`>`)
- Requires un-doubling on export

### 2. HTML with Pre Tags

**Approach**: Send as HTML with `<pre>` tags to preserve all whitespace.

```go
htmlBody := fmt.Sprintf("<html><body><pre>%s</pre></body></html>", escapeHTMLContent(body))
```

**Result**: Works for whitespace preservation but **fails git workflow requirements** - git mailing lists reject HTML.

### 3. System Events Menu Automation

**Approach**: Use System Events to click Format > Make Plain Text menu.

**Result**: Requires `visible:true` message window. Even when successful in UI, sending engine often re-applies formatting/quoting.

### 4. Defaults Write Configuration

**Approach**: Set Mail.app global preferences via `defaults write`.
- `defaults write com.apple.mail DisableFlowedText -bool YES`
- `defaults write com.apple.mail SendFormat -string "Plain"`

**Finding**: Failed to prevent `format=flowed` markers or whitespace stripping in automated sending.

### 5. .eml Draft Injection

**Approach**: Create a raw RFC-822 `.eml` file with `Content-Transfer-Encoding: 8bit` and `Content-Type: text/plain`, open it in Mail.app (`open -a Mail test.eml`), and send via AppleScript.

**Result**: **FAILED**. Mail.app re-encodes the message upon sending.
- Received headers showed `Content-Transfer-Encoding: quoted-printable`.
- Leading whitespace was stripped.
- Proves Mail.app's sending engine aggressively normalizes content regardless of input method.

## Working Solutions

### Account Auto-Detection

**Successfully implemented** - Extract author email from patch `From:` header and match to Mail.app account:

```go
fromHeader := msg.Header.Get("From")
fromEmail := extractEmailAddress(fromHeader)
matchedAccount, err := findAccountByEmail(client, fromEmail)
```

Works correctly when git commit author matches a configured Mail.app account.

### Mbox Parsing for Send

**Successfully implemented** using `github.com/emersion/go-mbox` library:

- Library is production-grade (author of go-imap 2.3k stars, go-smtp 2k stars)
- Latest release: v1.0.4 (June 2025)
- Handles mbox format parsing correctly
- Extracts To, Cc, Bcc, Subject from patch headers

### MIME Decoding for Export

**Partially implemented** - Can extract and decode:

- base64 encoding
- quoted-printable encoding
- Plain text MIME parts

**Issue**: Cannot remove format=flowed quote markers without breaking patch structure.

## Fundamental Incompatibility

**Mail.app is not suitable for sending git patches via AppleScript due to:*

1. Automatic multipart/alternative generation (adds HTML part)
2. Format=flowed quote marker injection
3. No AppleScript control over message format
4. Whitespace handling inconsistencies (stripping context line spaces)
5. **Aggressive Re-encoding**: Even pre-formatted `.eml` files are re-encoded and stripped upon sending.

**Git documentation conspicuously does NOT include Apple Mail** in MUA-specific configuration hints, only mentions:
- Thunderbird
- KMail
- Gmail (with warnings)
- mutt, alpine (recommended)

Source: [Git send-email MUA hints](https://git-scm.com/docs/git-send-email)

## Recommended Approach

### For Sending Patches

**Use `git send-email` directly** with SMTP configuration:

```bash
# Configure git send-email
git config sendemail.smtpserver smtp.gmail.com
git config sendemail.smtpport 587
git config sendemail.smtpencryption tls
git config sendemail.smtpuser rmelton@gmail.com

# Send patches
git send-email HEAD~3..HEAD --to=maintainer@project.org
```

Alternative: msmtp as mail transfer agent
- Recommended in multiple guides ([Setting up git send-email on macOS](https://moz.hashnode.dev/setting-up-git-send-mail-with-macos))
- Full SMTP client with credential storage
- Works reliably with git send-email

### For Receiving Patches

**Use mail-app-cli export** - This works well:

```bash
# Find patches
mail-app-cli search "[PATCH"

# Export and apply
mail-app-cli messages export <id1> <id2> <id3> -a Account -m INBOX | git am
```

**Remaining issue**: Must handle format=flowed markers and multipart decoding.

## Summary

**For git email workflows on macOS:*

**Sending patches**: Use `git send-email` configured with SMTP settings, OR send patches as **attachments** if using Mail.app is mandatory (to avoid credential duplication).

**Receiving patches**: Use `mail-app-cli messages export` to extract from Mail.app

**Mail.app via AppleScript is unsuitable for sending INLINE git patches** due to format=flowed injection, multipart/alternative generation, and whitespace handling limitations that cannot be controlled programmatically.
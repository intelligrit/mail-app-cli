# Performance Characteristics

## The cost model (measured against Mail.app on macOS 26)

Every property read on a JXA object specifier is one Apple event round trip,
and Mail.app answers them serially. Measured costs:

| Operation | Cost |
|-----------|------|
| Launch `osascript` + connect to Mail | ~100 ms |
| One property read on one message (`msg.subject()`) | ~10 ms |
| Bulk property read over a mailbox (`mbox.messages.subject()`) | ~35 µs / message |
| `mbox.messages.length` | ~10 ms (small) – 200 ms (21k messages) |
| `mbox.messages()` (materialize all specifiers) | ~25 ms (small) – 700 ms (21k) |
| `mbox.messages.id()` (bulk ids) | ~400 ms on 21k messages |
| `mbox.messages.byId(n)` | direct specifier, effectively free |
| `mbox.messages.at(i)` | **re-enumerates the mailbox on every access** — never use in a loop |
| `mbox.messages.whose({...})` | ~0.8–1.5 s on 21k messages; bulk property reads on the result are pathologically slow (15 s for 16 messages) |
| `msg.content()` / `msg.properties()` | may block Mail.app's *entire* scripting interface until a body download completes — see below |

## How the CLI uses this

- **Message lookup by ID** uses `byId()`. IDs are unique across the whole Mail
  database, so no enumeration is needed; `messages show/mark/flag/delete/
  archive/move` and attachment commands run in ~0.3 s regardless of mailbox size.
- **Batch mutations** (`messages mark id1 id2 ...`) run in one `osascript`
  process: cost is one launch plus ~10 ms per message.
- **`messages list`** is hybrid. Filters (`--unread`, `--flagged`, `--since`)
  always use one bulk read per property. Then:
  - if the mailbox is small relative to the page (`total <= max(2000, page*300)`)
    every field is bulk-read — a 40-message INBOX lists in ~0.2 s;
  - otherwise only the ids are bulk-read and the page's messages are resolved
    with `byId()` and read individually — a 21k-message "All Mail" lists in ~2.5 s.
- **`mailboxes list`** bulk-reads names and unread counts. `TotalCount` is only
  filled with `--counts` because it needs a `messages.length` per mailbox
  (~3 s across 80 mailboxes vs ~0.7 s without).
- **`mailboxes mark-read`** uses `whose({readStatus: false})` and loops over the
  result; bulk assignment on a `whose()` specifier is not supported. It skips
  mailboxes whose `unreadCount` is already 0.
- Special mailboxes come from Mail's unified `trashMailbox`/`junkMailbox`/...
  properties (`.mailboxes()` gives the per-account boxes), so provider naming
  never matters.

## `--with-content` can hang Mail.app

`msg.content()` (and `msg.properties()`, which includes it) makes Mail's main
thread wait synchronously on a MailCore worker in
`-[MCMessageBody attributedStringBlockingRemoteContent:...]`. If the body is
not cached locally and the fetch stalls, **all** AppleScript/JXA calls from
every process time out until Mail.app is restarted — the client going away does
not unblock it. Observed repeatedly on Gmail spam / "All Mail" messages right
after a Mail restart.

Mitigations: only request content for small, recently synced mailboxes; never
call `--with-content` from unattended jobs against large or junk mailboxes; and
if `osascript -e "Application('Mail').accounts.length"` times out, sample Mail
(`sample Mail 1`) — a stack containing `MCMessage(ScriptingSupport) content`
means it must be restarted.

## Moves change message IDs

When a message is moved (archive, move, delete) Mail assigns it a new ID in the
destination mailbox. Re-list the destination if you need to act on it again.

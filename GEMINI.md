# mail-app-cli

`mail-app-cli` is a Go-based command-line tool that interfaces with macOS Mail.app using AppleScript and JavaScript for Automation (JXA). It allows for managing accounts, mailboxes, messages, and sending emails directly from the terminal.

## Project Overview

- **Language:** Go 1.21+
- **CLI Framework:** [Cobra](https://github.com/spf13/cobra)
- **Integration:** Uses `osascript` to execute JXA (JavaScript for Automation) and AppleScript.
- **Key Dependencies:**
    - `github.com/spf13/cobra`: CLI structure.
    - `github.com/emersion/go-mbox`: Parsing mbox files (for git patch workflow).
- **Core Package:** `pkg/mail/client.go` handles all interactions with Mail.app.

## Development & Build

### Prerequisites
- macOS (Mail.app must be configured).
- Go 1.21 or higher.

### Build Command
```bash
go build -o mail-app-cli
```

### Running Locally
```bash
./mail-app-cli [command] [flags]
```

## Architecture & Conventions

### `pkg/mail/client.go`
This is the heart of the application.
- **JXA (JavaScript for Automation):** Preferred for reading data (Accounts, Mailboxes, Messages) because `JSON.stringify` allows for easy, structured output parsing in Go.
- **AppleScript:** Used for operations where JXA might be limited or for legacy reasons (e.g., `SendMessage`).
- **Escaping:** Critical. Helper functions like `escapeJSString` and `escapeAppleScriptString` prevent syntax errors when injecting Go strings into scripts.
- **JSON Output:** Most methods returning data (like `GetMessagesJSON`) execute JXA that returns a JSON string, which is then unmarshaled into Go structs.

### CLI Commands (`cmd/`)
- Each command (e.g., `messages`, `accounts`) has its own file in `cmd/`.
- Commands generally instantiate a `mail.NewClient()` and call methods on it.
- Output is typically printed as JSON to stdout for easy pipeability (e.g., to `jq`).

### Git Patch Workflow
The project supports a git email workflow (import/export), but with known limitations (detailed in `LEARNING.md`):
- **Sending:** Mail.app automatically adds HTML parts (multipart/alternative) and format=flowed markers, which can corrupt git patches.
- **Receiving:** Exporting works well using `GetMessageSource` to retrieve the raw MIME content.

## Key Files
- `pkg/mail/client.go`: JXA/AppleScript execution engine and business logic.
- `cmd/*.go`: CLI command definitions.
- `LEARNING.md`: Critical documentation on the limitations of Mail.app for git workflows.

## Common Tasks

### Adding a New Feature
1.  **Identify the Mail.app Scripting Bridge capability:** Open Script Editor.app, File > Open Dictionary > Mail.app.
2.  **Implement in `pkg/mail/client.go`:**
    - Prefer JXA for data retrieval.
    - Ensure robust escaping of user input.
    - Return JSON string from the script and unmarshal in Go.
3.  **Add CLI Command:** Create/update the relevant file in `cmd/` to expose the functionality.

### Debugging
- AppleScript/JXA errors are returned as Go errors.
- To debug scripts, it's often helpful to print the generated script to stdout before execution to test it directly in Script Editor.

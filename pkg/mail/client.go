package mail

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

// Client provides an interface to interact with Mail.app via AppleScript
type Client struct{}

// NewClient creates a new Mail.app client
func NewClient() *Client {
	return &Client{}
}

// escapeJSString escapes a string for use in JavaScript single-quoted strings.
// Non-ASCII characters (including emoji) are encoded as \uXXXX sequences to
// avoid encoding issues when passing strings through osascript.
func escapeJSString(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\\':
			b.WriteString("\\\\")
		case r == '\'':
			b.WriteString("\\'")
		case r == '\n':
			b.WriteString("\\n")
		case r == '\r':
			b.WriteString("\\r")
		case r == '\t':
			b.WriteString("\\t")
		case r > 0xFFFF:
			// Encode as a surrogate pair for characters outside BMP (e.g. most emoji)
			r -= 0x10000
			hi := 0xD800 + (r>>10)&0x3FF
			lo := 0xDC00 + r&0x3FF
			fmt.Fprintf(&b, "\\u%04X\\u%04X", hi, lo)
		case r >= 0x80:
			fmt.Fprintf(&b, "\\u%04X", r)
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// isInboxName returns true if the mailbox name refers to the built-in INBOX.
func isInboxName(name string) bool {
	return strings.EqualFold(name, "inbox")
}

// jxaResolveMailbox returns JXA code that assigns the target mailbox to a
// variable named varName. For INBOX it uses acc.inbox(); for all other
// mailboxes it uses acc.mailboxes.byName().
func jxaResolveMailbox(varName, accVar, mailboxName string) string {
	if isInboxName(mailboxName) {
		return fmt.Sprintf("const %s = %s.inbox();", varName, accVar)
	}
	return fmt.Sprintf("const %s = %s.mailboxes.byName('%s');", varName, accVar, escapeJSString(mailboxName))
}

// jxaFindMailboxInLoop returns a JXA function definition that can be used
// to find a mailbox by name within an account, handling INBOX specially.
// Call the returned function as: findMailbox(acc, 'INBOX')
func jxaFindMailboxHelper() string {
	return `
function findMailbox(acc, mboxName) {
	if (mboxName.toLowerCase() === 'inbox') {
		try { return acc.inbox(); } catch(e) { return null; }
	}
	const mailboxes = acc.mailboxes();
	for (let j = 0; j < mailboxes.length; j++) {
		if (mailboxes[j].name() === mboxName) return mailboxes[j];
	}
	return null;
}
`
}

// escapeAppleScriptString escapes a string for use in AppleScript double-quoted strings
func escapeAppleScriptString(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\") // Escape backslashes first
	s = strings.ReplaceAll(s, "\"", "\\\"") // Escape double quotes
	return s
}

// runAppleScript executes an AppleScript and returns the output
func (c *Client) runAppleScript(script string) (string, error) {
	cmd := exec.Command("osascript", "-e", script)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("applescript error: %v - %s", err, stderr.String())
	}

	return strings.TrimSpace(out.String()), nil
}

// runJXA executes JavaScript for Automation (JXA) and returns the output
func (c *Client) runJXA(script string) (string, error) {
	cmd := exec.Command("osascript", "-l", "JavaScript", "-e", script)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("jxa error: %v - %s", err, stderr.String())
	}

	return strings.TrimSpace(out.String()), nil
}

// Account represents a Mail.app account
type Account struct {
	ID           string
	Name         string
	EmailAddress string
	AccountType  string
	UserName     string
	Enabled      bool
}

// Mailbox represents a Mail.app mailbox
type Mailbox struct {
	Name        string
	UnreadCount int
	TotalCount  int
	Account     string
}

// Message represents an email message
type Message struct {
	ID            string
	Subject       string
	Sender        string
	DateSent      string
	DateReceived  string
	Read          bool
	Flagged       bool
	Deleted       bool
	MessageSize   int
	Content       string
	Mailbox       string
	Account       string
	ToRecipients  []string
	CcRecipients  []string
	BccRecipients []string
}

// Attachment represents an email attachment
type Attachment struct {
	Name     string
	FileSize int
	MimeType string
}

// GetAccounts retrieves all Mail.app accounts
func (c *Client) GetAccounts() ([]Account, error) {
	script := `
	tell application "Mail"
		set accountList to {}
		repeat with acc in accounts
			set accountInfo to {id:id of acc, name:name of acc, emailAddress:(try
				(email addresses of acc)
			on error
				""
			end try), accountType:(try
				(delivery account of acc) as string
			on error
				"unknown"
			end try), userName:user name of acc, enabled:enabled of acc}
			set end of accountList to accountInfo
		end repeat
		return accountList
	end tell
`
	output, err := c.runAppleScript(script)
	if err != nil {
		return nil, err
	}

	// Parse AppleScript list output
	accounts, err := c.parseAccounts(output)
	return accounts, err
}

// GetMailboxes retrieves all mailboxes for a specific account
func (c *Client) GetMailboxes(accountName string) ([]Mailbox, error) {
	script := fmt.Sprintf(`
	tell application "Mail"
		set mailboxList to {}
		try
			set targetAccount to account "%s"
			repeat with mbox in mailboxes of targetAccount
				set mailboxInfo to {name:(name of mbox), unreadCount:(unread count of mbox), totalCount:(count of messages in mbox), account:(name of targetAccount)}
				set end of mailboxList to mailboxInfo
			end repeat
		end try
		return mailboxList
	end tell
`, escapeAppleScriptString(accountName))

	output, err := c.runAppleScript(script)
	if err != nil {
		return nil, err
	}

	mailboxes, err := c.parseMailboxes(output)
	return mailboxes, err
}

// GetAllMailboxes retrieves all mailboxes across all accounts
func (c *Client) GetAllMailboxes() ([]Mailbox, error) {
	script := `
	tell application "Mail"
		set mailboxList to {}
		repeat with acc in accounts
			repeat with mbox in mailboxes of acc
				set mailboxInfo to {name:(name of mbox), unreadCount:(unread count of mbox), totalCount:(count of messages in mbox), account:(name of acc)}
				set end of mailboxList to mailboxInfo
			end repeat
		end repeat
		return mailboxList
	end tell
`
	output, err := c.runAppleScript(script)
	if err != nil {
		return nil, err
	}

	mailboxes, err := c.parseMailboxes(output)
	return mailboxes, err
}

// GetMessages retrieves messages from a mailbox
func (c *Client) GetMessages(accountName, mailboxName string, limit int) ([]Message, error) {
	limitClause := ""
	if limit > 0 {
		limitClause = fmt.Sprintf("if msgCount > %d then set msgCount to %d", limit, limit)
	}

	script := fmt.Sprintf(`
	tell application "Mail"
		set messageList to {}
		try
			set targetAccount to account "%s"
			set targetMailbox to mailbox "%s" of targetAccount
			set msgCount to count of messages in targetMailbox
			%s

			repeat with i from 1 to msgCount
				set msg to message i of targetMailbox
				set msgInfo to {subject:(subject of msg), sender:(sender of msg), dateSent:(date sent of msg as string), dateReceived:(date received of msg as string), isRead:(read status of msg), isFlagged:(flagged status of msg), messageSize:(message size of msg)}
				set end of messageList to msgInfo
			end repeat
		end try
		return messageList
	end tell
`, escapeAppleScriptString(accountName), escapeAppleScriptString(mailboxName), limitClause)

	output, err := c.runAppleScript(script)
	if err != nil {
		return nil, err
	}

	messages, err := c.parseMessages(output)
	return messages, err
}

// SearchMessages searches for messages matching a query
func (c *Client) SearchMessages(query string, limit int) ([]Message, error) {
	limitClause := ""
	if limit > 0 {
		limitClause = fmt.Sprintf("if msgCount > %d then set msgCount to %d", limit, limit)
	}

	// query is injected into AppleScript double quotes, needs escaping
	script := fmt.Sprintf(`
	tell application "Mail"
		set messageList to {}
		set foundMessages to (every message whose subject contains "%s" or sender contains "%s" or content contains "%s")
		set msgCount to count of foundMessages
		%s

		repeat with i from 1 to msgCount
			set msg to item i of foundMessages
			try
				set msgInfo to {subject:(subject of msg), sender:(sender of msg), dateSent:(date sent of msg as string), dateReceived:(date received of msg as string), isRead:(read status of msg), isFlagged:(flagged status of msg), messageSize:(message size of msg)}
				set end of messageList to msgInfo
			end try
		end repeat
		return messageList
	end tell
`, escapeAppleScriptString(query), escapeAppleScriptString(query), escapeAppleScriptString(query), limitClause)

	output, err := c.runAppleScript(script)
	if err != nil {
		return nil, err
	}

	messages, err := c.parseMessages(output)
	return messages, err
}

// MarkMessageAsRead marks a message as read
func (c *Client) MarkMessageAsRead(accountName, mailboxName, messageID string, read bool) error {
	readStatus := "true"
	if !read {
		readStatus = "false"
	}

	mboxResolve := jxaResolveMailbox("mbox", "acc", mailboxName)
	script := fmt.Sprintf(`
const mail = Application('Mail');
try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = mbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		targetMsg.readStatus = %s;
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), mboxResolve, escapeJSString(messageID), readStatus)

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// FlagMessage sets or unsets the flagged status of a message
func (c *Client) FlagMessage(accountName, mailboxName, messageID string, flagged bool) error {
	flagStatus := "true"
	if !flagged {
		flagStatus = "false"
	}

	mboxResolve := jxaResolveMailbox("mbox", "acc", mailboxName)
	script := fmt.Sprintf(`
const mail = Application('Mail');
try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = mbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		targetMsg.flaggedStatus = %s;
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), mboxResolve, escapeJSString(messageID), flagStatus)

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// DeleteMessage moves a message to trash
func (c *Client) DeleteMessage(accountName, mailboxName, messageID string) error {
	mboxResolve := jxaResolveMailbox("mbox", "acc", mailboxName)
	script := fmt.Sprintf(`
const mail = Application('Mail');
try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = mbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		targetMsg.delete();
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), mboxResolve, escapeJSString(messageID))

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// SendMessage sends a new email message
func (c *Client) SendMessage(accountName, subject, body string, to, cc, bcc, attachments []string) error {
	// Escape all recipients
	var toList, ccList, bccList string
	var escapedTo, escapedCc, escapedBcc []string

	for _, addr := range to {
		escapedTo = append(escapedTo, escapeAppleScriptString(addr))
	}
	toList = strings.Join(escapedTo, `", "`)

	for _, addr := range cc {
		escapedCc = append(escapedCc, escapeAppleScriptString(addr))
	}
	ccList = strings.Join(escapedCc, `", "`)

	for _, addr := range bcc {
		escapedBcc = append(escapedBcc, escapeAppleScriptString(addr))
	}
	bccList = strings.Join(escapedBcc, `", "`)

	// Build attachment code
	attachCode := ""
	if len(attachments) > 0 {
		for _, attPath := range attachments {
			// Attachments use JXA-like escaping in our helper? No, this is AppleScript block.
			// "make new attachment with properties {file name:"%s"}..."
			escapedPath := escapeAppleScriptString(attPath)
			attachCode += fmt.Sprintf(`
			try
				make new attachment with properties {file name:"%s"} at after the last paragraph
			on error
				-- Skip files that can't be attached
			end try
`, escapedPath)
		}
	}

	// AppleScript block
	script := fmt.Sprintf(`
	tell application "Mail"
		try
			set targetAccount to account "%s"
			set newMessage to make new outgoing message with properties {subject:"%s", content:"%s", visible:false}

			tell newMessage
				set sender to (item 1 of (email addresses of targetAccount as list))

				repeat with addr in {"%s"}
					make new to recipient at end of to recipients with properties {address:addr}
				end repeat

				if "%s" is not "" then
					repeat with addr in {"%s"}
						make new cc recipient at end of cc recipients with properties {address:addr}
					end repeat
				end if

				if "%s" is not "" then
					repeat with addr in {"%s"}
						make new bcc recipient at end of bcc recipients with properties {address:addr}
					end repeat
				end if
%s
			send
			end tell
			return "Success"
		on error errMsg
			return "Error: " & errMsg
		end try
	end tell
`, escapeAppleScriptString(accountName), escapeAppleScriptString(subject), escapeAppleScriptString(body),
		toList,
		ccList, ccList,
		bccList, bccList,
		attachCode)

	_, err := c.runAppleScript(script)
	return err
}

// Helper function to parse accounts from AppleScript output
func (c *Client) parseAccounts(output string) ([]Account, error) {
	// AppleScript returns records as comma-separated values
	// This is a simplified parser - may need enhancement based on actual output format
	accounts := []Account{}

	// For now, return empty list - need to see actual output format to implement properly
	// TODO: Implement proper parsing based on AppleScript record format

	return accounts, nil
}

// Helper function to parse mailboxes from AppleScript output
func (c *Client) parseMailboxes(output string) ([]Mailbox, error) {
	mailboxes := []Mailbox{}
	// TODO: Implement proper parsing based on AppleScript record format
	return mailboxes, nil
}

// Helper function to parse messages from AppleScript output
func (c *Client) parseMessages(output string) ([]Message, error) {
	messages := []Message{}
	// TODO: Implement proper parsing based on AppleScript record format
	return messages, nil
}

// GetUnreadCount gets the total unread message count
func (c *Client) GetUnreadCount() (int, error) {
	script := `
	tell application "Mail"
		set totalUnread to 0
		repeat with acc in accounts
			repeat with mbox in mailboxes of acc
				set totalUnread to totalUnread + (unread count of mbox)
			end repeat
		end repeat
		return totalUnread
	end tell
`
	output, err := c.runAppleScript(script)
	if err != nil {
		return 0, err
	}

	var count int
	fmt.Sscanf(output, "%d", &count)
	return count, nil
}

// Helper to convert AppleScript output to JSON for easier parsing
func (c *Client) executeJXAForJSON(jxaScript string) (string, error) {
	script := fmt.Sprintf(`
%s
JSON.stringify(result)
`, jxaScript)
	return c.runJXA(script)
}

// GetAccountsJSON retrieves accounts as JSON using JXA
func (c *Client) GetAccountsJSON() ([]Account, error) {
	script := `
const mail = Application('Mail');
const accounts = mail.accounts();
const result = [];

for (let i = 0; i < accounts.length; i++) {
	const acc = accounts[i];
	result.push({
		id: acc.id(),
		name: acc.name(),
		emailAddress: acc.emailAddresses().length > 0 ? acc.emailAddresses()[0] : '',
		userName: acc.userName(),
		enabled: acc.enabled()
	});
}

JSON.stringify(result);
`
	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var accounts []Account
	if err := json.Unmarshal([]byte(output), &accounts); err != nil {
		return nil, fmt.Errorf("failed to parse accounts JSON: %w", err)
	}

	return accounts, nil
}

// SyncAccount forces Mail.app to check for new mail (syncs all accounts)
// Note: Mail.app's AppleScript doesn't support per-account sync, so this syncs all accounts
func (c *Client) SyncAccount(accountName string) error {
	// Verify account exists
	script := fmt.Sprintf(`
	tell application "Mail"
		set accountFound to false
		repeat with acc in accounts
			if name of acc is "%s" then
				set accountFound to true
				exit repeat
			end if
		end repeat
		if not accountFound then
			error "Account not found: %s"
		end if
	end tell
`, escapeAppleScriptString(accountName), escapeAppleScriptString(accountName))

	_, err := c.runAppleScript(script)
	if err != nil {
		return err
	}

	// Check for new mail (syncs all accounts)
	return c.SyncAllAccounts()
}

// SyncAllAccounts forces Mail.app to check for new mail across all accounts
func (c *Client) SyncAllAccounts() error {
	script := `tell application "Mail" to check for new mail`
	_, err := c.runAppleScript(script)
	return err
}

// GetMailboxesJSON retrieves mailboxes as JSON using JXA
func (c *Client) GetMailboxesJSON(accountName string) ([]Mailbox, error) {
	// If specific account requested, use single JXA call
	if accountName != "" {
		return c.getMailboxesForSingleAccount(accountName)
	}

	// For all accounts, fetch in parallel for better performance
	accounts, err := c.GetAccountsJSON()
	if err != nil {
		return nil, fmt.Errorf("failed to get accounts: %w", err)
	}

	if len(accounts) == 0 {
		return []Mailbox{}, nil
	}

	// If only one account total, no need for parallelization
	if len(accounts) == 1 {
		return c.getMailboxesForSingleAccount(accounts[0].Name)
	}

	// Use channel to collect results from goroutines
	type result struct {
		mailboxes []Mailbox
		err       error
	}
	results := make(chan result, len(accounts))

	// Launch goroutine for each account
	for _, account := range accounts {
		go func(accName string) {
			mailboxes, err := c.getMailboxesForSingleAccount(accName)
			results <- result{mailboxes: mailboxes, err: err}
		}(account.Name)
	}

	// Collect results
	var allMailboxes []Mailbox
	var errors []error
	for i := 0; i < len(accounts); i++ {
		res := <-results
		if res.err != nil {
			errors = append(errors, res.err)
		} else {
			allMailboxes = append(allMailboxes, res.mailboxes...)
		}
	}

	// Return partial results even if some accounts failed
	if len(errors) > 0 && len(allMailboxes) == 0 {
		return nil, fmt.Errorf("failed to get mailboxes from all accounts: %v", errors)
	}

	return allMailboxes, nil
}

// getMailboxesForSingleAccount retrieves mailboxes for a specific account
func (c *Client) getMailboxesForSingleAccount(accountName string) ([]Mailbox, error) {
	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];

try {
	const accounts = mail.accounts();
	for (let i = 0; i < accounts.length; i++) {
		const acc = accounts[i];
		if (acc.name() === '%s') {
			// Include the built-in INBOX which is not part of acc.mailboxes()
			try {
				const inbox = acc.inbox();
				if (inbox) {
					const inboxMsgs = inbox.messages();
					result.push({
						name: 'INBOX',
						unreadCount: inbox.unreadCount(),
						totalCount: inboxMsgs ? inboxMsgs.length : 0,
						account: acc.name()
					});
				}
			} catch (e) {
				// INBOX may not be available for all accounts
			}
			const mailboxes = acc.mailboxes();
			for (let j = 0; j < mailboxes.length; j++) {
				const mbox = mailboxes[j];
				try {
					const msgs = mbox.messages();
					result.push({
						name: mbox.name(),
						unreadCount: mbox.unreadCount(),
						totalCount: msgs ? msgs.length : 0,
						account: acc.name()
					});
				} catch (e) {
					// Skip mailboxes that can't be queried
				}
			}
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapeJSString(accountName))

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var mailboxes []Mailbox
	if err := json.Unmarshal([]byte(output), &mailboxes); err != nil {
		return nil, fmt.Errorf("failed to parse mailboxes JSON: %w", err)
	}

	return mailboxes, nil
}

// GetMessagesJSON retrieves messages from a mailbox using JXA
func (c *Client) GetMessagesJSON(accountName, mailboxName string, limit, offset int, unreadOnly, flaggedOnly, withContent bool, since string) ([]Message, error) {
	offsetClause := ""
	if offset > 0 {
		offsetClause = fmt.Sprintf("if (messages.length > %d) messages = messages.slice(%d);", offset, offset)
	}

	limitClause := ""
	if limit > 0 {
		limitClause = fmt.Sprintf("if (messages.length > %d) messages = messages.slice(0, %d);", limit, limit)
	}

	unreadFilter := ""
	if unreadOnly {
		unreadFilter = "messages = messages.filter(m => !m.readStatus());"
	}

	flaggedFilter := ""
	if flaggedOnly {
		flaggedFilter = "messages = messages.filter(m => m.flaggedStatus());"
	}

	sinceFilter := ""
	if since != "" {
		// Parse the since date and create a filter
		// JXA can parse date strings in various formats
		sinceFilter = fmt.Sprintf("const sinceDate = new Date('%s'); messages = messages.filter(m => { const msgDate = m.dateReceived(); return msgDate && msgDate >= sinceDate; });", escapeJSString(since))
	}

	contentField := ""
	if withContent {
		contentField = "content: msg.content() || '',"
	} else {
		contentField = "content: '',"
	}

	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
%s

try {
	const accounts = mail.accounts();
	for (let i = 0; i < accounts.length; i++) {
		const acc = accounts[i];
		if (acc.name() === '%s') {
			const mbox = findMailbox(acc, '%s');
			if (mbox) {
					let messages = mbox.messages();
					// Apply filters BEFORE iterating for performance
					%s
					%s
					%s
					%s
					%s

					// Only iterate through limited set for performance on large mailboxes
					const maxToProcess = %d > 0 ? Math.min(%d * 3, messages.length) : Math.min(1000, messages.length);
					for (let k = 0; k < maxToProcess && result.length < %d; k++) {
						const msg = messages[k];
						// Skip deleted messages inline for performance
						try { if (msg.deletedStatus()) continue; } catch(e) {}
						try {
							result.push({
								id: String(msg.id()),
								subject: msg.subject() || '',
								sender: msg.sender() || '',
								dateReceived: (msg.dateReceived() || new Date()).toString(),
								dateSent: (msg.dateSent() || new Date()).toString(),
								read: msg.readStatus(),
								flagged: msg.flaggedStatus(),
								messageSize: 0,
								%s
							mailbox: '%s',
								account: acc.name()
							});
						} catch (e) {
							// Skip messages that cause errors
						}
					}
			}
			break;
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, jxaFindMailboxHelper(), escapeJSString(accountName), escapeJSString(mailboxName), unreadFilter, flaggedFilter, sinceFilter, offsetClause, limitClause, limit, limit, limit, contentField, escapeJSString(mailboxName))

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var messages []Message
	if err := json.Unmarshal([]byte(output), &messages); err != nil {
		return nil, fmt.Errorf("failed to parse messages JSON: %w", err)
	}

	return messages, nil
}

// GetMessageDetailsJSON retrieves full details of a specific message
func (c *Client) GetMessageDetailsJSON(accountName, mailboxName, messageID string) (*Message, error) {
	script := fmt.Sprintf(`
const mail = Application('Mail');
let result = null;
%s

try {
	const accounts = mail.accounts();
	for (let i = 0; i < accounts.length; i++) {
		const acc = accounts[i];
		if (acc.name() === '%s') {
			const mbox = findMailbox(acc, '%s');
			if (mbox) {
				const messages = mbox.messages();
				for (let k = 0; k < messages.length; k++) {
					const msg = messages[k];
					if (String(msg.id()) === '%s') {
						const toRecipients = [];
						const toRecs = msg.toRecipients();
						for (let t = 0; t < toRecs.length; t++) {
							toRecipients.push(toRecs[t].address());
						}

						const ccRecipients = [];
						const ccRecs = msg.ccRecipients();
						for (let c = 0; c < ccRecs.length; c++) {
							ccRecipients.push(ccRecs[c].address());
						}

						const bccRecipients = [];
						const bccRecs = msg.bccRecipients();
						for (let b = 0; b < bccRecs.length; b++) {
							bccRecipients.push(bccRecs[b].address());
						}

						result = {
							id: String(msg.id()),
							subject: msg.subject() || '',
							sender: msg.sender() || '',
							dateReceived: (msg.dateReceived() || new Date()).toString(),
							dateSent: (msg.dateSent() || new Date()).toString(),
							read: msg.readStatus(),
							flagged: msg.flaggedStatus(),
							messageSize: msg.messageSize(),
							content: msg.content() || '',
							mailbox: '%s',
							account: acc.name(),
							toRecipients: toRecipients,
							ccRecipients: ccRecipients,
							bccRecipients: bccRecipients
						};
						break;
					}
				}
			}
			break;
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, jxaFindMailboxHelper(), escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID), escapeJSString(mailboxName))

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var message Message
	if err := json.Unmarshal([]byte(output), &message); err != nil {
		return nil, fmt.Errorf("failed to parse message JSON: %w", err)
	}

	return &message, nil
}

// ArchiveMessage moves a message to the Archive mailbox
func (c *Client) ArchiveMessage(accountName, mailboxName, messageID string) error {
	mboxResolve := jxaResolveMailbox("mbox", "acc", mailboxName)
	script := fmt.Sprintf(`
const mail = Application('Mail');
try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = mbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		const allMailboxes = acc.mailboxes();
		let archiveBox = null;
		for (let j = 0; j < allMailboxes.length; j++) {
			const name = allMailboxes[j].name();
			if (name === 'Archive' || name === 'All Mail') {
				archiveBox = allMailboxes[j];
				break;
			}
		}

		if (archiveBox) {
			targetMsg.mailbox = archiveBox;
			'Success';
		} else {
			'Error: Archive mailbox not found';
		}
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), mboxResolve, escapeJSString(messageID))

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// MoveMessage moves a message to a different mailbox
func (c *Client) MoveMessage(accountName, sourceMailbox, messageID, targetMailbox string) error {
	srcResolve := jxaResolveMailbox("sourceMbox", "acc", sourceMailbox)
	destResolve := jxaResolveMailbox("destMbox", "acc", targetMailbox)
	script := fmt.Sprintf(`
const mail = Application('Mail');
try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = sourceMbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		%s
		targetMsg.mailbox = destMbox;
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), srcResolve, escapeJSString(messageID), destResolve)

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// GetAttachmentsJSON retrieves attachments from a message
func (c *Client) GetAttachmentsJSON(accountName, mailboxName, messageID string) ([]Attachment, error) {
	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
%s

try {
	const accounts = mail.accounts();
	for (let i = 0; i < accounts.length; i++) {
		const acc = accounts[i];
		if (acc.name() === '%s') {
			const mbox = findMailbox(acc, '%s');
			if (mbox) {
				const messages = mbox.messages();
				for (let k = 0; k < messages.length; k++) {
					const msg = messages[k];
					if (String(msg.id()) === '%s') {
						const attachments = msg.mailAttachments();
						for (let a = 0; a < attachments.length; a++) {
							const att = attachments[a];
							let mimeType = 'unknown';
							try {
								mimeType = att.mimeType() || 'unknown';
							} catch (e) {
								// mimeType() sometimes fails in Mail.app
							}
							result.push({
								name: att.name(),
								fileSize: att.fileSize(),
								mimeType: mimeType
							});
						}
						break;
					}
				}
			}
			break;
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, jxaFindMailboxHelper(), escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var attachments []Attachment
	if err := json.Unmarshal([]byte(output), &attachments); err != nil {
		return nil, fmt.Errorf("failed to parse attachments JSON: %w", err)
	}

	return attachments, nil
}

// SaveAttachment saves an attachment to disk
func (c *Client) SaveAttachment(accountName, mailboxName, messageID, attachmentName, savePath string) error {
	mboxResolve := jxaResolveMailbox("mbox", "acc", mailboxName)
	script := fmt.Sprintf(`
const mail = Application('Mail');
const app = Application.currentApplication();
app.includeStandardAdditions = true;

try {
	const acc = mail.accounts.byName('%s');
	%s
	const messages = mbox.messages();

	let targetMsg = null;
	for (let i = 0; i < messages.length; i++) {
		if (String(messages[i].id()) === '%s') {
			targetMsg = messages[i];
			break;
		}
	}

	if (!targetMsg) {
		'Error: Message not found';
	} else {
		const attachments = targetMsg.mailAttachments();
		let found = false;
		for (let a = 0; a < attachments.length; a++) {
			if (attachments[a].name() === '%s') {
				const pathObj = Path('%s');
				attachments[a].save({ in: pathObj });
				found = true;
				break;
			}
		}
		if (found) {
			'Success';
		} else {
			'Error: Attachment not found';
		}
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), mboxResolve, escapeJSString(messageID), escapeJSString(attachmentName), escapeJSString(savePath))

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// SearchMessagesJSON searches for messages across mailboxes
// Note: By default only searches INBOX mailboxes for performance reasons
func (c *Client) SearchMessagesJSON(query string, accountName string, mailboxName string, limit int) ([]Message, error) {
	// Set a reasonable default limit if none specified
	if limit == 0 {
		limit = 50
	}

	// If specific mailbox requested, use single JXA call for simplicity
	if mailboxName != "" {
		return c.searchMessagesInSingleMailbox(query, accountName, mailboxName, limit)
	}

	// Get list of mailboxes to search
	mailboxes, err := c.GetMailboxesJSON(accountName)
	if err != nil {
		return nil, fmt.Errorf("failed to get mailboxes: %w", err)
	}

	// Filter to only INBOX mailboxes for performance (unless specific account given)
	var mailboxesToSearch []Mailbox
	for _, mbox := range mailboxes {
		if mbox.Name == "INBOX" || mbox.Name == "Inbox" {
			mailboxesToSearch = append(mailboxesToSearch, mbox)
		}
	}

	if len(mailboxesToSearch) == 0 {
		return []Message{}, nil
	}

	// If only one mailbox, no need for parallelization
	if len(mailboxesToSearch) == 1 {
		return c.searchMessagesInSingleMailbox(query, mailboxesToSearch[0].Account, mailboxesToSearch[0].Name, limit)
	}

	// Search mailboxes in parallel
	type result struct {
		messages []Message
		err      error
	}
	results := make(chan result, len(mailboxesToSearch))

	// Launch goroutine for each mailbox
	for _, mbox := range mailboxesToSearch {
		go func(accName, mboxName string) {
			messages, err := c.searchMessagesInSingleMailbox(query, accName, mboxName, limit)
			results <- result{messages: messages, err: err}
		}(mbox.Account, mbox.Name)
	}

	// Collect results
	var allMessages []Message
	var errors []error
	for i := 0; i < len(mailboxesToSearch); i++ {
		res := <-results
		if res.err != nil {
			errors = append(errors, res.err)
		} else {
			allMessages = append(allMessages, res.messages...)
		}
	}

	// Return partial results even if some mailboxes failed
	if len(errors) > 0 && len(allMessages) == 0 {
		return nil, fmt.Errorf("failed to search all mailboxes: %v", errors)
	}

	// Sort by date received (newest first) and apply limit
	sort.Slice(allMessages, func(i, j int) bool {
		return allMessages[i].DateReceived > allMessages[j].DateReceived
	})

	if len(allMessages) > limit {
		allMessages = allMessages[:limit]
	}

	return allMessages, nil
}

// searchMessagesInSingleMailbox searches for messages in a specific mailbox
func (c *Client) searchMessagesInSingleMailbox(query, accountName, mailboxName string, limit int) ([]Message, error) {
	// Use helper for escaping
	escapedQuery := escapeJSString(query)
	escapedAccount := escapeJSString(accountName)
	escapedMailbox := escapeJSString(mailboxName)

	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
const searchTerm = '%s'.toLowerCase();
const targetAccount = '%s';
const targetMailbox = '%s';
const maxResults = %d;
%s

try {
	const accounts = mail.accounts();
	outerLoop: for (let i = 0; i < accounts.length; i++) {
		const acc = accounts[i];

		// Skip if account specified and this isn't it
		if (targetAccount !== '' && acc.name() !== targetAccount) {
			continue;
		}

		const mbox = findMailbox(acc, targetMailbox);
		if (!mbox) continue;

		const messages = mbox.messages();
		// Limit how many messages to check per mailbox for performance
		// Messages are typically sorted newest first, so this checks recent messages
		const maxToCheck = Math.min(messages.length, 500);

		for (let k = 0; k < maxToCheck; k++) {
			if (result.length >= maxResults) {
				break outerLoop;
			}

			const msg = messages[k];
			try {
				const subject = (msg.subject() || '').toLowerCase();
				const sender = (msg.sender() || '').toLowerCase();

				// Only search subject and sender
				if (subject.includes(searchTerm) || sender.includes(searchTerm)) {
					result.push({
						id: String(msg.id()),
						subject: msg.subject() || '',
						sender: msg.sender() || '',
						dateReceived: (msg.dateReceived() || new Date()).toString(),
						dateSent: (msg.dateSent() || new Date()).toString(),
						read: msg.readStatus(),
						flagged: msg.flaggedStatus(),
						messageSize: msg.messageSize(),
						mailbox: targetMailbox,
						account: acc.name()
					});
				}
			} catch (e) {
				// Skip messages that cause errors
			}
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapedQuery, escapedAccount, escapedMailbox, limit, jxaFindMailboxHelper())

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var messages []Message
	if err := json.Unmarshal([]byte(output), &messages); err != nil {
		return nil, fmt.Errorf("failed to parse search results JSON: %w", err)
	}

	return messages, nil
}

// GetMessagesFromMultipleMailboxes loads messages from multiple mailboxes concurrently
func (c *Client) GetMessagesFromMultipleMailboxes(requests []struct {
	AccountName  string
	MailboxName  string
	Limit        int
	Offset       int
	UnreadOnly   bool
	FlaggedOnly  bool
	WithContent  bool
	Since        string
}) ([]Message, error) {
	if len(requests) == 0 {
		return []Message{}, nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.GetMessagesJSON(req.AccountName, req.MailboxName, req.Limit, req.Offset, req.UnreadOnly, req.FlaggedOnly, req.WithContent, req.Since)
	}

	// Load messages from multiple mailboxes in parallel
	type result struct {
		messages []Message
		err      error
	}
	results := make(chan result, len(requests))

	// Launch goroutine for each mailbox
	for _, req := range requests {
		go func(r struct {
			AccountName  string
			MailboxName  string
			Limit        int
			Offset       int
			UnreadOnly   bool
			FlaggedOnly  bool
			WithContent  bool
			Since        string
		}) {
			messages, err := c.GetMessagesJSON(r.AccountName, r.MailboxName, r.Limit, r.Offset, r.UnreadOnly, r.FlaggedOnly, r.WithContent, r.Since)
			results <- result{messages: messages, err: err}
		}(req)
	}

	// Collect results
	var allMessages []Message
	var errors []error
	for i := 0; i < len(requests); i++ {
		res := <-results
		if res.err != nil {
			errors = append(errors, res.err)
		} else {
			allMessages = append(allMessages, res.messages...)
		}
	}

	// Return partial results even if some mailboxes failed
	if len(errors) > 0 && len(allMessages) == 0 {
		return nil, fmt.Errorf("failed to get messages from all mailboxes: %v", errors)
	}

	return allMessages, nil
}

// GetMultipleMessageDetails loads full details for multiple messages concurrently
func (c *Client) GetMultipleMessageDetails(requests []struct {
	AccountName  string
	MailboxName  string
	MessageID    string
}) ([]*Message, error) {
	if len(requests) == 0 {
		return []*Message{}, nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		msg, err := c.GetMessageDetailsJSON(req.AccountName, req.MailboxName, req.MessageID)
		if err != nil {
			return nil, err
		}
		return []*Message{msg}, nil
	}

	// Load message details in parallel
	type result struct {
		message *Message
		err     error
		index   int
	}
	results := make(chan result, len(requests))

	// Launch goroutine for each message
	for i, req := range requests {
		go func(idx int, r struct {
			AccountName  string
			MailboxName  string
			MessageID    string
		}) {
			message, err := c.GetMessageDetailsJSON(r.AccountName, r.MailboxName, r.MessageID)
			results <- result{message: message, err: err, index: idx}
		}(i, req)
	}

	// Collect results in original order
	messages := make([]*Message, len(requests))
	var errors []error
	successCount := 0

	for i := 0; i < len(requests); i++ {
		res := <-results
		if res.err != nil {
			errors = append(errors, res.err)
			messages[res.index] = nil
		} else {
			messages[res.index] = res.message
			successCount++
		}
	}

	// Return error if all requests failed
	if successCount == 0 {
		return nil, fmt.Errorf("failed to get all message details: %v", errors)
	}

	return messages, nil
}

// BulkMarkMessages marks multiple messages as read/unread concurrently
func (c *Client) BulkMarkMessages(requests []struct {
	AccountName string
	MailboxName string
	MessageID   string
	Read        bool
}) error {
	if len(requests) == 0 {
		return nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.MarkMessageAsRead(req.AccountName, req.MailboxName, req.MessageID, req.Read)
	}

	// Process marks in parallel
	errors := make(chan error, len(requests))

	// Launch goroutine for each mark operation
	for _, req := range requests {
		go func(r struct {
			AccountName string
			MailboxName string
			MessageID   string
			Read        bool
		}) {
			errors <- c.MarkMessageAsRead(r.AccountName, r.MailboxName, r.MessageID, r.Read)
		}(req)
	}

	// Collect results
	var errorList []error
	for i := 0; i < len(requests); i++ {
		if err := <-errors; err != nil {
			errorList = append(errorList, err)
		}
	}

	if len(errorList) > 0 {
		return fmt.Errorf("failed to mark some messages: %v", errorList)
	}

	return nil
}

// BulkFlagMessages flags/unflags multiple messages concurrently
func (c *Client) BulkFlagMessages(requests []struct {
	AccountName string
	MailboxName string
	MessageID   string
	Flagged     bool
}) error {
	if len(requests) == 0 {
		return nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.FlagMessage(req.AccountName, req.MailboxName, req.MessageID, req.Flagged)
	}

	// Process flags in parallel
	errors := make(chan error, len(requests))

	// Launch goroutine for each flag operation
	for _, req := range requests {
		go func(r struct {
			AccountName string
			MailboxName string
			MessageID   string
			Flagged     bool
		}) {
			errors <- c.FlagMessage(r.AccountName, r.MailboxName, r.MessageID, r.Flagged)
		}(req)
	}

	// Collect results
	var errorList []error
	for i := 0; i < len(requests); i++ {
		if err := <-errors; err != nil {
			errorList = append(errorList, err)
		}
	}

	if len(errorList) > 0 {
		return fmt.Errorf("failed to flag some messages: %v", errorList)
	}

	return nil
}

// BulkDeleteMessages deletes multiple messages concurrently
func (c *Client) BulkDeleteMessages(requests []struct {
	AccountName string
	MailboxName string
	MessageID   string
}) error {
	if len(requests) == 0 {
		return nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.DeleteMessage(req.AccountName, req.MailboxName, req.MessageID)
	}

	// Process deletes in parallel
	errors := make(chan error, len(requests))

	// Launch goroutine for each delete operation
	for _, req := range requests {
		go func(r struct {
			AccountName string
			MailboxName string
			MessageID   string
		}) {
			errors <- c.DeleteMessage(r.AccountName, r.MailboxName, r.MessageID)
		}(req)
	}

	// Collect results
	var errorList []error
	for i := 0; i < len(requests); i++ {
		if err := <-errors; err != nil {
			errorList = append(errorList, err)
		}
	}

	if len(errorList) > 0 {
		return fmt.Errorf("failed to delete some messages: %v", errorList)
	}

	return nil
}

// BulkArchiveMessages archives multiple messages concurrently
func (c *Client) BulkArchiveMessages(requests []struct {
	AccountName string
	MailboxName string
	MessageID   string
}) error {
	if len(requests) == 0 {
		return nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.ArchiveMessage(req.AccountName, req.MailboxName, req.MessageID)
	}

	// Process archives in parallel
	errors := make(chan error, len(requests))

	// Launch goroutine for each archive operation
	for _, req := range requests {
		go func(r struct {
			AccountName string
			MailboxName string
			MessageID   string
		}) {
			errors <- c.ArchiveMessage(r.AccountName, r.MailboxName, r.MessageID)
		}(req)
	}

	// Collect results
	var errorList []error
	for i := 0; i < len(requests); i++ {
		if err := <-errors; err != nil {
			errorList = append(errorList, err)
		}
	}

	if len(errorList) > 0 {
		return fmt.Errorf("failed to archive some messages: %v", errorList)
	}

	return nil
}

// BulkMoveMessages moves multiple messages concurrently
func (c *Client) BulkMoveMessages(requests []struct {
	AccountName    string
	SourceMailbox  string
	MessageID      string
	TargetMailbox  string
}) error {
	if len(requests) == 0 {
		return nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.MoveMessage(req.AccountName, req.SourceMailbox, req.MessageID, req.TargetMailbox)
	}

	// Process moves in parallel
	errors := make(chan error, len(requests))

	// Launch goroutine for each move operation
	for _, req := range requests {
		go func(r struct {
			AccountName    string
			SourceMailbox  string
			MessageID      string
			TargetMailbox  string
		}) {
			errors <- c.MoveMessage(r.AccountName, r.SourceMailbox, r.MessageID, r.TargetMailbox)
		}(req)
	}

	// Collect results
	var errorList []error
	for i := 0; i < len(requests); i++ {
		if err := <-errors; err != nil {
			errorList = append(errorList, err)
		}
	}

	if len(errorList) > 0 {
		return fmt.Errorf("failed to move some messages: %v", errorList)
	}

	return nil
}

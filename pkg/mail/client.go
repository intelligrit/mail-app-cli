package mail

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Client provides an interface to interact with Mail.app via AppleScript
type Client struct{}

// NewClient creates a new Mail.app client
func NewClient() *Client {
	return &Client{}
}

// escapeJSString escapes a string for use in JavaScript single-quoted strings
func escapeJSString(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\") // Escape backslashes first
	s = strings.ReplaceAll(s, "'", "\\'")   // Escape single quotes
	s = strings.ReplaceAll(s, "\n", "\\n")  // Escape newlines
	s = strings.ReplaceAll(s, "\r", "\\r")  // Escape carriage returns
	s = strings.ReplaceAll(s, "\t", "\\t")  // Escape tabs
	return s
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
// jsResolveMailbox defines a JXA helper that resolves a mailbox by walking
// the account's mailbox tree. byName() specifiers are broken for Gmail
// special mailboxes like "All Mail" ("Can't get object"), so scripts must
// match names against enumerated mailbox objects instead.
const jsResolveMailbox = `
function resolveMailbox(acc, name) {
	function walk(mailboxes) {
		for (let j = 0; j < mailboxes.length; j++) {
			if (mailboxes[j].name() === name) return mailboxes[j];
			try {
				const sub = mailboxes[j].mailboxes();
				if (sub.length > 0) {
					const found = walk(sub);
					if (found) return found;
				}
			} catch (e) {}
		}
		return null;
	}
	return walk(acc.mailboxes());
}
`

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

	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else {
		mbox.messages.at(targetIdx).readStatus = %s;
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID), readStatus)

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

	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else {
		mbox.messages.at(targetIdx).flaggedStatus = %s;
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID), flagStatus)

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
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else {
		mbox.messages.at(targetIdx).delete();
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

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
	var attachCodeBuilder strings.Builder
	for _, attPath := range attachments {
		escapedPath := escapeAppleScriptString(attPath)
		fmt.Fprintf(&attachCodeBuilder, `
			try
				make new attachment with properties {file name:"%s"} at after the last paragraph
			on error
				-- Skip files that can't be attached
			end try
`, escapedPath)
	}
	attachCode := attachCodeBuilder.String()

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
func (c *Client) parseAccounts(_ string) ([]Account, error) {
	// TODO: Implement proper parsing based on AppleScript record format
	return []Account{}, nil
}

// Helper function to parse mailboxes from AppleScript output
func (c *Client) parseMailboxes(_ string) ([]Mailbox, error) {
	// TODO: Implement proper parsing based on AppleScript record format
	return []Mailbox{}, nil
}

// Helper function to parse messages from AppleScript output
func (c *Client) parseMessages(_ string) ([]Message, error) {
	// TODO: Implement proper parsing based on AppleScript record format
	return []Message{}, nil
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
	const acc = mail.accounts.byName('%s');
	const accName = acc.name();
	const mailboxes = acc.mailboxes();
	for (let j = 0; j < mailboxes.length; j++) {
		const mbox = mailboxes[j];
		try {
			let totalCount = 0;
			try { totalCount = mbox.messages.count(); } catch (e) {}
			result.push({
				name: mbox.name(),
				unreadCount: mbox.unreadCount(),
				totalCount: totalCount,
				account: accName
			});
		} catch (e) {
			// Skip mailboxes that can't be queried at all
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
	// Build filter/offset/limit clauses using index-based approach.
	// Bulk property accessors (mbox.messages.readStatus()) fetch all values in a
	// single IPC call rather than one round-trip per message.
	unreadFilter := ""
	if unreadOnly {
		unreadFilter = "{ const rs = mbox.messages.readStatus(); indices = indices.filter(i => !rs[i]); }"
	}

	flaggedFilter := ""
	if flaggedOnly {
		flaggedFilter = "{ const fs = mbox.messages.flaggedStatus(); indices = indices.filter(i => fs[i]); }"
	}

	sinceFilter := ""
	if since != "" {
		// Bulk-fetch all received dates in one IPC call, then filter by index
		sinceFilter = fmt.Sprintf("{ const sd = new Date('%s'); const allDates = mbox.messages.dateReceived(); indices = indices.filter(i => { const d = allDates[i]; return d && d >= sd; }); }", escapeJSString(since))
	}

	offsetClause := ""
	if offset > 0 {
		offsetClause = fmt.Sprintf("if (indices.length > %d) indices = indices.slice(%d);", offset, offset)
	}

	limitClause := ""
	if limit > 0 {
		limitClause = fmt.Sprintf("if (indices.length > %d) indices = indices.slice(0, %d);", limit, limit)
	}

	contentField := "content: '',"
	if withContent {
		contentField = "content: msg.content() || '',"
	}

	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const accName = acc.name();
	const mboxName = mbox.name();
	const messages = mbox.messages();

	// Index array; all filtering operates on indices so property access is bulk/deferred
	let indices = Array.from({length: messages.length}, (_, i) => i);

	// Bulk property filters (1 IPC call each instead of N)
	%s
	%s
	%s
	%s
	%s

	for (let k = 0; k < indices.length; k++) {
		const i = indices[k];
		const msg = messages[i];
		try { if (msg.deletedStatus()) continue; } catch(e) {}
		try {
			result.push({
				id: String(msg.id()),
				subject: msg.subject() || '',
				sender: msg.sender() || '',
				dateReceived: (msg.dateReceived() || new Date()).toISOString(),
				dateSent: (msg.dateSent() || new Date()).toISOString(),
				read: msg.readStatus(),
				flagged: msg.flaggedStatus(),
				messageSize: 0,
				%s
				mailbox: mboxName,
				account: accName
			});
		} catch (e) {
			// Skip messages that cause errors
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapeJSString(accountName), escapeJSString(mailboxName), unreadFilter, flaggedFilter, sinceFilter, offsetClause, limitClause, contentField)

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
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx >= 0) {
		const msg = mbox.messages.at(targetIdx);
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
			dateReceived: (msg.dateReceived() || new Date()).toISOString(),
			dateSent: (msg.dateSent() || new Date()).toISOString(),
			read: msg.readStatus(),
			flagged: msg.flaggedStatus(),
			messageSize: msg.messageSize(),
			content: msg.content() || '',
			mailbox: mbox.name(),
			account: acc.name(),
			toRecipients: toRecipients,
			ccRecipients: ccRecipients,
			bccRecipients: bccRecipients
		};
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

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

// uiArchiveMu serializes UI-driven archive operations: they manipulate the
// shared Mail.app window selection, so concurrent runs would race.
var uiArchiveMu sync.Mutex

// ArchiveMessage moves a message to the provider's archive mailbox.
//
// Gmail accounts (detected by the presence of an "All Mail" mailbox) need
// special handling: scripted moves out of INBOX behave as label copies on
// Gmail's IMAP bridge — the message reappears in the inbox on the next sync.
// The only operation that truly archives (removes the INBOX label, keeps the
// message in All Mail) is Mail.app's own Archive command, which is not
// scriptable directly, so we select the message in a viewer and invoke the
// Message > Archive menu item via System Events. This requires Accessibility
// permission for the invoking terminal and briefly brings Mail forward.
//
// Other providers (Exchange, Fastmail, ...) do real moves, so a plain move
// to their "Archive" mailbox works.
func (c *Client) ArchiveMessage(accountName, mailboxName, messageID string) error {
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Source mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else if (resolveMailbox(acc, 'All Mail')) {
		// Gmail: the caller must archive through the Mail.app UI.
		'GMAIL_UI_ARCHIVE';
	} else {
		const archiveBox = resolveMailbox(acc, 'Archive');
		if (archiveBox) {
			// Use the move command; assigning the mailbox property is
			// silently ignored for Gmail mailboxes.
			mail.move(mbox.messages.at(targetIdx), { to: archiveBox });
			'Success';
		} else {
			'Error: Archive mailbox not found';
		}
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

	output, err := c.runJXA(script)
	if err != nil {
		return err
	}
	if strings.Contains(output, "GMAIL_UI_ARCHIVE") {
		return c.archiveMessageViaUI(accountName, mailboxName, messageID)
	}
	if strings.Contains(output, "Error") {
		return fmt.Errorf(output)
	}
	return nil
}

// archiveMessageViaUI archives a message by driving Mail.app's own Archive
// command, the only operation Gmail honors as a true archive.
//
// Primary path: select the message in a viewer and click Message > Archive.
// Setting a viewer's "selected messages" can land one row off the requested
// message, so the selection is read back and self-corrected before clicking.
// If the target row is unreachable (offset past the first row), fall back to
// opening the message in its own window. In both paths the Archive menu item
// is only clicked when enabled — it is disabled e.g. for windows opened in
// All Mail context — so a disabled state surfaces as an error instead of a
// silent no-op.
func (c *Client) archiveMessageViaUI(accountName, mailboxName, messageID string) error {
	uiArchiveMu.Lock()
	defer uiArchiveMu.Unlock()

	// The id is interpolated unquoted into AppleScript expressions, so insist
	// it is numeric.
	if _, err := strconv.ParseInt(messageID, 10, 64); err != nil {
		return fmt.Errorf("invalid message id %q", messageID)
	}

	script := fmt.Sprintf(`
on findIndexById(msgList, targetId)
	tell application "Mail"
		repeat with i from 1 to (count of msgList)
			if (id of item i of msgList) is targetId then return i
		end repeat
	end tell
	return 0
end findIndexById

set targetId to %s
tell application "Mail"
	activate
	set theAcct to account "%s"
	set theBox to mailbox "%s" of theAcct
	if (count of message viewers) is 0 then make new message viewer
	set theViewer to message viewer 1
	set selected mailboxes of theViewer to {theBox}
	delay 1
	set msgList to messages of theBox
end tell

set targetIdx to my findIndexById(msgList, targetId)
if targetIdx is 0 then return "Error: Message not found"
set n to count of msgList

set selOk to false
set tryIdx to targetIdx
repeat 4 times
	tell application "Mail"
		set selected messages of theViewer to {item tryIdx of msgList}
		delay 0.5
		set sel to selected messages of theViewer
	end tell
	if sel is not missing value then
		if (count of sel) > 0 then
			tell application "Mail" to set selId to id of item 1 of sel
			if selId is targetId then
				set selOk to true
				exit repeat
			end if
			set selIdx to my findIndexById(msgList, selId)
			if selIdx is 0 then exit repeat
			-- Selection lands (selIdx - tryIdx) rows off; compensate.
			set tryIdx to targetIdx - (selIdx - tryIdx)
			if tryIdx < 1 or tryIdx > n then exit repeat
		end if
	end if
end repeat

if not selOk then
	-- Fall back to opening the message in its own window.
	tell application "Mail"
		open (item targetIdx of msgList)
		delay 1.5
	end tell
end if

tell application "System Events"
	tell process "Mail"
		set frontmost to true
		set archItem to menu item "Archive" of menu "Message" of menu bar 1
		if enabled of archItem then
			click archItem
		else
			return "Error: Archive menu item is disabled for this message"
		end if
	end tell
end tell
return "Success"
`, messageID, escapeAppleScriptString(accountName), escapeAppleScriptString(mailboxName))

	// The menu click can silently no-op while Mail is still activating or the
	// message window is still loading, so verify the message actually left the
	// mailbox and retry a couple of times if it didn't.
	for attempt := 0; attempt < 3; attempt++ {
		if exists, err := c.messageExistsInMailbox(accountName, mailboxName, messageID); err == nil && !exists {
			return nil
		}

		output, err := c.runAppleScript(script)
		if err != nil {
			return fmt.Errorf("UI archive failed (System Events needs Accessibility permission for your terminal): %w", err)
		}
		if strings.Contains(output, "Error") {
			return fmt.Errorf(output)
		}

		for i := 0; i < 5; i++ {
			time.Sleep(1 * time.Second)
			if exists, err := c.messageExistsInMailbox(accountName, mailboxName, messageID); err == nil && !exists {
				return nil
			}
		}
	}

	return fmt.Errorf("message %s still in %s after UI archive attempts", messageID, mailboxName)
}

// messageExistsInMailbox reports whether a message id is present in a mailbox.
func (c *Client) messageExistsInMailbox(accountName, mailboxName, messageID string) (bool, error) {
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	String(allIds.findIndex(id => String(id) === '%s') >= 0);
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

	output, err := c.runJXA(script)
	if err != nil {
		return false, err
	}
	if strings.Contains(output, "Error") {
		return false, fmt.Errorf(output)
	}
	return strings.Contains(output, "true"), nil
}

// MoveMessage moves a message to a different mailbox
func (c *Client) MoveMessage(accountName, sourceMailbox, messageID, targetMailbox string) error {
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const sourceMbox = resolveMailbox(acc, '%s');
	if (!sourceMbox) throw 'Source mailbox not found';
	const destMbox = resolveMailbox(acc, '%s');
	if (!destMbox) throw 'Destination mailbox not found';
	const allIds = sourceMbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else {
		// Use the move command; assigning the mailbox property is
		// silently ignored for Gmail mailboxes.
		mail.move(sourceMbox.messages.at(targetIdx), { to: destMbox });
		'Success';
	}
} catch (e) {
	'Error: ' + e;
}
`, escapeJSString(accountName), escapeJSString(sourceMailbox), escapeJSString(targetMailbox), escapeJSString(messageID))

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
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx >= 0) {
		const attachments = mbox.messages.at(targetIdx).mailAttachments();
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
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID))

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
	script := fmt.Sprintf(`
const mail = Application('Mail');
const app = Application.currentApplication();
app.includeStandardAdditions = true;
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const allIds = mbox.messages.id();
	const targetIdx = allIds.findIndex(id => String(id) === '%s');
	if (targetIdx < 0) {
		'Error: Message not found';
	} else {
		const attachments = mbox.messages.at(targetIdx).mailAttachments();
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
`, escapeJSString(accountName), escapeJSString(mailboxName), escapeJSString(messageID), escapeJSString(attachmentName), escapeJSString(savePath))

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
const maxResults = %d;
`+jsResolveMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const accName = acc.name();
	const mboxName = mbox.name();
	const messages = mbox.messages();
	// Limit how many messages to check per mailbox for performance
	// Messages are typically sorted newest first, so this checks recent messages
	const maxToCheck = Math.min(messages.length, 500);

	for (let k = 0; k < maxToCheck && result.length < maxResults; k++) {
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
					dateReceived: (msg.dateReceived() || new Date()).toISOString(),
					dateSent: (msg.dateSent() || new Date()).toISOString(),
					read: msg.readStatus(),
					flagged: msg.flaggedStatus(),
					messageSize: msg.messageSize(),
					mailbox: mboxName,
					account: accName
				});
			}
		} catch (e) {
			// Skip messages that cause errors
		}
	}
} catch (e) {
	// Handle errors gracefully
}

JSON.stringify(result);
`, escapedQuery, limit, escapedAccount, escapedMailbox)

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
// GetUnifiedMessagesJSON retrieves messages from Mail.app's special unified
// mailboxes (inboxes, sentMailboxes, draftMailboxes, trashMailboxes,
// junkMailboxes) across all accounts in a single JXA call.
//
// mailboxType must be one of: "inbox", "unread", "sent", "drafts",
// "trash", "junk", "flagged".
//
// "unread" and "flagged" are treated as inbox views with the appropriate
// filter applied.
// GetUnifiedMessagesJSON retrieves messages from unified views across all accounts.
//
// mailboxType must be one of: "inbox", "unread", "flagged", "sent", "drafts",
// "trash", "junk".
//
// inbox/unread/flagged use the accounts-based path (GetMessagesFromMultipleMailboxes
// → GetMessagesJSON per account INBOX) because mailbox objects from
// mail.inboxes() don't support the same bulk property operations as those
// resolved from the account's own mailbox tree, causing unreliable filtering.
//
// sent/drafts/trash/junk use Mail.app's JXA special-mailbox accessors
// (mail.sentMailboxes() etc.) which don't require per-message filtering.
func (c *Client) GetUnifiedMessagesJSON(mailboxType string, limit, offset int, withContent bool) ([]Message, error) {
	switch mailboxType {
	case "inbox", "unread", "flagged":
		return c.getInboxBasedUnified(mailboxType, limit, offset, withContent)
	case "sent", "drafts", "trash", "junk":
		return c.getSpecialMailboxUnified(mailboxType, limit, offset, withContent)
	default:
		return nil, fmt.Errorf("unknown unified mailbox type: %s", mailboxType)
	}
}

// getInboxBasedUnified fetches messages from each account's INBOX using the
// proven GetMessagesJSON path, then merges, sorts, and slices globally.
func (c *Client) getInboxBasedUnified(mailboxType string, limit, offset int, withContent bool) ([]Message, error) {
	accounts, err := c.GetAccountsJSON()
	if err != nil {
		return nil, fmt.Errorf("failed to list accounts: %w", err)
	}

	// Over-fetch per account so the global sort+slice is accurate.
	perLimit := limit + offset
	if perLimit < 50 {
		perLimit = 50
	}

	type req = struct {
		AccountName string
		MailboxName string
		Limit       int
		Offset      int
		UnreadOnly  bool
		FlaggedOnly bool
		WithContent bool
		Since       string
	}

	var requests []req
	for _, acc := range accounts {
		if !acc.Enabled {
			continue
		}
		requests = append(requests, req{
			AccountName: acc.Name,
			MailboxName: "INBOX",
			Limit:       perLimit,
			Offset:      0,
			UnreadOnly:  mailboxType == "unread",
			FlaggedOnly: mailboxType == "flagged",
			WithContent: withContent,
		})
	}

	if len(requests) == 0 {
		return []Message{}, nil
	}

	messages, err := c.GetMessagesFromMultipleMailboxes(requests)
	if err != nil {
		return nil, err
	}

	return sortAndSlice(messages, offset, limit), nil
}

// getSpecialMailboxUnified fetches messages from Mail.app's built-in special
// mailbox collections (sentMailboxes, draftMailboxes, trashMailboxes,
// junkMailboxes) via a single JXA call.  No per-message filtering is applied
// since these views don't need unread/flagged filtering.
func (c *Client) getSpecialMailboxUnified(mailboxType string, limit, offset int, withContent bool) ([]Message, error) {
	accessor := map[string]string{
		"sent":   "sentMailboxes",
		"drafts": "draftMailboxes",
		"trash":  "trashMailboxes",
		"junk":   "junkMailboxes",
	}[mailboxType]

	perLimit := limit + offset
	if perLimit < 50 {
		perLimit = 50
	}

	contentField := "content: '',"
	if withContent {
		contentField = "content: msg.content() || '',"
	}

	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
const mailboxes = mail.%s();

for (let m = 0; m < mailboxes.length; m++) {
	const mbox = mailboxes[m];
	let accName = '';
	let mboxName = '';
	try { accName = mbox.account().name(); } catch(e) {
		try { accName = mbox.account.name(); } catch(e2) { accName = ''; }
	}
	try { mboxName = mbox.name(); } catch(e) { mboxName = '%s'; }

	let messages;
	try { messages = mbox.messages(); } catch(e) { continue; }

	// Cap per-mailbox before iterating
	const cap = Math.min(messages.length, %d);

	for (let k = 0; k < cap; k++) {
		const msg = messages[k];
		try { if (msg.deletedStatus()) continue; } catch(e) {}
		try {
			result.push({
				id: String(msg.id()),
				subject: msg.subject() || '',
				sender: msg.sender() || '',
				dateReceived: (msg.dateReceived() || new Date()).toISOString(),
				dateSent: (msg.dateSent() || new Date()).toISOString(),
				read: msg.readStatus(),
				flagged: msg.flaggedStatus(),
				messageSize: 0,
				%s
				mailbox: mboxName,
				account: accName
			});
		} catch(e) {}
	}
}

JSON.stringify(result);
`, accessor, mailboxType, perLimit, contentField)

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}

	var messages []Message
	if err := json.Unmarshal([]byte(output), &messages); err != nil {
		return nil, fmt.Errorf("failed to parse %s messages JSON: %w", mailboxType, err)
	}

	return sortAndSlice(messages, offset, limit), nil
}

// sortAndSlice sorts messages by date descending then applies offset and limit.
func sortAndSlice(messages []Message, offset, limit int) []Message {
	sort.Slice(messages, func(i, j int) bool {
		return messages[i].DateReceived > messages[j].DateReceived
	})
	if offset > 0 {
		if offset >= len(messages) {
			return []Message{}
		}
		messages = messages[offset:]
	}
	if limit > 0 && len(messages) > limit {
		messages = messages[:limit]
	}
	return messages
}

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

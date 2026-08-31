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
	MessageID     string
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
	InReplyTo     string   `json:",omitempty"`
	References    []string `json:",omitempty"`
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
	// Bulk-fetch names at each level (one IPC call) instead of calling
	// name() per mailbox; only descend into sub-mailboxes when no match.
	function walk(container) {
		const names = container.mailboxes.name();
		for (let j = 0; j < names.length; j++) {
			if (names[j] === name) return container.mailboxes.at(j);
		}
		for (let j = 0; j < names.length; j++) {
			try {
				const child = container.mailboxes.at(j);
				if (child.mailboxes.length > 0) {
					const found = walk(child);
					if (found) return found;
				}
			} catch (e) {}
		}
		return null;
	}
	return walk(acc);
}
// resolveMessage returns a message specifier by Mail's global message id,
// or null if no such message exists. byId() is a direct object specifier
// (~10ms) whereas mbox.messages.id() enumerates the whole mailbox (seconds
// on large boxes). Note that byId is not scoped to mbox: message ids are
// unique across the Mail database, so the result is always the message the
// caller identified, even if Gmail reports it under a different label.
function resolveMessage(mbox, id) {
	const n = Number(id);
	if (!isFinite(n)) return null;
	const m = mbox.messages.byId(n);
	try { m.id(); return m; } catch (e) { return null; }
}
`

// jsParseThreadHeaders extracts In-Reply-To and References from a raw
// "all headers" string. Both headers can fold across lines (RFC 5322
// continuation lines start with whitespace), so each is matched up to the
// next non-indented header line rather than to end-of-line.
const jsParseThreadHeaders = `
function parseThreadHeaders(headers) {
	function field(name) {
		const m = headers.match(new RegExp('^' + name + ':([^\\n]*(?:\\n[ \\t]+[^\\n]*)*)', 'im'));
		return m ? m[1].replace(/\s+/g, ' ').trim() : '';
	}
	const inReplyToRaw = field('In-Reply-To');
	const referencesRaw = field('References');
	const inReplyTo = (inReplyToRaw.match(/<[^>]+>/) || [''])[0];
	const references = referencesRaw.match(/<[^>]+>/g) || [];
	return { inReplyTo: inReplyTo, references: references };
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
	res, err := c.MarkMessages(accountName, mailboxName, []string{messageID}, read)
	if err != nil {
		return err
	}
	return res.Err()
}

// FlagMessage sets or unsets the flagged status of a message
func (c *Client) FlagMessage(accountName, mailboxName, messageID string, flagged bool) error {
	res, err := c.FlagMessages(accountName, mailboxName, []string{messageID}, flagged)
	if err != nil {
		return err
	}
	return res.Err()
}

// DeleteMessage moves a message to trash
func (c *Client) DeleteMessage(accountName, mailboxName, messageID string) error {
	res, err := c.DeleteMessages(accountName, mailboxName, []string{messageID})
	if err != nil {
		return err
	}
	return res.Err()
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

// GetMailboxesJSON retrieves mailboxes as JSON using JXA. withCounts also
// fills TotalCount, which costs a full enumeration per mailbox (~200ms on
// large ones).
func (c *Client) GetMailboxesJSON(accountName string, withCounts bool) ([]Mailbox, error) {
	// If specific account requested, use single JXA call
	if accountName != "" {
		return c.getMailboxesForSingleAccount(accountName, withCounts)
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
		return c.getMailboxesForSingleAccount(accounts[0].Name, withCounts)
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
			mailboxes, err := c.getMailboxesForSingleAccount(accName, withCounts)
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
func (c *Client) getMailboxesForSingleAccount(accountName string, withCounts bool) ([]Mailbox, error) {
	countExpr := "0"
	if withCounts {
		countExpr = "acc.mailboxes.at(j).messages.length"
	}
	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];

try {
	const acc = mail.accounts.byName('%s');
	const accName = acc.name();
	// Bulk property reads: one IPC call per property instead of per mailbox.
	const names = acc.mailboxes.name();
	const unread = acc.mailboxes.unreadCount();
	for (let j = 0; j < names.length; j++) {
		try {
			let totalCount = 0;
			try { totalCount = %s; } catch (e) {}
			result.push({
				name: names[j],
				unreadCount: unread[j],
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
`, escapeJSString(accountName), countExpr)

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
func (c *Client) GetMessagesJSON(accountName, mailboxName string, limit, offset int, unreadOnly, flaggedOnly, withContent, withHeaders bool, since string) ([]Message, error) {
	// Filters operate on an index array using bulk property accessors
	// (M.readStatus() is one IPC call for the whole mailbox).
	unreadFilter := ""
	if unreadOnly {
		unreadFilter = "{ const rs = M.readStatus(); indices = indices.filter(i => !rs[i]); }"
	}

	flaggedFilter := ""
	if flaggedOnly {
		flaggedFilter = "{ const fs = M.flaggedStatus(); indices = indices.filter(i => fs[i]); }"
	}

	sinceFilter := ""
	if since != "" {
		sinceFilter = fmt.Sprintf("{ const sd = new Date('%s'); const allDates = M.dateReceived(); indices = indices.filter(i => { const d = allDates[i]; return d && d >= sd; }); }", escapeJSString(since))
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
		// content() is never bulk-fetched: it is large and can trigger a
		// blocking body download inside Mail.app.
		contentField = "content: M.byId(cols.id[i]).content() || '',"
	}

	// allHeaders is a large string and ~9x slower to bulk-fetch than the
	// other scalar props, so it is only added to PROPS (and thus fetched at
	// all) when explicitly requested.
	headerProp := ""
	headerFields := "inReplyTo: '', references: [],"
	if withHeaders {
		headerProp = ", 'allHeaders'"
		headerFields = "inReplyTo: parseThreadHeaders(get(i, 'allHeaders') || '').inReplyTo, references: parseThreadHeaders(get(i, 'allHeaders') || '').references,"
	}

	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
`+jsResolveMailbox+jsParseThreadHeaders+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const accName = acc.name();
	const mboxName = mbox.name();
	const M = mbox.messages;
	const total = M.length;

	let indices = Array.from({length: total}, (_, i) => i);
	%s
	%s
	%s
	%s
	%s

	// Each per-message property read is one ~10ms Apple event; a bulk read
	// of one property over the whole mailbox costs ~35us per message. So
	// bulk-fetch everything when the mailbox is small relative to the page,
	// otherwise read per-message for just the page.
	const PROPS = ['id', 'subject', 'sender', 'dateReceived', 'dateSent', 'readStatus', 'flaggedStatus', 'deletedStatus', 'messageId'%s];
	// Index specifiers (M.at(i)) re-enumerate the mailbox on every access,
	// so the per-message path resolves by id instead (ids are cheap in bulk).
	const useBulk = total <= Math.max(2000, indices.length * 300);
	const cols = { id: M.id() };
	let get;
	if (useBulk) {
		for (const p of PROPS) if (p !== 'id') cols[p] = M[p]();
		get = (i, p) => cols[p][i];
	} else {
		const refs = {};
		get = (i, p) => {
			if (p === 'id') return cols.id[i];
			if (!refs[i]) refs[i] = M.byId(cols.id[i]);
			return refs[i][p]();
		};
	}

	for (let k = 0; k < indices.length; k++) {
		const i = indices[k];
		try {
			if (get(i, 'deletedStatus')) continue;
			result.push({
				id: String(get(i, 'id')),
				messageId: get(i, 'messageId') || '',
				subject: get(i, 'subject') || '',
				sender: get(i, 'sender') || '',
				dateReceived: (get(i, 'dateReceived') || new Date()).toISOString(),
				dateSent: (get(i, 'dateSent') || new Date()).toISOString(),
				read: get(i, 'readStatus'),
				flagged: get(i, 'flaggedStatus'),
				messageSize: 0,
				%s
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
`, escapeJSString(accountName), escapeJSString(mailboxName),
		unreadFilter, flaggedFilter, sinceFilter, offsetClause, limitClause,
		headerProp, contentField, headerFields)

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
`+jsResolveMailbox+jsParseThreadHeaders+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	const target = resolveMessage(mbox, '%s');
	if (target) {
		const msg = target;
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

		const threadHeaders = parseThreadHeaders(msg.allHeaders() || '');

		result = {
			id: String(msg.id()),
			messageId: msg.messageId() || '',
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
			bccRecipients: bccRecipients,
			inReplyTo: threadHeaders.inReplyTo,
			references: threadHeaders.references
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

// ArchiveMessage moves a message to the provider's archive mailbox.
//
// Gmail accounts (detected by the presence of an "All Mail" mailbox) are
// refused: Mail.app offers no safe, scriptable archive for Gmail. Every
// mechanism was tested and fails:
//   - Scripted moves out of INBOX (mailbox property or the move command)
//     behave as label copies on Gmail's IMAP bridge — the message reappears
//     in the inbox on the next sync.
//   - Moving through Trash (move to Trash, then move back out to All Mail)
//     does archive, but races Gmail's "expunged from Trash = permanently
//     deleted" rule and was observed to permanently delete messages.
//   - message.deletedStatus is read-only.
//   - Driving Mail's own Archive command works reliably but requires UI
//     automation that activates Mail and steals focus.
//
// Archiving Gmail from the CLI therefore needs the Gmail API, not Mail.app.
//
// Other providers (Exchange, Fastmail, ...) do real moves, so a plain move
// to their "Archive" mailbox works.
func (c *Client) ArchiveMessage(accountName, mailboxName, messageID string) error {
	res, err := c.ArchiveMessages(accountName, mailboxName, []string{messageID})
	if err != nil {
		return err
	}
	return res.Err()
}

// MoveMessage moves a message to a different mailbox
func (c *Client) MoveMessage(accountName, sourceMailbox, messageID, targetMailbox string) error {
	res, err := c.MoveMessages(accountName, sourceMailbox, []string{messageID}, targetMailbox)
	if err != nil {
		return err
	}
	return res.Err()
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
	const target = resolveMessage(mbox, '%s');
	if (target) {
		const attachments = target.mailAttachments();
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
	const target = resolveMessage(mbox, '%s');
	if (!target) {
		'Error: Message not found';
	} else {
		const attachments = target.mailAttachments();
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
	mailboxes, err := c.GetMailboxesJSON(accountName, false)
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
					messageId: msg.messageId() || '',
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
	AccountName string
	MailboxName string
	Limit       int
	Offset      int
	UnreadOnly  bool
	FlaggedOnly bool
	WithContent bool
	WithHeaders bool
	Since       string
}) ([]Message, error) {
	if len(requests) == 0 {
		return []Message{}, nil
	}

	// If only one request, no need for parallelization
	if len(requests) == 1 {
		req := requests[0]
		return c.GetMessagesJSON(req.AccountName, req.MailboxName, req.Limit, req.Offset, req.UnreadOnly, req.FlaggedOnly, req.WithContent, req.WithHeaders, req.Since)
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
			AccountName string
			MailboxName string
			Limit       int
			Offset      int
			UnreadOnly  bool
			FlaggedOnly bool
			WithContent bool
			WithHeaders bool
			Since       string
		}) {
			messages, err := c.GetMessagesJSON(r.AccountName, r.MailboxName, r.Limit, r.Offset, r.UnreadOnly, r.FlaggedOnly, r.WithContent, r.WithHeaders, r.Since)
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
	AccountName string
	MailboxName string
	MessageID   string
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
			AccountName string
			MailboxName string
			MessageID   string
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
func (c *Client) GetUnifiedMessagesJSON(mailboxType string, limit, offset int, withContent, withHeaders bool) ([]Message, error) {
	switch mailboxType {
	case "inbox", "unread", "flagged":
		return c.getInboxBasedUnified(mailboxType, limit, offset, withContent, withHeaders)
	case "sent", "drafts", "trash", "junk":
		return c.getSpecialMailboxUnified(mailboxType, limit, offset, withContent, withHeaders)
	default:
		return nil, fmt.Errorf("unknown unified mailbox type: %s", mailboxType)
	}
}

// getInboxBasedUnified fetches messages from each account's INBOX using the
// proven GetMessagesJSON path, then merges, sorts, and slices globally.
func (c *Client) getInboxBasedUnified(mailboxType string, limit, offset int, withContent, withHeaders bool) ([]Message, error) {
	// Resolve each account's real inbox name ("INBOX" vs "Inbox") via Mail's
	// unified inbox rather than assuming a name.
	refs, err := c.GetSpecialMailboxRefs("inbox")
	if err != nil {
		return nil, fmt.Errorf("failed to resolve inboxes: %w", err)
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
		WithHeaders bool
		Since       string
	}

	var requests []req
	for _, r := range refs {
		requests = append(requests, req{
			AccountName: r.Account,
			MailboxName: r.Mailbox,
			Limit:       perLimit,
			Offset:      0,
			UnreadOnly:  mailboxType == "unread",
			FlaggedOnly: mailboxType == "flagged",
			WithContent: withContent,
			WithHeaders: withHeaders,
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

// SpecialMailboxRef names one account's mailbox within a Mail.app unified
// mailbox (inbox, sentMailbox, draftsMailbox, trashMailbox, junkMailbox).
type SpecialMailboxRef struct {
	Account string `json:"account"`
	Mailbox string `json:"mailbox"`
}

// GetSpecialMailboxRefs resolves the per-account mailboxes behind one of
// Mail.app's unified mailboxes in a single JXA call, so provider naming
// ("Inbox" vs "INBOX", "Trash" vs "Deleted Items") is handled by Mail.
// kind is one of inbox, sent, drafts, trash, junk.
func (c *Client) GetSpecialMailboxRefs(kind string) ([]SpecialMailboxRef, error) {
	accessor, ok := map[string]string{
		"inbox":  "inbox",
		"sent":   "sentMailbox",
		"drafts": "draftsMailbox",
		"trash":  "trashMailbox",
		"junk":   "junkMailbox",
	}[kind]
	if !ok {
		return nil, fmt.Errorf("unknown special mailbox kind: %s", kind)
	}
	script := fmt.Sprintf(`
const mail = Application('Mail');
const result = [];
const subs = mail.%s().mailboxes();
for (let i = 0; i < subs.length; i++) {
	try { result.push({ account: subs[i].account().name(), mailbox: subs[i].name() }); } catch (e) {}
}
JSON.stringify(result);
`, accessor)
	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}
	var refs []SpecialMailboxRef
	if err := json.Unmarshal([]byte(output), &refs); err != nil {
		return nil, fmt.Errorf("failed to parse mailbox refs: %w", err)
	}
	return refs, nil
}

// getSpecialMailboxUnified lists a unified special mailbox by resolving the
// per-account boxes and fetching each concurrently through GetMessagesJSON
// (the bulk/byId fast path), then merging, sorting and slicing globally.
func (c *Client) getSpecialMailboxUnified(mailboxType string, limit, offset int, withContent, withHeaders bool) ([]Message, error) {
	refs, err := c.GetSpecialMailboxRefs(mailboxType)
	if err != nil {
		return nil, err
	}
	if len(refs) == 0 {
		return []Message{}, nil
	}

	perLimit := limit + offset
	if perLimit < 50 {
		perLimit = 50
	}

	var requests []struct {
		AccountName string
		MailboxName string
		Limit       int
		Offset      int
		UnreadOnly  bool
		FlaggedOnly bool
		WithContent bool
		WithHeaders bool
		Since       string
	}
	for _, r := range refs {
		requests = append(requests, struct {
			AccountName string
			MailboxName string
			Limit       int
			Offset      int
			UnreadOnly  bool
			FlaggedOnly bool
			WithContent bool
			WithHeaders bool
			Since       string
		}{AccountName: r.Account, MailboxName: r.Mailbox, Limit: perLimit, WithContent: withContent, WithHeaders: withHeaders})
	}

	messages, err := c.GetMessagesFromMultipleMailboxes(requests)
	if err != nil {
		return nil, err
	}
	return sortAndSlice(messages, offset, limit), nil
}

// sortAndSlice sorts messages by date descending then applies offset and limit.
func sortAndSlice(messages []Message, offset, limit int) []Message {
	if messages == nil {
		messages = []Message{}
	}
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
	AccountName   string
	SourceMailbox string
	MessageID     string
	TargetMailbox string
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
			AccountName   string
			SourceMailbox string
			MessageID     string
			TargetMailbox string
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

// MutationResult reports the per-message outcome of a batch mutation.
type MutationResult struct {
	Succeeded []string          `json:"succeeded"`
	Missing   []string          `json:"missing"`
	Failed    map[string]string `json:"failed,omitempty"`
}

// Err returns a non-nil error if any message was missing or failed.
func (r *MutationResult) Err() error {
	if len(r.Missing) == 0 && len(r.Failed) == 0 {
		return nil
	}
	var parts []string
	if len(r.Missing) > 0 {
		parts = append(parts, fmt.Sprintf("not found: %s", strings.Join(r.Missing, ", ")))
	}
	for id, msg := range r.Failed {
		parts = append(parts, fmt.Sprintf("%s: %s", id, msg))
	}
	return fmt.Errorf("%d of %d messages failed (%s)",
		len(r.Missing)+len(r.Failed), len(r.Succeeded)+len(r.Missing)+len(r.Failed), strings.Join(parts, "; "))
}

// mutateMessages resolves a mailbox once, looks up every requested message ID
// in a single enumeration, and runs jsAction on each match. jsAction is a JXA
// snippet with `msg` (the message specifier), `acc`, `mbox` and `mail` in
// scope. Each message is resolved with byId (no mailbox enumeration) and all
// IDs share one osascript process, so cost is ~10ms per message plus one
// process launch.
func (c *Client) mutateMessages(accountName, mailboxName string, messageIDs []string, jsPrelude, jsAction string) (*MutationResult, error) {
	res := &MutationResult{Failed: map[string]string{}}
	if len(messageIDs) == 0 {
		return res, nil
	}
	idsJSON, _ := json.Marshal(messageIDs)

	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
const result = { succeeded: [], missing: [], failed: {} };
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	%s
	const wanted = %s;
	for (const id of wanted) {
		const msg = resolveMessage(mbox, id);
		if (!msg) { result.missing.push(id); continue; }
		const t = { id: id };
		try {
			%s
			result.succeeded.push(t.id);
		} catch (e) {
			result.failed[t.id] = String(e);
		}
	}
	JSON.stringify(result);
} catch (e) {
	JSON.stringify({ error: String(e) });
}
`, escapeJSString(accountName), escapeJSString(mailboxName), jsPrelude, string(idsJSON), jsAction)

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}
	var raw struct {
		Error     string            `json:"error"`
		Succeeded []string          `json:"succeeded"`
		Missing   []string          `json:"missing"`
		Failed    map[string]string `json:"failed"`
	}
	if err := json.Unmarshal([]byte(output), &raw); err != nil {
		return nil, fmt.Errorf("unexpected output: %s", output)
	}
	if raw.Error != "" {
		return nil, fmt.Errorf("%s", raw.Error)
	}
	res.Succeeded = raw.Succeeded
	res.Missing = raw.Missing
	if raw.Failed != nil {
		res.Failed = raw.Failed
	}
	return res, nil
}

// MarkMessages marks several messages read/unread in one Mail.app round trip.
func (c *Client) MarkMessages(accountName, mailboxName string, messageIDs []string, read bool) (*MutationResult, error) {
	return c.mutateMessages(accountName, mailboxName, messageIDs, "", fmt.Sprintf("msg.readStatus = %t;", read))
}

// FlagMessages flags/unflags several messages in one Mail.app round trip.
func (c *Client) FlagMessages(accountName, mailboxName string, messageIDs []string, flagged bool) (*MutationResult, error) {
	return c.mutateMessages(accountName, mailboxName, messageIDs, "", fmt.Sprintf("msg.flaggedStatus = %t;", flagged))
}

// DeleteMessages moves several messages to Trash in one Mail.app round trip.
// Messages already in Trash are deleted permanently by Mail.app.
func (c *Client) DeleteMessages(accountName, mailboxName string, messageIDs []string) (*MutationResult, error) {
	return c.mutateMessages(accountName, mailboxName, messageIDs, "", "msg.delete();")
}

// MoveMessages moves several messages to targetMailbox in one round trip.
func (c *Client) MoveMessages(accountName, sourceMailbox string, messageIDs []string, targetMailbox string) (*MutationResult, error) {
	prelude := fmt.Sprintf(`const destMbox = resolveMailbox(acc, '%s');
	if (!destMbox) throw 'Destination mailbox not found';`, escapeJSString(targetMailbox))
	return c.mutateMessages(accountName, sourceMailbox, messageIDs, prelude, "mail.move(msg, { to: destMbox });")
}

// ArchiveMessages archives several messages in one round trip. See
// ArchiveMessage for why Gmail accounts are refused.
func (c *Client) ArchiveMessages(accountName, mailboxName string, messageIDs []string) (*MutationResult, error) {
	prelude := `if (resolveMailbox(acc, 'All Mail')) throw 'Gmail accounts cannot be archived safely via Mail.app scripting. ' +
		'Archive it in Mail.app or Gmail directly, or use "messages delete" to move it to Trash.';
	const destMbox = resolveMailbox(acc, 'Archive');
	if (!destMbox) throw 'Archive mailbox not found';`
	return c.mutateMessages(accountName, mailboxName, messageIDs, prelude, "mail.move(msg, { to: destMbox });")
}

// MailboxMarkResult reports one mailbox touched by a mark-read operation.
type MailboxMarkResult struct {
	Account string `json:"account"`
	Mailbox string `json:"mailbox"`
	Changed int    `json:"changed"`
	Error   string `json:"error,omitempty"`
}

// jsMarkMailbox marks every message in `mb` whose readStatus != read and
// returns the count. Bulk property assignment on a whose() specifier is not
// supported by Mail.app, so this loops over the filtered result.
const jsMarkMailbox = `
function markMailbox(mb, read, dryRun) {
	// unreadCount is a cheap property; skip the full whose() scan when
	// there is nothing to do (only valid when marking read).
	if (read) { try { if (mb.unreadCount() === 0) return 0; } catch (e) {} }
	const pending = mb.messages.whose({ readStatus: !read })();
	if (!dryRun) {
		for (let i = 0; i < pending.length; i++) pending[i].readStatus = read;
	}
	return pending.length;
}
`

// MarkMailboxRead marks all messages in one mailbox read (or unread) and
// returns the number of messages changed. With dryRun it only counts.
func (c *Client) MarkMailboxRead(accountName, mailboxName string, read, dryRun bool) (int, error) {
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+jsMarkMailbox+`
try {
	const acc = mail.accounts.byName('%s');
	const mbox = resolveMailbox(acc, '%s');
	if (!mbox) throw 'Mailbox not found';
	JSON.stringify({ changed: markMailbox(mbox, %t, %t) });
} catch (e) {
	JSON.stringify({ error: String(e) });
}
`, escapeJSString(accountName), escapeJSString(mailboxName), read, dryRun)

	output, err := c.runJXA(script)
	if err != nil {
		return 0, err
	}
	var raw struct {
		Error   string `json:"error"`
		Changed int    `json:"changed"`
	}
	if err := json.Unmarshal([]byte(output), &raw); err != nil {
		return 0, fmt.Errorf("unexpected output: %s", output)
	}
	if raw.Error != "" {
		return 0, fmt.Errorf("%s", raw.Error)
	}
	return raw.Changed, nil
}

// MarkSpecialMailboxesRead marks every per-account mailbox of the given kinds
// read (or unread) in a single JXA call. kinds may contain "trash", "junk"
// and "archive". Trash and junk resolve through Mail.app's unified
// trashMailbox/junkMailbox properties, so provider naming (Trash vs
// "Deleted Items", Spam vs "Junk Email") is handled by Mail itself. Archive
// resolves a mailbox literally named "Archive" in each account's tree;
// Gmail's "All Mail" is deliberately not treated as archive because it also
// contains every inbox message. accounts, if non-empty, restricts to those
// account names.
func (c *Client) MarkSpecialMailboxesRead(kinds []string, accounts []string, read, dryRun bool) ([]MailboxMarkResult, error) {
	kindsJSON, _ := json.Marshal(kinds)
	if accounts == nil {
		accounts = []string{}
	}
	accountsJSON, _ := json.Marshal(accounts)

	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+jsMarkMailbox+`
const kinds = %s;
const onlyAccounts = %s;
const read = %t;
const dryRun = %t;
const results = [];
function wanted(accName) {
	return onlyAccounts.length === 0 || onlyAccounts.indexOf(accName) >= 0;
}
function handle(accName, mb) {
	const r = { account: accName, mailbox: '', changed: 0 };
	try {
		r.mailbox = mb.name();
		r.changed = markMailbox(mb, read, dryRun);
	} catch (e) {
		r.error = String(e);
	}
	results.push(r);
}
for (const kind of kinds) {
	if (kind === 'trash' || kind === 'junk') {
		const subs = mail[kind + 'Mailbox']().mailboxes();
		for (let i = 0; i < subs.length; i++) {
			let accName = '';
			try { accName = subs[i].account().name(); } catch (e) { continue; }
			if (wanted(accName)) handle(accName, subs[i]);
		}
	} else if (kind === 'archive') {
		const accs = mail.accounts();
		for (let i = 0; i < accs.length; i++) {
			const accName = accs[i].name();
			if (!wanted(accName)) continue;
			let mb = null;
			try { mb = resolveMailbox(accs[i], 'Archive'); } catch (e) {}
			if (mb) handle(accName, mb);
		}
	} else {
		results.push({ account: '', mailbox: kind, changed: 0, error: 'unknown mailbox kind' });
	}
}
JSON.stringify(results);
`, string(kindsJSON), string(accountsJSON), read, dryRun)

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}
	var results []MailboxMarkResult
	if err := json.Unmarshal([]byte(output), &results); err != nil {
		return nil, fmt.Errorf("unexpected output: %s", output)
	}
	return results, nil
}

// GlobalResult is the per-message outcome of a global (no account/mailbox)
// mutation. Status is one of ok, missing, failed, skipped.
type GlobalResult struct {
	ID      string `json:"id"`
	Account string `json:"account,omitempty"`
	Mailbox string `json:"mailbox,omitempty"`
	Status  string `json:"status"`
	Gmail   bool   `json:"gmail,omitempty"`
	Error   string `json:"error,omitempty"`
}

// GlobalSummary aggregates GlobalResults.
type GlobalSummary struct {
	Results []GlobalResult `json:"results"`
	OK      int            `json:"ok"`
	Missing int            `json:"missing"`
	Failed  int            `json:"failed"`
	Skipped int            `json:"skipped"`
}

// Err returns an error if any message was missing or failed (skips are not
// errors: they are reported deliberately).
func (s *GlobalSummary) Err() error {
	if s.Missing == 0 && s.Failed == 0 {
		return nil
	}
	var parts []string
	for _, r := range s.Results {
		switch r.Status {
		case "missing":
			parts = append(parts, r.ID+": not found")
		case "failed":
			parts = append(parts, r.ID+": "+r.Error)
		}
	}
	return fmt.Errorf("%d of %d messages failed (%s)", s.Missing+s.Failed, len(s.Results), strings.Join(parts, "; "))
}

// MutateMessagesGlobal applies one action to messages identified only by
// their Mail.app IDs. IDs are unique across the whole Mail database, so no
// account or mailbox is needed: each message is resolved with byId and its
// own mailbox().account() supplies the context. Messages from any mix of
// accounts can be handled in one round trip.
//
// action: "read", "unread", "flag", "unflag", "delete", "move" (target is
// the destination mailbox name within each message's own account) or
// "archive". For archive, gmailPolicy decides what happens to messages in
// Gmail accounts (which cannot be archived safely via scripting, see
// ArchiveMessage): "skip" (default), "delete" (move to Trash, Gmail's own
// delete semantics) or "read" (just mark read).
func (c *Client) MutateMessagesGlobal(messageIDs []string, action, target, gmailPolicy string) (*GlobalSummary, error) {
	idsJSON, _ := json.Marshal(messageIDs)
	if gmailPolicy == "" {
		gmailPolicy = "skip"
	}
	script := fmt.Sprintf(`
const mail = Application('Mail');
`+jsResolveMailbox+`
const wanted = %s;
const action = '%s';
const target = '%s';
const gmailPolicy = '%s';
const results = [];
// Any container works for byId; the unified inbox is always present.
const container = mail.inbox().messages;
const archiveBoxes = {};
const isGmail = {};
for (const id of wanted) {
	const r = { id: id, status: 'ok' };
	try {
		const n = Number(id);
		let mbox;
		try { mbox = container.byId(n).mailbox(); r.mailbox = mbox.name(); } catch (e) { r.status = 'missing'; results.push(r); continue; }
		// Commands like move need a specifier scoped to the message's own
		// mailbox; a byId reference through another container is rejected.
		const msg = mbox.messages.byId(n);
		const acc = mbox.account();
		const accName = acc.name();
		r.account = accName;
		if (isGmail[accName] === undefined) isGmail[accName] = !!resolveMailbox(acc, 'All Mail');
		r.gmail = isGmail[accName];
		switch (action) {
		case 'read': msg.readStatus = true; break;
		case 'unread': msg.readStatus = false; break;
		case 'flag': msg.flaggedStatus = true; break;
		case 'unflag': msg.flaggedStatus = false; break;
		case 'delete': msg.delete(); break;
		case 'move': {
			const dest = resolveMailbox(acc, target);
			if (!dest) throw 'Destination mailbox "' + target + '" not found in ' + accName;
			mail.move(msg, { to: dest });
			break;
		}
		case 'archive': {
			if (r.gmail) {
				if (gmailPolicy === 'delete') { msg.delete(); }
				else if (gmailPolicy === 'read') { msg.readStatus = true; }
				else { r.status = 'skipped'; r.error = 'Gmail accounts cannot be archived via Mail.app scripting'; }
				break;
			}
			if (archiveBoxes[accName] === undefined) archiveBoxes[accName] = resolveMailbox(acc, 'Archive');
			if (!archiveBoxes[accName]) throw 'Archive mailbox not found in ' + accName;
			mail.move(msg, { to: archiveBoxes[accName] });
			break;
		}
		default: throw 'unknown action ' + action;
		}
	} catch (e) {
		r.status = 'failed'; r.error = String(e);
	}
	results.push(r);
}
JSON.stringify(results);
`, string(idsJSON), escapeJSString(action), escapeJSString(target), escapeJSString(gmailPolicy))

	output, err := c.runJXA(script)
	if err != nil {
		return nil, err
	}
	var results []GlobalResult
	if err := json.Unmarshal([]byte(output), &results); err != nil {
		return nil, fmt.Errorf("unexpected output: %s", output)
	}
	s := &GlobalSummary{Results: results}
	for _, r := range results {
		switch r.Status {
		case "ok":
			s.OK++
		case "missing":
			s.Missing++
		case "failed":
			s.Failed++
		case "skipped":
			s.Skipped++
		}
	}
	return s, nil
}

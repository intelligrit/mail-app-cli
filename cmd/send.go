package cmd

import (
	"os"
	"fmt"
	"io"
	"strings"
	netmail "net/mail"

	"github.com/emersion/go-mbox"
	"github.com/robertmeta/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

var (
	sendAccount         string
	sendTo              []string
	sendCc              []string
	sendBcc             []string
	sendSubject         string
	sendBody            string
	sendAttachments     []string
	sendFromMbox        string
	sendPreserveSpaces  bool
	sendAsAttachment    bool
)

var sendCmd = &cobra.Command{
	Use:   "send",
	Short: "Send an email message",
	Long: `Send an email message through Mail.app.

Regular mode (specify recipients, subject, body):
  mail-app-cli send --account "Gmail" --to user@example.com --subject "Hello" --body "Message content"
  mail-app-cli send -a "Gmail" -t user@example.com -t another@example.com --subject "Multi recipient" --body "Content"
  mail-app-cli send -a "Gmail" -t user@example.com -s "With attachments" --body "See attached" --attach ~/file.pdf --attach ~/image.png

Mbox mode (send from mbox format file, e.g., git format-patch output):
  # Account auto-detected from patch author's email
  git format-patch HEAD~3..HEAD --stdout | mail-app-cli send --from-mbox -

  # Or specify account explicitly
  mail-app-cli send --account "Gmail" --from-mbox 0001-my-patch.patch
  mail-app-cli send -a "Gmail" --from-mbox - < patches.mbox`,
	RunE: func(cmd *cobra.Command, args []string) error {
		// Mbox mode: send from mbox file (account may be auto-detected)
		if sendFromMbox != "" {
			return sendFromMboxFile(sendAccount, sendFromMbox)
		}

		// Regular mode requires account
		if sendAccount == "" {
			return fmt.Errorf("--account is required")
		}

		// Regular mode: validate required fields
		if len(sendTo) == 0 {
			return fmt.Errorf("at least one --to recipient is required")
		}
		if sendSubject == "" {
			return fmt.Errorf("--subject is required")
		}

		client := mail.NewClient()
		err := client.SendMessage(sendAccount, sendSubject, sendBody, sendTo, sendCc, sendBcc, sendAttachments)
		if err != nil {
			return fmt.Errorf("failed to send message: %w", err)
		}

		if len(sendAttachments) > 0 {
			fmt.Fprintf(os.Stderr, "Message sent to %s with %d attachment(s)\n", strings.Join(sendTo, ", "), len(sendAttachments))
		} else {
			fmt.Fprintf(os.Stderr, "Message sent to: %s\n", strings.Join(sendTo, ", "))
		}
		return nil
	},
}

func sendFromMboxFile(account, mboxPath string) error {
	var reader io.Reader

	if mboxPath == "-" {
		reader = os.Stdin
	} else {
		file, err := os.Open(mboxPath)
		if err != nil {
			return fmt.Errorf("failed to open mbox file: %w", err)
		}
		defer file.Close()
		reader = file
	}

	mr := mbox.NewReader(reader)
	client := mail.NewClient()
	messageCount := 0

	for {
		msgReader, err := mr.NextMessage()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to read mbox message: %w", err)
		}

		// Parse the message to extract headers and body
		msg, err := netmail.ReadMessage(msgReader)
		if err != nil {
			return fmt.Errorf("failed to parse email message: %w", err)
		}

		to := parseAddressList(msg.Header.Get("To"))
		cc := parseAddressList(msg.Header.Get("Cc"))
		bcc := parseAddressList(msg.Header.Get("Bcc"))
		subject := msg.Header.Get("Subject")

		// Auto-detect account from patch From header if not specified
		sendAccount := account
		if sendAccount == "" {
			fromHeader := msg.Header.Get("From")
			if fromHeader != "" {
				fromEmail := extractEmailAddress(fromHeader)
				matchedAccount, err := findAccountByEmail(client, fromEmail)
				if err != nil {
					return fmt.Errorf("failed to find account for %s: %w", fromEmail, err)
				}
				sendAccount = matchedAccount
				fmt.Fprintf(os.Stderr, "Auto-detected account: %s (from patch author: %s)\n", sendAccount, fromHeader)
			} else {
				return fmt.Errorf("no --account specified and no From header in patch to auto-detect")
			}
		}

		// Read only the body (after headers) - this preserves git patch content
		bodyBytes, err := io.ReadAll(msg.Body)
		if err != nil {
			return fmt.Errorf("failed to read message body: %w", err)
		}
		body := string(bodyBytes)

		var attachments []string
		finalBody := body

		if sendAsAttachment {
			// Create a temp file for the patch
			safeSubject := strings.Map(func(r rune) rune {
				if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
					return r
				}
				return '_'
			}, subject)
			if safeSubject == "" {
				safeSubject = "patch"
			}
			
			tmpFile, err := os.CreateTemp("", fmt.Sprintf("%s-*.patch", safeSubject))
			if err != nil {
				return fmt.Errorf("failed to create temp file: %w", err)
			}
			defer os.Remove(tmpFile.Name())
			defer tmpFile.Close()

			if _, err := tmpFile.Write(bodyBytes); err != nil {
				return fmt.Errorf("failed to write patch to temp file: %w", err)
			}
			
			attachments = append(attachments, tmpFile.Name())
			finalBody = fmt.Sprintf("Please see attached patch: %s\n\nOriginal Subject: %s", subject, subject)
		} else {
			// Double leading spaces to work around Mail.app stripping single spaces in plain text
			// Context lines in diffs start with exactly 1 space
			if !sendPreserveSpaces {
				finalBody = doubleLeadingSpaces(body)
			}
		}

		// Send message
		if sendPreserveSpaces && !sendAsAttachment {
			err = client.SendMessagePreserveWhitespace(sendAccount, subject, finalBody, to, cc, bcc, []string{})
		} else {
			err = client.SendMessage(sendAccount, subject, finalBody, to, cc, bcc, attachments)
		}
		if err != nil {
			return fmt.Errorf("failed to send message %d: %w", messageCount+1, err)
		}

		messageCount++
		fmt.Fprintf(os.Stderr, "Sent message %d: %s\n", messageCount, subject)
	}

	if messageCount == 0 {
		return fmt.Errorf("no messages found in mbox file")
	}

	fmt.Fprintf(os.Stderr, "Successfully sent %d message(s)\n", messageCount)
	return nil
}

func doubleLeadingSpaces(body string) string {
	lines := strings.Split(body, "\n")
	inHunk := false

	for i, line := range lines {
		// Track if we're inside a diff hunk
		if strings.HasPrefix(line, "@@") {
			inHunk = true
			continue
		}
		// End of hunk when we see "diff --git" or another @@ or end of changes
		if strings.HasPrefix(line, "diff ") || strings.HasPrefix(line, "---") && i > 0 && strings.HasPrefix(lines[i-1], "+++") {
			inHunk = false
		}

		// Only double spaces on context lines INSIDE hunks
		// Context lines are: " unchanged line" (space followed by content)
		// Don't touch: "+added", "-removed", "@@", or lines outside hunks
		if inHunk && len(line) > 0 && line[0] == ' ' {
			lines[i] = " " + line
		}
	}
	return strings.Join(lines, "\n")
}

func parseAddressList(headerValue string) []string {
	if headerValue == "" {
		return []string{}
	}

	addresses, err := netmail.ParseAddressList(headerValue)
	if err != nil {
		// If parsing fails, try splitting by comma as fallback
		parts := strings.Split(headerValue, ",")
		result := make([]string, 0, len(parts))
		for _, part := range parts {
			trimmed := strings.TrimSpace(part)
			if trimmed != "" {
				result = append(result, trimmed)
			}
		}
		return result
	}

	result := make([]string, 0, len(addresses))
	for _, addr := range addresses {
		result = append(result, addr.Address)
	}
	return result
}

func findAccountByEmail(client *mail.Client, email string) (string, error) {
	accounts, err := client.GetAccountsJSON()
	if err != nil {
		return "", fmt.Errorf("failed to list accounts: %w", err)
	}

	email = strings.ToLower(strings.TrimSpace(email))

	for _, account := range accounts {
		accountEmail := strings.ToLower(strings.TrimSpace(account.EmailAddress))
		if accountEmail == email {
			return account.Name, nil
		}
	}

	return "", fmt.Errorf("no Mail.app account found for email address: %s", email)
}

func init() {
	sendCmd.Flags().StringVarP(&sendAccount, "account", "a", "", "Account to send from (optional with --from-mbox, auto-detects from patch author)")
	sendCmd.Flags().StringSliceVarP(&sendTo, "to", "t", []string{}, "To recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendCc, "cc", "c", []string{}, "Cc recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendBcc, "bcc", "b", []string{}, "Bcc recipients (can be specified multiple times)")
	sendCmd.Flags().StringVarP(&sendSubject, "subject", "s", "", "Email subject (required)")
	sendCmd.Flags().StringVarP(&sendBody, "body", "", "", "Email body content")
	sendCmd.Flags().StringSliceVar(&sendAttachments, "attach", []string{}, "File paths to attach (can be specified multiple times)")
	sendCmd.Flags().StringVar(&sendFromMbox, "from-mbox", "", "Send from mbox format file (use '-' for stdin)")
	sendCmd.Flags().BoolVar(&sendPreserveSpaces, "preserve-whitespace", false, "Preserve leading whitespace using HTML <pre> tags (useful for code/patches)")
	sendCmd.Flags().BoolVar(&sendAsAttachment, "as-attachment", false, "Send patch content as an attachment instead of inline body (prevents corruption)")
}

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
	sendAccount     string
	sendTo          []string
	sendCc          []string
	sendBcc         []string
	sendSubject     string
	sendBody        string
	sendAttachments []string
	sendFromMbox    string
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
  mail-app-cli send --account "Gmail" --from-mbox 0001-my-patch.patch
  mail-app-cli send -a "Gmail" --from-mbox - < patches.mbox
  git format-patch HEAD~3..HEAD --stdout | mail-app-cli send -a "Gmail" --from-mbox -`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if sendAccount == "" {
			return fmt.Errorf("--account is required")
		}

		// Mbox mode: send from mbox file
		if sendFromMbox != "" {
			return sendFromMboxFile(sendAccount, sendFromMbox)
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

		msg, err := netmail.ReadMessage(msgReader)
		if err != nil {
			return fmt.Errorf("failed to parse email message: %w", err)
		}

		// Extract recipients
		to := parseAddressList(msg.Header.Get("To"))
		cc := parseAddressList(msg.Header.Get("Cc"))
		bcc := parseAddressList(msg.Header.Get("Bcc"))
		subject := msg.Header.Get("Subject")

		// Read body
		bodyBytes, err := io.ReadAll(msg.Body)
		if err != nil {
			return fmt.Errorf("failed to read message body: %w", err)
		}
		body := string(bodyBytes)

		// Send message
		err = client.SendMessage(account, subject, body, to, cc, bcc, []string{})
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

func init() {
	sendCmd.Flags().StringVarP(&sendAccount, "account", "a", "", "Account to send from (required)")
	sendCmd.Flags().StringSliceVarP(&sendTo, "to", "t", []string{}, "To recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendCc, "cc", "c", []string{}, "Cc recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendBcc, "bcc", "b", []string{}, "Bcc recipients (can be specified multiple times)")
	sendCmd.Flags().StringVarP(&sendSubject, "subject", "s", "", "Email subject (required)")
	sendCmd.Flags().StringVarP(&sendBody, "body", "", "", "Email body content")
	sendCmd.Flags().StringSliceVar(&sendAttachments, "attach", []string{}, "File paths to attach (can be specified multiple times)")
	sendCmd.Flags().StringVar(&sendFromMbox, "from-mbox", "", "Send from mbox format file (use '-' for stdin)")

	sendCmd.MarkFlagRequired("account")
}

package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/intelligrit/mail-app-cli/pkg/mail"
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
)

var sendCmd = &cobra.Command{
	Use:   "send",
	Short: "Send an email message",
	Long: `Send an email message through Mail.app.
Examples:
  mail-app-cli send --account "Gmail" --to user@example.com --subject "Hello" --body "Message content"
  mail-app-cli send -a "Gmail" -t user@example.com -t another@example.com --subject "Multi recipient" --body "Content"
  mail-app-cli send -a "Gmail" -t user@example.com -s "With attachments" --body "See attached" --attach ~/file.pdf --attach ~/image.png`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if sendAccount == "" {
			return fmt.Errorf("--account is required")
		}
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

func init() {
	sendCmd.Flags().StringVarP(&sendAccount, "account", "a", "", "Account to send from (required)")
	sendCmd.Flags().StringSliceVarP(&sendTo, "to", "t", []string{}, "To recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendCc, "cc", "c", []string{}, "Cc recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendBcc, "bcc", "b", []string{}, "Bcc recipients (can be specified multiple times)")
	sendCmd.Flags().StringVarP(&sendSubject, "subject", "s", "", "Email subject (required)")
	sendCmd.Flags().StringVarP(&sendBody, "body", "", "", "Email body content")
	sendCmd.Flags().StringSliceVar(&sendAttachments, "attach", []string{}, "File paths to attach (can be specified multiple times)")

	sendCmd.MarkFlagRequired("account")
	sendCmd.MarkFlagRequired("to")
	sendCmd.MarkFlagRequired("subject")
}

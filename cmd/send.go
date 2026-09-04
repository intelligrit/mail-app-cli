package cmd

import (
	"fmt"
	netmail "net/mail"
	"os"
	"strings"

	"github.com/intelligrit/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

var (
	sendAccount     string
	sendFrom        string
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
  mail-app-cli send --from "user@example.com" --to user@example.com --subject "Hello" --body "Message content"
  mail-app-cli send -a "Gmail" -f "Sender <user@example.com>" -t user@example.com -s "Subject" --body "Content"
  mail-app-cli send -a "Gmail" -t user@example.com -s "With attachments" --body "See attached" --attach ~/file.pdf`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(sendTo) == 0 {
			return fmt.Errorf("at least one --to recipient is required")
		}
		if sendSubject == "" {
			return fmt.Errorf("--subject is required")
		}

		client := mail.NewClient()

		// If sendAccount is not specified, try to infer it from sendFrom or single account
		if sendAccount == "" {
			var rawEmail string
			if sendFrom != "" {
				if addr, err := netmail.ParseAddress(sendFrom); err == nil {
					rawEmail = strings.ToLower(strings.TrimSpace(addr.Address))
				} else {
					rawEmail = strings.ToLower(strings.Trim(strings.TrimSpace(sendFrom), "<>"))
				}
			}

			accounts, err := client.GetAccountsJSON()
			if err == nil {
				if rawEmail != "" {
					for _, acc := range accounts {
						if strings.ToLower(acc.EmailAddress) == rawEmail {
							sendAccount = acc.Name
							break
						}
						for _, alias := range acc.EmailAddresses {
							if strings.ToLower(alias) == rawEmail {
								sendAccount = acc.Name
								break
							}
						}
						if sendAccount != "" {
							break
						}
					}
				}
				if sendAccount == "" && len(accounts) == 1 {
					sendAccount = accounts[0].Name
				}
			}
		}

		if sendAccount == "" {
			return fmt.Errorf("--account is required (or specify --from matching a configured account)")
		}

		err := client.SendMessage(sendAccount, sendFrom, sendSubject, sendBody, sendTo, sendCc, sendBcc, sendAttachments)
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
	sendCmd.Flags().StringVarP(&sendAccount, "account", "a", "", "Account to send from (inferred from --from if omitted)")
	sendCmd.Flags().StringVarP(&sendFrom, "from", "f", "", "From address or sender (e.g. \"Name <addr@example.com>\" or \"addr@example.com\")")
	sendCmd.Flags().StringSliceVarP(&sendTo, "to", "t", []string{}, "To recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendCc, "cc", "c", []string{}, "Cc recipients (can be specified multiple times)")
	sendCmd.Flags().StringSliceVarP(&sendBcc, "bcc", "b", []string{}, "Bcc recipients (can be specified multiple times)")
	sendCmd.Flags().StringVarP(&sendSubject, "subject", "s", "", "Email subject (required)")
	sendCmd.Flags().StringVarP(&sendBody, "body", "", "", "Email body content")
	sendCmd.Flags().StringSliceVar(&sendAttachments, "attach", []string{}, "File paths to attach (can be specified multiple times)")

	sendCmd.MarkFlagRequired("to")
	sendCmd.MarkFlagRequired("subject")
}

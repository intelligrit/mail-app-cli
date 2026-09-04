package cmd

import (
	"fmt"

	"github.com/intelligrit/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

var (
	openAccount string
	openMailbox string
)

var openCmd = &cobra.Command{
	Use:   "open [message-id]",
	Short: "Open Mail.app and optionally focus an account, mailbox, or message",
	Long: `Open and activate Mail.app. Optionally focus a mailbox or open a message.
Examples:
  mail-app-cli open
  mail-app-cli open -a "Gmail" -m "INBOX"
  mail-app-cli open 12345 -a "Gmail" -m "INBOX"`,
	Args: cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		var messageID string
		if len(args) > 0 {
			messageID = args[0]
		}

		client := mail.NewClient()
		if err := client.OpenInMail(openAccount, openMailbox, messageID); err != nil {
			return fmt.Errorf("failed to open in Mail.app: %w", err)
		}
		return nil
	},
}

func init() {
	openCmd.Flags().StringVarP(&openAccount, "account", "a", "", "Account name")
	openCmd.Flags().StringVarP(&openMailbox, "mailbox", "m", "", "Mailbox name")
	rootCmd.AddCommand(openCmd)
}

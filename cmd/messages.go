package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/emersion/go-mbox"
	"github.com/robertmeta/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

var (
	msgAccount      string
	msgMailbox      string
	msgLimit        int
	msgOffset       int
	msgUnread       bool
	msgFlaggedFilter bool
	msgWithContent  bool
	msgRead         bool
	msgFlaggedSet   bool
	msgMessageID    string
	msgSince        string
)

var messagesCmd = &cobra.Command{
	Use:   "messages",
	Short: "Manage Mail.app messages",
	Long:  `View and manage email messages in Mail.app.`,
}

var messagesListCmd = &cobra.Command{
	Use:   "list",
	Short: "List messages",
	Long:  `List messages from a specific mailbox. Output is JSON format. Use jq for pretty printing: mail-app-cli messages list -a Account -m INBOX | jq`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		messages, err := client.GetMessagesJSON(msgAccount, msgMailbox, msgLimit, msgOffset, msgUnread, msgFlaggedFilter, msgWithContent, msgSince)
		if err != nil {
			return fmt.Errorf("failed to get messages: %w", err)
		}

		output, err := json.MarshalIndent(messages, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal messages: %w", err)
		}

		fmt.Println(string(output))
		return nil
	},
}

var messagesShowCmd = &cobra.Command{
	Use:   "show [message-id]",
	Short: "Show message details",
	Long:  `Show full details of a specific message. Output is JSON format.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		message, err := client.GetMessageDetailsJSON(msgAccount, msgMailbox, messageID)
		if err != nil {
			return fmt.Errorf("failed to get message: %w", err)
		}

		output, err := json.MarshalIndent(message, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal message: %w", err)
		}

		fmt.Println(string(output))
		return nil
	},
}

var messagesMarkCmd = &cobra.Command{
	Use:   "mark [message-id]",
	Short: "Mark message as read/unread",
	Long:  `Mark a message as read or unread.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		err := client.MarkMessageAsRead(msgAccount, msgMailbox, messageID, msgRead)
		if err != nil {
			return fmt.Errorf("failed to mark message: %w", err)
		}

		status := "unread"
		if msgRead {
			status = "read"
		}
		fmt.Printf("Message marked as %s\n", status)
		return nil
	},
}

var messagesFlagCmd = &cobra.Command{
	Use:   "flag [message-id]",
	Short: "Flag or unflag a message",
	Long:  `Set or unset the flagged status of a message.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		err := client.FlagMessage(msgAccount, msgMailbox, messageID, msgFlaggedSet)
		if err != nil {
			return fmt.Errorf("failed to flag message: %w", err)
		}

		status := "unflagged"
		if msgFlaggedSet {
			status = "flagged"
		}
		fmt.Printf("Message %s\n", status)
		return nil
	},
}

var messagesDeleteCmd = &cobra.Command{
	Use:   "delete [message-id]",
	Short: "Delete a message",
	Long:  `Move a message to the trash.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		err := client.DeleteMessage(msgAccount, msgMailbox, messageID)
		if err != nil {
			return fmt.Errorf("failed to delete message: %w", err)
		}

		fmt.Println("Message deleted")
		return nil
	},
}

var messagesArchiveCmd = &cobra.Command{
	Use:   "archive [message-id]",
	Short: "Archive a message",
	Long:  `Move a message to the Archive mailbox.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		err := client.ArchiveMessage(msgAccount, msgMailbox, messageID)
		if err != nil {
			return fmt.Errorf("failed to archive message: %w", err)
		}

		fmt.Println("Message archived")
		return nil
	},
}

var messagesMoveCmd = &cobra.Command{
	Use:   "move [message-id] [target-mailbox]",
	Short: "Move a message to another mailbox",
	Long:  `Move a message to a different mailbox.`,
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		messageID := args[0]
		targetMailbox := args[1]
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		err := client.MoveMessage(msgAccount, msgMailbox, messageID, targetMailbox)
		if err != nil {
			return fmt.Errorf("failed to move message: %w", err)
		}

		fmt.Printf("Message moved to %s\n", targetMailbox)
		return nil
	},
}

var messagesExportCmd = &cobra.Command{
	Use:   "export [message-id...]",
	Short: "Export messages in mbox format",
	Long: `Export one or more messages in mbox format to stdout.
This is useful for creating patch series that can be applied with git am.

Examples:
  # Export a single message
  mail-app-cli messages export <id> -a "Gmail" -m "INBOX" > patch.mbox

  # Export multiple messages (e.g., a patch series)
  mail-app-cli messages export <id1> <id2> <id3> -a "Gmail" -m "INBOX" > series.mbox

  # Use with git am
  mail-app-cli messages export <id> -a "Gmail" -m "INBOX" | git am`,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if msgAccount == "" || msgMailbox == "" {
			return fmt.Errorf("both --account and --mailbox are required")
		}

		client := mail.NewClient()
		mw := mbox.NewWriter(os.Stdout)
		defer mw.Close()

		for _, messageID := range args {
			message, err := client.GetMessageDetailsJSON(msgAccount, msgMailbox, messageID)
			if err != nil {
				return fmt.Errorf("failed to get message %s: %w", messageID, err)
			}

			// Parse the date for mbox format
			var msgTime time.Time
			if message.DateSent != "" {
				msgTime, _ = time.Parse(time.RFC1123, message.DateSent)
			}
			if msgTime.IsZero() {
				msgTime = time.Now()
			}

			// Create the mbox message
			from := extractEmailAddress(message.Sender)
			if from == "" {
				from = "unknown@example.com"
			}

			msgWriter, err := mw.CreateMessage(from, msgTime)
			if err != nil {
				return fmt.Errorf("failed to create mbox message: %w", err)
			}

			// Write email headers and body
			email := formatEmailMessage(message)
			if _, err := msgWriter.Write([]byte(email)); err != nil {
				return fmt.Errorf("failed to write message: %w", err)
			}
		}

		return nil
	},
}

func extractEmailAddress(sender string) string {
	// Sender format is typically "Name <email@example.com>" or just "email@example.com"
	if idx := strings.Index(sender, "<"); idx >= 0 {
		if endIdx := strings.Index(sender, ">"); endIdx > idx {
			return sender[idx+1 : endIdx]
		}
	}
	return sender
}

func formatEmailMessage(msg *mail.Message) string {
	var sb strings.Builder

	// Write headers
	sb.WriteString(fmt.Sprintf("From: %s\n", msg.Sender))

	if len(msg.ToRecipients) > 0 {
		sb.WriteString(fmt.Sprintf("To: %s\n", strings.Join(msg.ToRecipients, ", ")))
	}

	if len(msg.CcRecipients) > 0 {
		sb.WriteString(fmt.Sprintf("Cc: %s\n", strings.Join(msg.CcRecipients, ", ")))
	}

	if len(msg.BccRecipients) > 0 {
		sb.WriteString(fmt.Sprintf("Bcc: %s\n", strings.Join(msg.BccRecipients, ", ")))
	}

	sb.WriteString(fmt.Sprintf("Subject: %s\n", msg.Subject))
	sb.WriteString(fmt.Sprintf("Date: %s\n", msg.DateSent))
	sb.WriteString(fmt.Sprintf("Message-ID: <%s>\n", msg.ID))

	// Blank line between headers and body
	sb.WriteString("\n")

	// Write body
	sb.WriteString(msg.Content)
	sb.WriteString("\n")

	return sb.String()
}

func init() {
	messagesCmd.AddCommand(messagesListCmd)
	messagesCmd.AddCommand(messagesShowCmd)
	messagesCmd.AddCommand(messagesMarkCmd)
	messagesCmd.AddCommand(messagesFlagCmd)
	messagesCmd.AddCommand(messagesDeleteCmd)
	messagesCmd.AddCommand(messagesArchiveCmd)
	messagesCmd.AddCommand(messagesMoveCmd)
	messagesCmd.AddCommand(messagesExportCmd)

	// Common flags for all message commands
	messagesCmd.PersistentFlags().StringVarP(&msgAccount, "account", "a", "", "Account name (required)")
	messagesCmd.PersistentFlags().StringVarP(&msgMailbox, "mailbox", "m", "", "Mailbox name (required)")

	// List-specific flags
	messagesListCmd.Flags().IntVarP(&msgLimit, "limit", "l", 25, "Maximum number of messages to display")
	messagesListCmd.Flags().IntVarP(&msgOffset, "offset", "o", 0, "Number of messages to skip (for pagination)")
	messagesListCmd.Flags().BoolVarP(&msgUnread, "unread", "u", false, "Show only unread messages")
	messagesListCmd.Flags().BoolVarP(&msgFlaggedFilter, "flagged", "f", false, "Show only flagged messages")
	messagesListCmd.Flags().BoolVar(&msgWithContent, "with-content", false, "Include message content (slower but better for accessibility)")
	messagesListCmd.Flags().StringVarP(&msgSince, "since", "s", "", "Show messages since date (format: YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)")

	// Mark-specific flags
	messagesMarkCmd.Flags().BoolVarP(&msgRead, "read", "r", true, "Mark as read (default) or use --read=false for unread")

	// Flag-specific flags
	messagesFlagCmd.Flags().BoolVarP(&msgFlaggedSet, "flagged", "f", true, "Flag message (default) or use --flagged=false to unflag")
}

package cmd

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"mime/quotedprintable"
	"strings"
	"io"

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

		for i, messageID := range args {
			// Get the raw message source to extract patch content
			source, err := client.GetMessageSource(msgAccount, msgMailbox, messageID)
			if err != nil {
				return fmt.Errorf("failed to get message source %s: %w", messageID, err)
			}

			// Extract plain text body from MIME message
			content := extractPlainTextBody(source)

			// Add separator between multiple messages for git am
			if i > 0 {
				fmt.Println()
			}

			fmt.Print(content)
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

func extractPlainTextBody(source string) string {
	// Find the text/plain part in the MIME message
	textPlainStart := strings.Index(source, "Content-Type: text/plain")
	if textPlainStart == -1 {
		// No plain text part, return empty
		return ""
	}

	// Find the start of the body content (after headers, at first blank line)
	searchFrom := source[textPlainStart:]
	bodyStart := strings.Index(searchFrom, "\n\n")
	if bodyStart == -1 {
		bodyStart = strings.Index(searchFrom, "\r\n\r\n")
	}
	if bodyStart == -1 {
		return ""
	}

	// Find the end of this MIME part (next boundary or next Content-Type)
	bodyContent := searchFrom[bodyStart:]
	endMarkers := []string{"\n--", "\r\n--", "\nContent-Type:", "\r\nContent-Type:"}
	endPos := len(bodyContent)
	for _, marker := range endMarkers {
		if pos := strings.Index(bodyContent, marker); pos != -1 && pos < endPos {
			endPos = pos
		}
	}

	bodyContent = bodyContent[:endPos]

	// Check encoding and decode
	if strings.Contains(searchFrom[:bodyStart], "Content-Transfer-Encoding: base64") {
		// Decode base64
		bodyContent = strings.TrimSpace(bodyContent)
		bodyContent = strings.ReplaceAll(bodyContent, "\r\n", "")
		bodyContent = strings.ReplaceAll(bodyContent, "\n", "")
		decoded, err := base64.StdEncoding.DecodeString(bodyContent)
		if err == nil {
			bodyContent = string(decoded)
		}
	} else if strings.Contains(searchFrom[:bodyStart], "Content-Transfer-Encoding: quoted-printable") {
		// Decode quoted-printable
		qpReader := quotedprintable.NewReader(strings.NewReader(bodyContent))
		decoded, err := io.ReadAll(qpReader)
		if err == nil {
			bodyContent = string(decoded)
		}
	}

	// Remove format=flowed quote markers (>)
	lines := strings.Split(bodyContent, "\n")
	for i, line := range lines {
		if strings.HasPrefix(line, "> ") {
			lines[i] = line[2:]
		} else if line == ">" {
			lines[i] = ""
		}
	}
	bodyContent = strings.Join(lines, "\n")

	// Remove one leading space from doubled spaces (workaround for Mail.app stripping)
	// We double spaces when sending, so we need to un-double when exporting
	lines = strings.Split(bodyContent, "\n")
	for i, line := range lines {
		if len(line) >= 2 && line[0] == ' ' && line[1] == ' ' {
			lines[i] = line[1:] // Remove first space, keeping the rest
		}
	}
	bodyContent = strings.Join(lines, "\n")

	return strings.TrimSpace(bodyContent)
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

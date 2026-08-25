package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/intelligrit/mail-app-cli/pkg/cache"
	"github.com/intelligrit/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

const messageCacheTTL = 5 * time.Minute

var (
	msgAccount       string
	msgMailbox       string
	msgLimit         int
	msgOffset        int
	msgUnread        bool
	msgFlaggedFilter bool
	msgWithContent   bool
	msgRead          bool
	msgFlaggedSet    bool
	msgSince         string
	msgNoCache       bool
	msgForceRefresh  bool
	msgGmailPolicy   string
)

// sanitizeCacheKey replaces non-alphanumeric chars so the key is safe as a filename component.
func sanitizeCacheKey(s string) string {
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else {
			b.WriteRune('-')
		}
	}
	return b.String()
}

// invalidateMailboxCache removes all message-list cache entries for the given mailbox.
// Call this after any mutation so subsequent list commands see fresh data.
func invalidateMailboxCache(account, mailbox string) {
	if c, err := cache.New(); err == nil {
		prefix := fmt.Sprintf("msgs-%s-%s-", sanitizeCacheKey(account), sanitizeCacheKey(mailbox))
		if mailbox == "" {
			// Every mailbox of the account.
			prefix = fmt.Sprintf("msgs-%s-", sanitizeCacheKey(account))
		}
		c.DeletePrefix(prefix)
	}
}

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

		// Build a cache key that encodes all query parameters so different queries
		// get separate cache entries.
		cacheKey := fmt.Sprintf("msgs-%s-%s-%d-%d-%v-%v-%s-%v",
			sanitizeCacheKey(msgAccount),
			sanitizeCacheKey(msgMailbox),
			msgLimit, msgOffset,
			msgUnread, msgFlaggedFilter,
			sanitizeCacheKey(msgSince),
			msgWithContent,
		)

		// Try cache first (skip if content requested — content is per-user and typically large)
		if !msgNoCache && !msgForceRefresh {
			c, err := cache.New()
			if err == nil {
				c.SetTTL(messageCacheTTL)
				var cached []mail.Message
				found, err := c.Get(cacheKey, &cached)
				if err == nil && found {
					output, err := json.MarshalIndent(cached, "", "  ")
					if err != nil {
						return fmt.Errorf("failed to marshal messages: %w", err)
					}
					fmt.Println(string(output))
					return nil
				}
			}
		}

		client := mail.NewClient()
		messages, err := client.GetMessagesJSON(msgAccount, msgMailbox, msgLimit, msgOffset, msgUnread, msgFlaggedFilter, msgWithContent, msgSince)
		if err != nil {
			return fmt.Errorf("failed to get messages: %w", err)
		}

		// Populate cache (always write unless --no-cache)
		if !msgNoCache {
			if c, err := cache.New(); err == nil {
				c.SetTTL(messageCacheTTL)
				c.Set(cacheKey, messages)
			}
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

// reportMutation prints a batch result and returns an error if any ID failed.
func reportMutation(res *mail.MutationResult, verb string) error {
	n := len(res.Succeeded)
	if n == 1 {
		fmt.Fprintf(os.Stderr, "Message %s\n", verb)
	} else {
		fmt.Fprintf(os.Stderr, "%d messages %s\n", n, verb)
	}
	return res.Err()
}

// runGlobal applies action to IDs without account/mailbox context, prints
// the per-message JSON results to stdout and a summary to stderr, and
// invalidates every mailbox cache touched.
func runGlobal(ids []string, action, target, verb string) error {
	summary, err := mail.NewClient().MutateMessagesGlobal(ids, action, target, msgGmailPolicy)
	if err != nil {
		return fmt.Errorf("failed to %s messages: %w", action, err)
	}
	touched := map[string]bool{}
	for _, r := range summary.Results {
		if r.Account != "" && !touched[r.Account] {
			touched[r.Account] = true
			invalidateMailboxCache(r.Account, "")
		}
	}
	output, _ := json.MarshalIndent(summary, "", "  ")
	fmt.Println(string(output))
	line := fmt.Sprintf("%d messages %s", summary.OK, verb)
	if summary.Skipped > 0 {
		line += fmt.Sprintf(", %d skipped (Gmail)", summary.Skipped)
	}
	if summary.Missing+summary.Failed > 0 {
		line += fmt.Sprintf(", %d failed", summary.Missing+summary.Failed)
	}
	fmt.Fprintln(os.Stderr, line)
	return summary.Err()
}

// hasMailboxContext reports whether --account/--mailbox were both given.
// Without them, commands resolve messages globally by ID.
func hasMailboxContext() (bool, error) {
	if msgAccount == "" && msgMailbox == "" {
		return false, nil
	}
	if msgAccount == "" || msgMailbox == "" {
		return false, fmt.Errorf("give both --account and --mailbox, or neither (IDs are then resolved globally)")
	}
	return true, nil
}

const globalHelp = `
With --account and --mailbox the IDs are looked up in that mailbox. Without
them, IDs are resolved globally (Mail.app message IDs are unique across all
accounts), so one call can mix messages from any accounts; the output is then
a JSON summary with a per-message status (ok, missing, failed, skipped).`

var messagesMarkCmd = &cobra.Command{
	Use:   "mark [message-id...]",
	Short: "Mark messages as read/unread",
	Long:  `Mark one or more messages as read or unread. All IDs are processed in a single Mail.app call.` + globalHelp,
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		scoped, err := hasMailboxContext()
		if err != nil {
			return err
		}
		status := "marked as unread"
		action := "unread"
		if msgRead {
			status = "marked as read"
			action = "read"
		}
		if !scoped {
			return runGlobal(args, action, "", status)
		}
		res, err := mail.NewClient().MarkMessages(msgAccount, msgMailbox, args, msgRead)
		if err != nil {
			return fmt.Errorf("failed to mark messages: %w", err)
		}
		invalidateMailboxCache(msgAccount, msgMailbox)
		return reportMutation(res, status)
	},
}

var messagesFlagCmd = &cobra.Command{
	Use:   "flag [message-id...]",
	Short: "Flag or unflag messages",
	Long:  `Set or unset the flagged status of one or more messages. All IDs are processed in a single Mail.app call.` + globalHelp,
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		scoped, err := hasMailboxContext()
		if err != nil {
			return err
		}
		status := "unflagged"
		action := "unflag"
		if msgFlaggedSet {
			status = "flagged"
			action = "flag"
		}
		if !scoped {
			return runGlobal(args, action, "", status)
		}
		res, err := mail.NewClient().FlagMessages(msgAccount, msgMailbox, args, msgFlaggedSet)
		if err != nil {
			return fmt.Errorf("failed to flag messages: %w", err)
		}
		invalidateMailboxCache(msgAccount, msgMailbox)
		return reportMutation(res, status)
	},
}

var messagesDeleteCmd = &cobra.Command{
	Use:   "delete [message-id...]",
	Short: "Delete messages",
	Long: `Move one or more messages to the trash. All IDs are processed in a single Mail.app call.
Deleting a message that is already in Trash removes it permanently.` + globalHelp,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		scoped, err := hasMailboxContext()
		if err != nil {
			return err
		}
		if !scoped {
			return runGlobal(args, "delete", "", "deleted")
		}
		res, err := mail.NewClient().DeleteMessages(msgAccount, msgMailbox, args)
		if err != nil {
			return fmt.Errorf("failed to delete messages: %w", err)
		}
		invalidateMailboxCache(msgAccount, msgMailbox)
		return reportMutation(res, "deleted")
	},
}

var messagesArchiveCmd = &cobra.Command{
	Use:   "archive [message-id...]",
	Short: "Archive messages",
	Long: `Move one or more messages to the Archive mailbox. All IDs are processed in a single Mail.app call.
Gmail accounts cannot be archived via Mail.app scripting (see README); --gmail
chooses what happens to Gmail messages: skip (default, reported as skipped),
delete (move to Trash) or read (mark as read and leave in place).` + globalHelp,
	Args: cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		switch msgGmailPolicy {
		case "skip", "delete", "read":
		default:
			return fmt.Errorf("--gmail must be skip, delete or read")
		}
		scoped, err := hasMailboxContext()
		if err != nil {
			return err
		}
		if !scoped {
			return runGlobal(args, "archive", "", "archived")
		}
		res, err := mail.NewClient().ArchiveMessages(msgAccount, msgMailbox, args)
		if err != nil {
			return fmt.Errorf("failed to archive messages: %w", err)
		}
		invalidateMailboxCache(msgAccount, msgMailbox)
		invalidateMailboxCache(msgAccount, "Archive")
		return reportMutation(res, "archived")
	},
}

var messagesMoveCmd = &cobra.Command{
	Use:   "move [message-id...] [target-mailbox]",
	Short: "Move messages to another mailbox",
	Long: `Move one or more messages to a different mailbox. The last argument is the target mailbox. All IDs are processed in a single Mail.app call.` + globalHelp + `
When resolving globally, the target is looked up within each message's own account.`,
	Args: cobra.MinimumNArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		scoped, err := hasMailboxContext()
		if err != nil {
			return err
		}
		ids := args[:len(args)-1]
		targetMailbox := args[len(args)-1]
		if !scoped {
			return runGlobal(ids, "move", targetMailbox, "moved to "+targetMailbox)
		}
		res, err := mail.NewClient().MoveMessages(msgAccount, msgMailbox, ids, targetMailbox)
		if err != nil {
			return fmt.Errorf("failed to move messages: %w", err)
		}
		invalidateMailboxCache(msgAccount, msgMailbox)
		invalidateMailboxCache(msgAccount, targetMailbox)
		return reportMutation(res, "moved to "+targetMailbox)
	},
}

// newUnifiedCmd returns a cobra.Command for a unified mailbox view.
// mailboxType must match one of the types understood by GetUnifiedMessagesJSON.
func newUnifiedCmd(use, short, mailboxType string) *cobra.Command {
	return &cobra.Command{
		Use:   use,
		Short: short,
		RunE: func(cmd *cobra.Command, args []string) error {
			client := mail.NewClient()
			messages, err := client.GetUnifiedMessagesJSON(mailboxType, msgLimit, msgOffset, msgWithContent)
			if err != nil {
				return fmt.Errorf("failed to get %s messages: %w", mailboxType, err)
			}

			output, err := json.MarshalIndent(messages, "", "  ")
			if err != nil {
				return fmt.Errorf("failed to marshal messages: %w", err)
			}

			fmt.Println(string(output))
			return nil
		},
	}
}

var messagesInboxCmd = newUnifiedCmd(
	"inbox",
	"List inbox messages across all accounts",
	"inbox",
)

var messagesUnreadCmd = newUnifiedCmd(
	"unread",
	"List unread messages across all accounts",
	"unread",
)

var messagesSentCmd = newUnifiedCmd(
	"sent",
	"List sent messages across all accounts",
	"sent",
)

var messagesDraftsCmd = newUnifiedCmd(
	"drafts",
	"List draft messages across all accounts",
	"drafts",
)

var messagesFlaggedCmd = newUnifiedCmd(
	"flagged",
	"List flagged messages across all accounts",
	"flagged",
)

var messagesTrashCmd = newUnifiedCmd(
	"trash",
	"List trash messages across all accounts",
	"trash",
)

var messagesJunkCmd = newUnifiedCmd(
	"junk",
	"List junk/spam messages across all accounts",
	"junk",
)

func init() {
	messagesCmd.AddCommand(messagesListCmd)
	messagesCmd.AddCommand(messagesShowCmd)
	messagesCmd.AddCommand(messagesMarkCmd)
	messagesCmd.AddCommand(messagesFlagCmd)
	messagesCmd.AddCommand(messagesDeleteCmd)
	messagesCmd.AddCommand(messagesArchiveCmd)
	messagesCmd.AddCommand(messagesMoveCmd)
	// Unified view subcommands
	messagesCmd.AddCommand(messagesInboxCmd)
	messagesCmd.AddCommand(messagesUnreadCmd)
	messagesCmd.AddCommand(messagesSentCmd)
	messagesCmd.AddCommand(messagesDraftsCmd)
	messagesCmd.AddCommand(messagesFlaggedCmd)
	messagesCmd.AddCommand(messagesTrashCmd)
	messagesCmd.AddCommand(messagesJunkCmd)

	// Common flags for all message commands
	messagesCmd.PersistentFlags().StringVarP(&msgAccount, "account", "a", "", "Account name (required for list/show; optional for mutations)")
	messagesCmd.PersistentFlags().StringVarP(&msgMailbox, "mailbox", "m", "", "Mailbox name (required for list/show; optional for mutations)")
	messagesArchiveCmd.Flags().StringVar(&msgGmailPolicy, "gmail", "skip", "What to do with Gmail messages: skip, delete or read")

	// List-specific flags
	messagesListCmd.Flags().IntVarP(&msgLimit, "limit", "l", 25, "Maximum number of messages to display")
	messagesListCmd.Flags().IntVarP(&msgOffset, "offset", "o", 0, "Number of messages to skip (for pagination)")
	messagesListCmd.Flags().BoolVarP(&msgUnread, "unread", "u", false, "Show only unread messages")
	messagesListCmd.Flags().BoolVarP(&msgFlaggedFilter, "flagged", "f", false, "Show only flagged messages")
	messagesListCmd.Flags().BoolVar(&msgWithContent, "with-content", false, "Include message content (slower but better for accessibility)")
	messagesListCmd.Flags().StringVarP(&msgSince, "since", "s", "", "Show messages since date (format: YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)")
	messagesListCmd.Flags().BoolVar(&msgNoCache, "no-cache", false, "Bypass cache and fetch fresh data")
	messagesListCmd.Flags().BoolVar(&msgForceRefresh, "force-refresh", false, "Force refresh cache with fresh data")

	// Mark-specific flags
	messagesMarkCmd.Flags().BoolVarP(&msgRead, "read", "r", true, "Mark as read (default) or use --read=false for unread")

	// Flag-specific flags
	messagesFlagCmd.Flags().BoolVarP(&msgFlaggedSet, "flagged", "f", true, "Flag message (default) or use --flagged=false to unflag")

	// Unified view flags (shared across all unified subcommands)
	for _, cmd := range []*cobra.Command{
		messagesInboxCmd, messagesUnreadCmd, messagesSentCmd,
		messagesDraftsCmd, messagesFlaggedCmd, messagesTrashCmd, messagesJunkCmd,
	} {
		cmd.Flags().IntVarP(&msgLimit, "limit", "l", 25, "Maximum number of messages to return")
		cmd.Flags().IntVarP(&msgOffset, "offset", "o", 0, "Number of messages to skip (pagination)")
		cmd.Flags().BoolVar(&msgWithContent, "with-content", false, "Include message content")
	}
}

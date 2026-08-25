package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/intelligrit/mail-app-cli/pkg/cache"
	"github.com/intelligrit/mail-app-cli/pkg/mail"
	"github.com/spf13/cobra"
)

var (
	mailboxAccount      string
	mailboxNoCache      bool
	mailboxForceRefresh bool
	mailboxWithCounts   bool

	markMailbox  string
	markTrash    bool
	markJunk     bool
	markArchive  bool
	markAll      bool
	markUnread   bool
	markDryRun   bool
	markAccounts []string
)

var mailboxesCmd = &cobra.Command{
	Use:   "mailboxes",
	Short: "Manage Mail.app mailboxes",
	Long:  `View and manage your Mail.app mailboxes.`,
}

var mailboxesListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all mailboxes",
	Long:  `List all mailboxes across all accounts or for a specific account. Output is JSON format. Use jq for pretty printing: mail-app-cli mailboxes list | jq`,
	RunE: func(cmd *cobra.Command, args []string) error {
		var mailboxes []mail.Mailbox

		// Determine cache key based on whether account is specified
		cacheKey := "mailboxes"
		if mailboxAccount != "" {
			cacheKey = fmt.Sprintf("mailboxes-%s", mailboxAccount)
		}
		if mailboxWithCounts {
			cacheKey += "-counts"
		}

		// Try to get from cache if not disabled
		if !mailboxNoCache && !mailboxForceRefresh {
			c, err := cache.New()
			if err == nil {
				found, err := c.Get(cacheKey, &mailboxes)
				if err == nil && found {
					output, err := json.MarshalIndent(mailboxes, "", "  ")
					if err != nil {
						return fmt.Errorf("failed to marshal mailboxes: %w", err)
					}
					fmt.Println(string(output))
					return nil
				}
			}
		}

		// Get from Mail.app
		client := mail.NewClient()
		mailboxes, err := client.GetMailboxesJSON(mailboxAccount, mailboxWithCounts)
		if err != nil {
			return fmt.Errorf("failed to get mailboxes: %w", err)
		}

		// Save to cache if not disabled
		if !mailboxNoCache {
			c, err := cache.New()
			if err == nil {
				c.Set(cacheKey, mailboxes)
			}
		}

		output, err := json.MarshalIndent(mailboxes, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal mailboxes: %w", err)
		}

		fmt.Println(string(output))
		return nil
	},
}

var mailboxesMarkReadCmd = &cobra.Command{
	Use:   "mark-read",
	Short: "Mark every message in a mailbox as read",
	Long: `Mark all messages in one or more mailboxes as read (or unread with --unread).

Target a specific mailbox with --account and --mailbox, or use the provider-
independent selectors --trash, --junk and --archive, which cover every account
(or only the accounts given with --account, repeatable). --all is shorthand for
--trash --junk --archive.

Trash and junk are resolved through Mail.app's own unified mailboxes, so
"Deleted Items", "Trash", "Spam" and "Junk Email" all work. --archive matches a
mailbox literally named "Archive"; Gmail's "All Mail" is skipped because it
also contains every inbox message (use --mailbox "All Mail" explicitly if you
really want that).

Output is a JSON array of {account, mailbox, changed} for each mailbox touched.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		client := mail.NewClient()
		read := !markUnread

		if markAll {
			markTrash, markJunk, markArchive = true, true, true
		}
		var kinds []string
		if markTrash {
			kinds = append(kinds, "trash")
		}
		if markJunk {
			kinds = append(kinds, "junk")
		}
		if markArchive {
			kinds = append(kinds, "archive")
		}

		var results []mail.MailboxMarkResult
		switch {
		case markMailbox != "" && len(kinds) > 0:
			return fmt.Errorf("--mailbox cannot be combined with --trash/--junk/--archive/--all")
		case markMailbox != "":
			if len(markAccounts) != 1 {
				return fmt.Errorf("--mailbox requires exactly one --account")
			}
			changed, err := client.MarkMailboxRead(markAccounts[0], markMailbox, read, markDryRun)
			if err != nil {
				return fmt.Errorf("failed to mark mailbox: %w", err)
			}
			results = []mail.MailboxMarkResult{{Account: markAccounts[0], Mailbox: markMailbox, Changed: changed}}
		case len(kinds) > 0:
			var err error
			results, err = client.MarkSpecialMailboxesRead(kinds, markAccounts, read, markDryRun)
			if err != nil {
				return fmt.Errorf("failed to mark mailboxes: %w", err)
			}
		default:
			return fmt.Errorf("specify --mailbox with --account, or one of --trash/--junk/--archive/--all")
		}

		total := 0
		var failed []string
		for _, r := range results {
			total += r.Changed
			if r.Error != "" {
				failed = append(failed, fmt.Sprintf("%s/%s: %s", r.Account, r.Mailbox, r.Error))
			}
			if !markDryRun {
				invalidateMailboxCache(r.Account, r.Mailbox)
			}
		}
		if !markDryRun {
			if c, err := cache.New(); err == nil {
				c.DeletePrefix("mailboxes")
			}
		}

		output, err := json.MarshalIndent(results, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(output))

		verb := "marked read"
		if !read {
			verb = "marked unread"
		}
		if markDryRun {
			verb = "would be " + verb
		}
		fmt.Fprintf(os.Stderr, "%d messages %s across %d mailboxes\n", total, verb, len(results))
		if len(failed) > 0 {
			return fmt.Errorf("%d mailboxes failed: %s", len(failed), strings.Join(failed, "; "))
		}
		return nil
	},
}

func init() {
	mailboxesCmd.AddCommand(mailboxesListCmd)
	mailboxesCmd.AddCommand(mailboxesMarkReadCmd)
	mailboxesMarkReadCmd.Flags().StringSliceVarP(&markAccounts, "account", "a", nil, "Account name (repeatable; with --mailbox exactly one is required)")
	mailboxesMarkReadCmd.Flags().StringVarP(&markMailbox, "mailbox", "m", "", "Mailbox name to mark")
	mailboxesMarkReadCmd.Flags().BoolVar(&markTrash, "trash", false, "Mark every account's Trash / Deleted Items")
	mailboxesMarkReadCmd.Flags().BoolVar(&markJunk, "junk", false, "Mark every account's Junk / Spam")
	mailboxesMarkReadCmd.Flags().BoolVar(&markArchive, "archive", false, "Mark every account's Archive mailbox")
	mailboxesMarkReadCmd.Flags().BoolVar(&markAll, "all", false, "Shorthand for --trash --junk --archive")
	mailboxesMarkReadCmd.Flags().BoolVar(&markUnread, "unread", false, "Mark as unread instead of read")
	mailboxesMarkReadCmd.Flags().BoolVarP(&markDryRun, "dry-run", "n", false, "Only report how many messages would change")

	mailboxesListCmd.Flags().StringVarP(&mailboxAccount, "account", "a", "", "Filter by account name")
	mailboxesListCmd.Flags().BoolVar(&mailboxNoCache, "no-cache", false, "Bypass cache and fetch fresh data")
	mailboxesListCmd.Flags().BoolVar(&mailboxForceRefresh, "force-refresh", false, "Force refresh cache with fresh data")
	mailboxesListCmd.Flags().BoolVar(&mailboxWithCounts, "counts", false, "Include TotalCount per mailbox (slower: enumerates every mailbox)")
}

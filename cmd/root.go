package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	SilenceUsage: true,
	Use:          "mail-app-cli",
	Short:        "Mail.app CLI - Command line interface for macOS Mail.app",
	Long: `A command line tool for interacting with macOS Mail.app.
Manage accounts, mailboxes, messages, and more from your terminal.`,
	Version: "1.2.0",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.AddCommand(accountsCmd)
	rootCmd.AddCommand(mailboxesCmd)
	rootCmd.AddCommand(messagesCmd)
	rootCmd.AddCommand(sendCmd)
	rootCmd.AddCommand(attachmentsCmd)
	rootCmd.AddCommand(searchCmd)
	rootCmd.AddCommand(syncCmd)
}

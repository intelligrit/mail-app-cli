;;; mail-app-modes.el --- Major modes and keymaps for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Major modes and keymaps for mail-app

(require 'mail-app-core)
(require 'mail-app-emacspeak)



;;; Code:


;;; Keymaps

(defvar mail-app-accounts-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-mailboxes-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "r") 'mail-app-refresh)
    (define-key map (kbd "s") 'mail-app-search)
    (define-key map (kbd "S") 'mail-app-search-all)
    (define-key map (kbd "o") 'mail-app-toggle-accounts-sort)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-accounts-mode'.")



(defvar mail-app-mailboxes-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-messages-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "r") 'mail-app-refresh)
    (define-key map (kbd "s") 'mail-app-search)
    (define-key map (kbd "S") 'mail-app-search-all)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-mailboxes-mode'.")



(defvar mail-app-messages-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-message-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "r") 'mail-app-refresh)
    (define-key map (kbd "s") 'mail-app-search)
    (define-key map (kbd "S") 'mail-app-search-all)
    (define-key map (kbd "f") 'mail-app-flag-message-at-point)
    (define-key map (kbd "F") 'mail-app-forward-message-at-point)
    (define-key map (kbd "d") 'mail-app-delete-message-at-point)
    (define-key map (kbd "a") 'mail-app-archive-message-at-point)
    (define-key map (kbd "!") 'mail-app-junk-message-at-point)
    (define-key map (kbd "v") 'mail-app-move-message-at-point)
    (define-key map (kbd "t") 'mail-app-mark-message-at-point)
    (define-key map (kbd "u") 'mail-app-show-unread)
    (define-key map (kbd "C") 'mail-app-toggle-read-content)
    (define-key map (kbd "o") 'mail-app-sort-messages)
    (define-key map (kbd "O") 'mail-app-reverse-sort)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    (define-key map (kbd "N") 'mail-app-load-more-messages)
    ;; Marking for bulk operations
    (define-key map (kbd "m") 'mail-app-toggle-mark-at-point)
    (define-key map (kbd "M") 'mail-app-toggle-mark-backward)
    (define-key map (kbd "U") 'mail-app-unmark-all)
    (define-key map (kbd "x") 'mail-app-delete-marked)
    (define-key map (kbd ",a") 'mail-app-archive-marked)
    (define-key map (kbd ",f") 'mail-app-flag-marked)
    (define-key map (kbd ",j") 'mail-app-junk-marked)
    (define-key map (kbd ",v") 'mail-app-move-marked)
    (define-key map (kbd ",r") 'mail-app-mark-marked-as-read)
    (define-key map (kbd ",u") 'mail-app-mark-marked-as-unread)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-messages-mode'.")



(defvar mail-app-message-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "r") 'mail-app-reply-current-message)
    (define-key map (kbd "R") 'mail-app-reply-all-current-message)
    (define-key map (kbd "F") 'mail-app-forward-current-message)
    (define-key map (kbd "TAB") 'mail-app-cycle-view)
    (define-key map (kbd "<backtab>") 'mail-app-cycle-view-reverse)
    (define-key map (kbd "b") 'mail-app-jump-to-body)
    (define-key map (kbd "f") 'mail-app-flag-current-message)
    (define-key map (kbd "d") 'mail-app-delete-current-message)
    (define-key map (kbd "a") 'mail-app-archive-current-message)
    (define-key map (kbd "t") 'mail-app-mark-current-message)
    (define-key map (kbd "s") 'mail-app-save-attachment-at-point)
    (define-key map (kbd "RET") 'mail-app-save-attachment-at-point)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-message-view-mode'.")



;;; Major modes

(define-derived-mode mail-app-accounts-mode special-mode "Mail-App-Accounts"
  "Major mode for viewing Mail.app accounts.

This mode displays all configured Mail.app accounts with their email
addresses and enabled status. Use RET to view mailboxes for an account.

Key bindings:
\\{mail-app-accounts-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))



(define-derived-mode mail-app-mailboxes-mode special-mode "Mail-App-Mailboxes"
  "Major mode for viewing Mail.app mailboxes.

This mode displays mailboxes with their unread and total message counts.
Mailboxes with unread messages are shown in bold. Use RET to view messages
in a mailbox, or T to mark all unread messages in a mailbox as read.

Sort methods can be toggled with 'o' to cycle through:
  - default: As returned by mail-app-cli
  - smart: INBOX first, then by unread count, then alphabetical
  - unread: Pure unread count (descending)
  - alpha: Alphabetical by mailbox name

Key bindings:
\\{mail-app-mailboxes-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))



(define-derived-mode mail-app-messages-mode special-mode "Mail-App-Messages"
  "Major mode for viewing messages in a Mail.app mailbox.

This mode displays messages with their subject, sender, and read/flagged status.
Unread messages are shown in bold. Press RET to view a message.

Message actions:
  f - flag/unflag   d - delete   a - archive   t - toggle read/unread
  ! - mark as junk  v - move to another mailbox

Bulk operations (mark messages with 'm', then):
  x   - delete marked    ,a - archive marked   ,f - flag marked
  ,j  - junk marked      ,v - move marked      ,r - mark as read
  ,u  - mark as unread   U  - unmark all

Sort methods (toggle with 'o' and 'O' to reverse):
  date, subject, from, unread

Key bindings:
\\{mail-app-messages-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))



(define-derived-mode mail-app-message-view-mode special-mode "Mail-App-Message"
  "Major mode for viewing a single Mail.app message.

This mode displays the full content of an email message. Use TAB to cycle
through different view modes: plain (basic headers), full (all headers),
and attachments (list attachments).

Message actions:
  r - reply          R - reply all      F - forward
  f - flag/unflag    d - delete         a - archive
  t - mark as unread

In attachments view:
  RET or s - save attachment at point

Key bindings:
\\{mail-app-message-view-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines nil)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))




(defvar mail-app-thread-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-thread-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "r") 'mail-app-refresh)
    (define-key map (kbd "f") 'mail-app-flag-thread-at-point)
    (define-key map (kbd "d") 'mail-app-delete-thread-at-point)
    (define-key map (kbd "a") 'mail-app-archive-thread-at-point)
    (define-key map (kbd "t") 'mail-app-mark-thread-at-point)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "s") 'mail-app-search)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-thread-list-mode'.")



(defvar mail-app-thread-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-message-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "f") 'mail-app-flag-message-at-point)
    (define-key map (kbd "d") 'mail-app-delete-message-at-point)
    (define-key map (kbd "a") 'mail-app-archive-message-at-point)
    (define-key map (kbd "t") 'mail-app-mark-message-at-point)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-thread-view-mode'.")



(define-derived-mode mail-app-thread-list-mode special-mode "Mail-App-Threads"
  "Major mode for viewing threads in a Mail.app mailbox.

This mode displays message threads as a collapsed list. Each thread shows:
  - Unread indicator (●) if ANY message in thread is unread
  - Thread root subject
  - Sender of latest message
  - Message count in thread

Press RET to view the full thread. Single-message threads skip to message view.

Thread actions (affects all messages in thread):
  f - flag    d - delete    a - archive    t - toggle read

Key bindings:
\\{mail-app-thread-list-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))



(define-derived-mode mail-app-thread-view-mode special-mode "Mail-App-Thread"
  "Major mode for viewing a single message thread.

This mode displays all messages in a thread as a visible tree structure:
  - Root message at top (no indent)
  - Replies nested with indentation and → marker

Press RET to view a message's full content.

Message actions:
  f - flag    d - delete    a - archive    t - toggle read

Key bindings:
\\{mail-app-thread-view-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))


(provide 'mail-app-modes)

;;; mail-app-modes.el ends here

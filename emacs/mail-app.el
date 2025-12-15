;;; mail-app.el --- Emacs interface for mail-app CLI -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, mail

;;; Commentary:

;; This package provides an Emacs interface to the mail-app CLI tool.
;; It allows you to view, manage, and interact with macOS Mail.app from Emacs.
;;
;; Features:
;;
;; - View accounts and mailboxes
;; - Browse messages with filters
;; - View full message details
;; - Search email
;; - Flag, archive, delete messages
;; - Full Emacspeak integration for screen reader users
;; - Evil mode support with vim-like keybindings
;;
;; Usage:
;;
;;   M-x mail-app-list-mailboxes
;;
;; This will open the mailboxes list.  From there you can navigate to messages
;; and view message details.

;;; Code:

(require 'seq)
(require 'message)
(require 'sendmail)

;;; Customization

(defgroup mail-app nil
  "Interface to mail-app-cli."
  :group 'tools)

(defcustom mail-app-command "mail-app-cli"
  "Path to the mail-app-cli command-line tool."
  :type 'string
  :group 'mail-app)

(defcustom mail-app-default-account nil
  "Default Mail.app account to use.
If nil, you will be prompted to select one when needed."
  :type '(choice (const :tag "Prompt each time" nil)
                 (string :tag "Account name"))
  :group 'mail-app)

(defcustom mail-app-message-limit 50
  "Default number of messages to display."
  :type 'integer
  :group 'mail-app)

;;; Keymaps

(defvar mail-app-accounts-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'mail-app-view-mailboxes-at-point)
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "r") 'mail-app-refresh)
    (define-key map (kbd "s") 'mail-app-search)
    (define-key map (kbd "c") 'mail-app-compose)
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
    (define-key map (kbd "c") 'mail-app-compose)
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
    (define-key map (kbd "f") 'mail-app-flag-message-at-point)
    (define-key map (kbd "d") 'mail-app-delete-message-at-point)
    (define-key map (kbd "a") 'mail-app-archive-message-at-point)
    (define-key map (kbd "t") 'mail-app-mark-message-at-point)
    (define-key map (kbd "u") 'mail-app-show-unread)
    (define-key map (kbd "c") 'mail-app-compose)
    ;; Marking for bulk operations
    (define-key map (kbd "m") 'mail-app-toggle-mark-at-point)
    (define-key map (kbd "M") 'mail-app-unmark-at-point)
    (define-key map (kbd "U") 'mail-app-unmark-all)
    (define-key map (kbd "x") 'mail-app-delete-marked)
    (define-key map (kbd ",a") 'mail-app-archive-marked)
    (define-key map (kbd ",f") 'mail-app-flag-marked)
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
    (define-key map (kbd "f") 'mail-app-flag-current-message)
    (define-key map (kbd "d") 'mail-app-delete-current-message)
    (define-key map (kbd "a") 'mail-app-archive-current-message)
    (define-key map (kbd "t") 'mail-app-mark-current-message)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "g") 'mail-app-refresh)
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "?") 'describe-mode)
    map)
  "Keymap for `mail-app-message-view-mode'.")

;;; Buffer-local variables

(defvar-local mail-app-current-account nil
  "The currently displayed account.")

(defvar-local mail-app-current-mailbox nil
  "The currently displayed mailbox.")

(defvar-local mail-app-current-message-id nil
  "The currently displayed message ID.")

(defvar-local mail-app-accounts-data nil
  "Cached accounts data for the current buffer.")

(defvar-local mail-app-mailboxes-data nil
  "Cached mailboxes data for the current buffer.")

(defvar-local mail-app-messages-data nil
  "Cached messages data for the current buffer.")

(defvar-local mail-app-show-only-unread nil
  "If non-nil, show only unread messages.")

(defvar-local mail-app-marked-messages nil
  "List of marked message IDs for bulk operations.")

;;; Utility functions

(defun mail-app--run-command (&rest args)
  "Run mail-app-cli command with ARGS and return output."
  (with-temp-buffer
    (let ((exit-code (apply 'call-process mail-app-command nil t nil args)))
      (if (zerop exit-code)
          (buffer-string)
        (error "Mail app command failed: %s" (buffer-string))))))

(defun mail-app--run-command-async (callback &rest args)
  "Run mail-app-cli command with ARGS asynchronously and call CALLBACK with output."
  (let ((output-buffer (generate-new-buffer " *mail-app-async*")))
    (make-process
     :name "mail-app-cli"
     :buffer output-buffer
     :command (cons mail-app-command args)
     :sentinel
     (lambda (process event)
       (when (string-match-p "finished" event)
         (with-current-buffer (process-buffer process)
           (let ((output (buffer-string)))
             (kill-buffer)
             (funcall callback output))))
       (when (string-match-p "exited abnormally" event)
         (with-current-buffer (process-buffer process)
           (let ((error-msg (buffer-string)))
             (kill-buffer)
             (message "Mail app command failed: %s" error-msg))))))))

(defun mail-app--parse-accounts-output (output)
  "Parse accounts list OUTPUT into a list of plists."
  (let ((lines (split-string output "\n" t))
        (accounts '()))
    ;; Skip header and separator lines
    (setq lines (cddr lines))
    ;; Parse each line
    (dolist (line lines)
      (when (string-match "^\\(.+?\\)\\s-+\\(.+?\\)\\s-+\\(.+?\\)\\s-+\\(yes\\|no\\)\\s-*$" line)
        (let ((name (string-trim (match-string 1 line)))
              (email (string-trim (match-string 2 line)))
              (username (string-trim (match-string 3 line)))
              (enabled (string= "yes" (string-trim (match-string 4 line)))))
          (push (list :name name
                      :email email
                      :username username
                      :enabled enabled)
                accounts))))
    (nreverse accounts)))

(defun mail-app--parse-mailboxes-output (output)
  "Parse mailboxes list OUTPUT into a list of plists."
  (let ((lines (split-string output "\n" t))
        (mailboxes '()))
    ;; Skip header and separator lines
    (setq lines (cddr lines))
    ;; Parse each line - match two numbers at the end, then split the rest
    (dolist (line lines)
      (when (string-match "^\\(.+?\\)\\s-+\\(.+?\\)\\s-+\\([0-9]+\\)\\s-+\\([0-9]+\\)\\s-*$" line)
        (let ((account (string-trim (match-string 1 line)))
              (name (string-trim (match-string 2 line)))
              (unread (string-to-number (match-string 3 line)))
              (total (string-to-number (match-string 4 line))))
          (push (list :account account
                      :name name
                      :unread unread
                      :total total)
                mailboxes))))
    (nreverse mailboxes)))

(defun mail-app--parse-messages-output (output)
  "Parse messages list OUTPUT into a list of plists."
  (let ((lines (split-string output "\n" t))
        (messages '()))
    ;; Skip header and separator lines
    (setq lines (cddr lines))
    ;; Parse each line - split on 3+ spaces which act as column separators
    (dolist (line lines)
      (let ((fields (split-string line "\\s-\\s-\\s-+" t)))
        (when (>= (length fields) 4)
          (let* ((id (string-trim (nth 0 fields)))
                 (subject (string-trim (nth 1 fields)))
                 (from (string-trim (nth 2 fields)))
                 (date (string-trim (nth 3 fields)))
                 (read-flag (if (>= (length fields) 5) (nth 4 fields) ""))
                 (flagged-flag (if (>= (length fields) 6) (nth 5 fields) "")))
            (push (list :id id
                        :read (not (string-match-p "✓" (or read-flag "")))
                        :flagged (string-match-p "⚑" (or flagged-flag ""))
                        :from from
                        :subject subject
                        :date date)
                  messages)))))
    (nreverse messages)))

(defun mail-app--get-account-at-point ()
  "Get the account data at point."
  (get-text-property (point) 'mail-app-account-data))

(defun mail-app--get-mailbox-at-point ()
  "Get the mailbox data at point."
  (get-text-property (point) 'mail-app-mailbox-data))

(defun mail-app--get-message-at-point ()
  "Get the message data at point."
  (get-text-property (point) 'mail-app-message-data))

;;; Emacspeak integration

(defun mail-app--emacspeak-speak-line ()
  "Custom Emacspeak line speaking for mail-app."
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
      (when speech-text
        (dtk-speak speech-text)))))

(defun mail-app--emacspeak-post-command ()
  "Emacspeak post-command hook for mail-app modes."
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (mail-app--emacspeak-speak-line)))

;;; Display functions

(defun mail-app--format-accounts (accounts)
  "Format ACCOUNTS for display."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "Mail.app Accounts\n" 'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] view mailboxes  [c] compose  [s] search  [g/r] refresh  [q] quit  [?] help\n\n")
    (insert (format "%-30s %-40s %-10s\n"
                    "ACCOUNT" "EMAIL" "ENABLED"))
    (insert (make-string 85 ?-) "\n")
    (dolist (account accounts)
      (let* ((name (plist-get account :name))
             (email (plist-get account :email))
             (enabled (plist-get account :enabled))
             (line (format "%-30s %-40s %-10s\n"
                           name email (if enabled "yes" "no")))
             (speech-text (format "%s account, %s, %s"
                                  name email (if enabled "enabled" "disabled")))
             (start (point)))
        (insert line)
        (put-text-property start (point) 'mail-app-account-data account)
        (put-text-property start (point) 'emacspeak-speak speech-text)
        (when enabled
          (put-text-property start (point) 'face 'default))))
    (goto-char (point-min))
    (forward-line 5)))  ; Skip title, blank line, commands, blank line, header

(defun mail-app--sort-mailboxes (mailboxes)
  "Sort MAILBOXES with INBOX first, then alphabetically by name."
  (sort mailboxes
        (lambda (a b)
          (let ((name-a (plist-get a :name))
                (name-b (plist-get b :name)))
            (cond
             ;; INBOX always comes first (case-insensitive)
             ((string-equal (upcase name-a) "INBOX") t)
             ((string-equal (upcase name-b) "INBOX") nil)
             ;; Otherwise sort alphabetically
             (t (string< name-a name-b)))))))

(defun mail-app--format-mailboxes (mailboxes)
  "Format MAILBOXES for display."
  (let ((inhibit-read-only t)
        (sorted-mailboxes (mail-app--sort-mailboxes mailboxes)))
    (erase-buffer)
    (insert (propertize (format "Mail.app Mailboxes: %s\n"
                                (or mail-app-current-account "All Accounts"))
                        'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] view messages  [c] compose  [s] search  [g/r] refresh  [q] quit  [?] help\n\n")
    (insert (format "%-30s %-50s %8s %8s\n"
                    "ACCOUNT" "MAILBOX" "UNREAD" "TOTAL"))
    (insert (make-string 100 ?-) "\n")
    (dolist (mailbox sorted-mailboxes)
      (let* ((account (plist-get mailbox :account))
             (name (plist-get mailbox :name))
             (unread (plist-get mailbox :unread))
             (total (plist-get mailbox :total))
             (line (format "%-30s %-50s %8d %8d\n"
                           account name unread total))
             (speech-text (format "%s mailbox in %s account, %d unread, %d total"
                                  name account unread total))
             (start (point)))
        (insert line)
        (put-text-property start (point) 'mail-app-mailbox-data mailbox)
        (put-text-property start (point) 'emacspeak-speak speech-text)
        (when (> unread 0)
          (put-text-property start (point) 'face 'bold))))
    (goto-char (point-min))
    (forward-line 5)))  ; Skip title, blank line, commands, blank line, header

(defun mail-app--format-messages (messages)
  "Format MESSAGES for display."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "Mail.app Messages: %s/%s\n"
                                mail-app-current-account
                                mail-app-current-mailbox)
                        'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] read  [c] compose  [f] flag  [d] delete  [a] archive  [t] toggle read/unread\n")
    (insert "          [s] search  [u] unread filter  [g/r] refresh  [q] quit  [?] help\n")
    (insert "Marking:  [m] mark  [M] unmark  [U] unmark-all  [x] delete marked\n")
    (insert "          [,a] archive marked  [,f] flag marked  [,r] read  [,u] unread\n\n")
    (insert (format "%-2s %-4s %-35s %-58s %-30s\n"
                    "" "FLAG" "FROM" "SUBJECT" "DATE"))
    (insert (make-string 135 ?-) "\n")
    (dolist (message messages)
      (let* ((id (plist-get message :id))
             (read (plist-get message :read))
             (flagged (plist-get message :flagged))
             (from (plist-get message :from))
             (subject (plist-get message :subject))
             (date (plist-get message :date))
             (marked (member id mail-app-marked-messages))
             (mark-str (if marked "*" " "))
             (flag-str (concat (if read "✓" " ") (if flagged "⚑" " ")))
             (line (format "%-2s %-4s %-35s %-58s %-30s\n"
                           mark-str
                           flag-str
                           (truncate-string-to-width from 35 nil nil "...")
                           (truncate-string-to-width subject 58 nil nil "...")
                           (truncate-string-to-width date 30 nil nil "...")))
             (speech-text (format "%s%s%s from %s, %s"
                                  (if marked "Marked. " "")
                                  (if flagged "Flagged message: " "")
                                  subject from date))
             (start (point)))
        (insert line)
        (put-text-property start (point) 'mail-app-message-data message)
        (put-text-property start (point) 'emacspeak-speak speech-text)
        (unless read
          (put-text-property start (point) 'face 'bold))))
    (goto-char (point-min))
    (forward-line 8)))  ; Skip title, blank, command lines (4), blank, header

(defun mail-app--format-message-view (message-id account mailbox)
  "Format full message view for MESSAGE-ID in ACCOUNT and MAILBOX."
  (let* ((output (mail-app--run-command "messages" "show" message-id
                                         "-a" account "-m" mailbox))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "Mail.app Message: %s/%s\n" account mailbox) 'face 'bold))
    (insert "\n")
    (insert "Commands: [r] reply  [R] reply-all  [c] compose  [f] flag  [d] delete  [a] archive\n")
    (insert "          [t] mark unread  [g] refresh  [q] quit  [?] help\n\n")
    (insert (make-string 80 ?=) "\n\n")
    (insert output)
    (goto-char (point-min))
    (forward-line 6)))

;;; Interactive commands - Accounts

;;;###autoload
(defun mail-app-list-accounts ()
  "List all Mail.app accounts."
  (interactive)
  (let* ((output (mail-app--run-command "accounts" "list"))
         (accounts (mail-app--parse-accounts-output output))
         (buf (get-buffer-create "*Mail.app Accounts*")))
    (with-current-buffer buf
      (mail-app-accounts-mode)
      (setq mail-app-accounts-data accounts)
      (mail-app--format-accounts accounts))
    (switch-to-buffer buf)))

(defun mail-app-view-mailboxes-at-point ()
  "View mailboxes for the account at point."
  (interactive)
  (let ((account (mail-app--get-account-at-point)))
    (if (not account)
        (message "No account at point")
      (let ((name (plist-get account :name)))
        (mail-app-list-mailboxes-for-account name)))))

;;; Interactive commands - Mailboxes

(defun mail-app-list-mailboxes-for-account (account)
  "List mailboxes for ACCOUNT."
  (interactive
   (list (read-string "Account: " mail-app-default-account)))
  (let* ((output (mail-app--run-command "mailboxes" "list" "-a" account))
         (mailboxes (mail-app--parse-mailboxes-output output))
         (buf (get-buffer-create (format "*Mail.app Mailboxes: %s*" account))))
    (with-current-buffer buf
      (mail-app-mailboxes-mode)
      (setq mail-app-current-account account)
      (setq mail-app-mailboxes-data mailboxes)
      (mail-app--format-mailboxes mailboxes))
    (switch-to-buffer buf)))

;;;###autoload
(defun mail-app-list-mailboxes ()
  "List all Mail.app mailboxes."
  (interactive)
  (let* ((output (mail-app--run-command "mailboxes" "list"))
         (mailboxes (mail-app--parse-mailboxes-output output))
         (buf (get-buffer-create "*Mail.app Mailboxes*")))
    (with-current-buffer buf
      (mail-app-mailboxes-mode)
      (setq mail-app-mailboxes-data mailboxes)
      (mail-app--format-mailboxes mailboxes))
    (switch-to-buffer buf)))

(defun mail-app-view-messages-at-point ()
  "View messages for the mailbox at point."
  (interactive)
  (let ((mailbox (mail-app--get-mailbox-at-point)))
    (if (not mailbox)
        (message "No mailbox at point")
      (let ((account (plist-get mailbox :account))
            (name (plist-get mailbox :name)))
        (mail-app-list-messages account name)))))

(defun mail-app-refresh ()
  "Refresh the current view."
  (interactive)
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (dtk-speak "Refreshing")
    (emacspeak-icon 'select-object))
  (cond
   ((eq major-mode 'mail-app-accounts-mode)
    (mail-app-list-accounts))
   ((eq major-mode 'mail-app-mailboxes-mode)
    (if mail-app-current-account
        (mail-app-list-mailboxes-for-account mail-app-current-account)
      (mail-app-list-mailboxes)))
   ((eq major-mode 'mail-app-messages-mode)
    (when (and mail-app-current-account mail-app-current-mailbox)
      (mail-app-list-messages mail-app-current-account mail-app-current-mailbox)))
   (t
    (message "Nothing to refresh"))))

;;; Interactive commands - Messages

(defun mail-app-list-messages (account mailbox)
  "List messages for ACCOUNT and MAILBOX."
  (interactive
   (list (read-string "Account: " mail-app-default-account)
         (read-string "Mailbox: " "INBOX")))
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (dtk-speak (format "Loading messages from %s" mailbox))
    (emacspeak-icon 'select-object))
  (let* ((args (list "messages" "list" "-a" account "-m" mailbox
                     "-l" (number-to-string mail-app-message-limit)))
         (args (if mail-app-show-only-unread
                   (append args '("-u"))
                 args))
         (buf (get-buffer-create (format "*Mail.app Messages: %s/%s*" account mailbox))))
    ;; Setup buffer immediately with loading message
    (with-current-buffer buf
      (mail-app-messages-mode)
      (setq mail-app-current-account account)
      (setq mail-app-current-mailbox mailbox)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Loading messages...\n")))
    (switch-to-buffer buf)
    ;; Load messages asynchronously
    (apply 'mail-app--run-command-async
           (lambda (output)
             (let ((messages (mail-app--parse-messages-output output)))
               (when (buffer-live-p buf)
                 (with-current-buffer buf
                   (setq mail-app-messages-data messages)
                   (mail-app--format-messages messages)
                   (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
                     (dtk-speak (format "Loaded %d messages" (length messages)))
                     (emacspeak-icon 'task-done))))))
           args)))

(defun mail-app-view-message-at-point ()
  "View the full message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let ((id (plist-get message :id)))
        (mail-app-view-message id mail-app-current-account mail-app-current-mailbox)))))

(defun mail-app-view-message (message-id account mailbox)
  "View full MESSAGE-ID in ACCOUNT and MAILBOX."
  (interactive
   (list (read-string "Message ID: ")
         (read-string "Account: " mail-app-default-account)
         (read-string "Mailbox: " "INBOX")))
  (let ((buf (get-buffer-create (format "*Mail.app Message: %s*" message-id))))
    (with-current-buffer buf
      (mail-app-message-view-mode)
      (setq mail-app-current-message-id message-id)
      (setq mail-app-current-account account)
      (setq mail-app-current-mailbox mailbox)
      (mail-app--format-message-view message-id account mailbox))
    (switch-to-buffer buf)))

(defun mail-app-show-unread ()
  "Toggle showing only unread messages."
  (interactive)
  (setq mail-app-show-only-unread (not mail-app-show-only-unread))
  (message "Showing %s messages" (if mail-app-show-only-unread "unread" "all"))
  (mail-app-refresh))

;;; Interactive commands - Message actions

(defun mail-app-flag-message-at-point ()
  "Toggle flag on message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let* ((id (plist-get message :id))
             (flagged (plist-get message :flagged))
             (new-state (not flagged)))
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (dtk-speak (if new-state "Flagging message" "Unflagging message"))
          (emacspeak-icon 'select-object))
        (mail-app--run-command "messages" "flag" id
                               "-a" mail-app-current-account
                               "-m" mail-app-current-mailbox
                               "--flagged" (if new-state "true" "false"))
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (emacspeak-icon 'task-done))
        (mail-app-refresh)))))

(defun mail-app-delete-message-at-point ()
  "Delete message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (when (yes-or-no-p "Delete this message? ")
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (dtk-speak "Deleting message")
          (emacspeak-icon 'delete-object))
        (let ((id (plist-get message :id)))
          (mail-app--run-command "messages" "delete" id
                                 "-a" mail-app-current-account
                                 "-m" mail-app-current-mailbox)
          (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
            (emacspeak-icon 'task-done))
          (mail-app-refresh))))))

(defun mail-app-archive-message-at-point ()
  "Archive message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak "Archiving message")
        (emacspeak-icon 'select-object))
      (let ((id (plist-get message :id)))
        (mail-app--run-command "messages" "archive" id
                               "-a" mail-app-current-account
                               "-m" mail-app-current-mailbox)
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (emacspeak-icon 'task-done))
        (mail-app-refresh)))))

(defun mail-app-mark-message-at-point ()
  "Toggle read status of message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let* ((id (plist-get message :id))
             (read (plist-get message :read))
             (new-state (not read)))
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (dtk-speak (format "Marking as %s" (if new-state "read" "unread")))
          (emacspeak-icon 'select-object))
        (mail-app--run-command "messages" "mark" id
                               "-a" mail-app-current-account
                               "-m" mail-app-current-mailbox
                               "--read" (if new-state "true" "false"))
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (emacspeak-icon 'task-done))
        (mail-app-refresh)))))

(defun mail-app-flag-current-message ()
  "Toggle flag on current message in message view."
  (interactive)
  (when mail-app-current-message-id
    (mail-app--run-command "messages" "flag" mail-app-current-message-id
                           "-a" mail-app-current-account
                           "-m" mail-app-current-mailbox
                           "--flagged" "true")
    (message "Message flagged")))

(defun mail-app-delete-current-message ()
  "Delete current message in message view."
  (interactive)
  (when (and mail-app-current-message-id
             (yes-or-no-p "Delete this message? "))
    (mail-app--run-command "messages" "delete" mail-app-current-message-id
                           "-a" mail-app-current-account
                           "-m" mail-app-current-mailbox)
    (message "Message deleted")
    (quit-window)))

(defun mail-app-archive-current-message ()
  "Archive current message in message view."
  (interactive)
  (when mail-app-current-message-id
    (mail-app--run-command "messages" "archive" mail-app-current-message-id
                           "-a" mail-app-current-account
                           "-m" mail-app-current-mailbox)
    (message "Message archived")
    (quit-window)))

(defun mail-app-mark-current-message ()
  "Toggle read status of current message in message view."
  (interactive)
  (when mail-app-current-message-id
    (mail-app--run-command "messages" "mark" mail-app-current-message-id
                           "-a" mail-app-current-account
                           "-m" mail-app-current-mailbox
                           "--read" "false")
    (message "Message marked as unread")))

(defun mail-app--parse-message-headers (output)
  "Parse message headers from OUTPUT and return plist."
  (let ((headers '()))
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (when (re-search-forward "^Subject:\\s-*\\(.+\\)$" nil t)
        (setq headers (plist-put headers :subject (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^From:\\s-*\\(.+\\)$" nil t)
        (setq headers (plist-put headers :from (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^To:\\s-*\\[\\(.+\\)\\]" nil t)
        (setq headers (plist-put headers :to (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^Cc:\\s-*\\[\\(.+\\)\\]" nil t)
        (setq headers (plist-put headers :cc (match-string 1))))
      (goto-char (point-min))
      (when (re-search-forward "^--- Content ---\\s-*\\(.+\\)" nil t)
        (setq headers (plist-put headers :body (buffer-substring (point) (point-max))))))
    headers))

(defun mail-app-reply-current-message ()
  "Reply to current message."
  (interactive)
  (when mail-app-current-message-id
    (let* ((output (mail-app--run-command "messages" "show" mail-app-current-message-id
                                          "-a" mail-app-current-account
                                          "-m" mail-app-current-mailbox))
           (headers (mail-app--parse-message-headers output))
           (from (plist-get headers :from))
           (subject (plist-get headers :subject))
           (body (plist-get headers :body))
           (reply-subject (if (string-prefix-p "Re: " subject)
                              subject
                            (concat "Re: " subject))))
      (setq message-options `((account . ,mail-app-current-account)))
      (compose-mail from
                    reply-subject
                    nil nil nil
                    `((account . ,mail-app-current-account)))
      ;; Set From header based on account
      (message-goto-from)
      (message-beginning-of-line)
      (kill-line)
      (insert (format "From: %s" mail-app-current-account))
      (when body
        (goto-char (point-max))
        (insert "\n\n")
        (insert (replace-regexp-in-string "^" "> " body)))
      (message-goto-body)
      (message "Composing reply..."))))

(defun mail-app-reply-all-current-message ()
  "Reply to all on current message."
  (interactive)
  (when mail-app-current-message-id
    (let* ((output (mail-app--run-command "messages" "show" mail-app-current-message-id
                                          "-a" mail-app-current-account
                                          "-m" mail-app-current-mailbox))
           (headers (mail-app--parse-message-headers output))
           (from (plist-get headers :from))
           (to (plist-get headers :to))
           (cc (plist-get headers :cc))
           (subject (plist-get headers :subject))
           (body (plist-get headers :body))
           (reply-subject (if (string-prefix-p "Re: " subject)
                              subject
                            (concat "Re: " subject)))
           (all-recipients (string-join (delq nil (list from to cc)) ", ")))
      (setq message-options `((account . ,mail-app-current-account)))
      (compose-mail all-recipients
                    reply-subject
                    nil nil nil
                    `((account . ,mail-app-current-account)))
      ;; Set From header based on account
      (message-goto-from)
      (message-beginning-of-line)
      (kill-line)
      (insert (format "From: %s" mail-app-current-account))
      (when body
        (goto-char (point-max))
        (insert "\n\n")
        (insert (replace-regexp-in-string "^" "> " body)))
      (message-goto-body)
      (message "Composing reply to all..."))))

(defun mail-app-send-message ()
  "Send the current message using mail-app-cli."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let* ((to (mail-fetch-field "To"))
           (cc (mail-fetch-field "Cc"))
           (bcc (mail-fetch-field "Bcc"))
           (subject (mail-fetch-field "Subject"))
           (from (mail-fetch-field "From"))
           ;; Extract account from message-options or From header
           (account (or (when (boundp 'message-options)
                          (cdr (assq 'account message-options)))
                       (when from
                         ;; Try to match From email to account
                         (let ((email (if (string-match "<\\(.+\\)>" from)
                                          (match-string 1 from)
                                        from)))
                           ;; Use the email as account identifier
                           email))
                       mail-app-current-account
                       mail-app-default-account
                       (read-string "Account: ")))
           (body-start (save-excursion
                         (goto-char (point-min))
                         (search-forward mail-header-separator nil t)
                         (forward-line 1)
                         (point)))
           (body (buffer-substring-no-properties body-start (point-max))))
      (unless to
        (error "No recipients specified"))
      (unless subject
        (error "No subject specified"))
      (unless account
        (error "No account specified"))
      (let ((args (list "send" "-a" account "-s" subject "--body" body)))
        ;; Add To recipients
        (dolist (recipient (split-string to "," t "\\s-+"))
          (setq args (append args (list "-t" (string-trim recipient)))))
        ;; Add Cc recipients if present
        (when cc
          (dolist (recipient (split-string cc "," t "\\s-+"))
            (setq args (append args (list "-c" (string-trim recipient))))))
        ;; Add Bcc recipients if present
        (when bcc
          (dolist (recipient (split-string bcc "," t "\\s-+"))
            (setq args (append args (list "-b" (string-trim recipient))))))
        (apply 'mail-app--run-command args)
        (message "Message sent via %s" account)
        (kill-buffer)))))

;; Hook into message-mode's send mechanism
(with-eval-after-load 'message
  (defun mail-app--message-send-hook ()
    "Hook to send message via mail-app-cli when using message-mode."
    (when (or (and (boundp 'message-options)
                   (assq 'account message-options))
              mail-app-current-account)
      (mail-app-send-message)
      t))  ; Return t to prevent normal sending

  (add-hook 'message-send-hook 'mail-app--message-send-hook))

;;;###autoload
(defun mail-app-compose ()
  "Compose a new email message."
  (interactive)
  (let ((account (or mail-app-current-account
                     mail-app-default-account
                     (read-string "Account: "))))
    (setq message-options `((account . ,account)))
    (compose-mail nil nil nil nil nil `((account . ,account)))
    ;; Set From header based on account
    (message-goto-from)
    (message-beginning-of-line)
    (kill-line)
    (insert (format "From: %s" account))
    (message-goto-to)
    (message "Composing new message...")))

;;; Marking and bulk operations

(defun mail-app--update-mark-indicator ()
  "Update the mark indicator and speech text for the current line."
  (when-let* ((message (mail-app--get-message-at-point))
              (id (plist-get message :id)))
    (let* ((inhibit-read-only t)
           (marked (member id mail-app-marked-messages))
           (flagged (plist-get message :flagged))
           (subject (plist-get message :subject))
           (from (plist-get message :from))
           (date (plist-get message :date))
           (speech-text (format "%s%s%s from %s, %s"
                                (if marked "Marked. " "")
                                (if flagged "Flagged message: " "")
                                subject from date)))
      (save-excursion
        (beginning-of-line)
        (let ((line-end (line-end-position)))
          ;; Update mark indicator
          (delete-char 1)
          (insert (if marked "*" " "))
          ;; Update speech text property
          (put-text-property (line-beginning-position) line-end 'emacspeak-speak speech-text))))))

(defun mail-app-toggle-mark-at-point ()
  "Toggle mark on the message at point for bulk operations."
  (interactive)
  (when-let* ((message (mail-app--get-message-at-point))
              (id (plist-get message :id)))
    (if (member id mail-app-marked-messages)
        ;; Unmark
        (progn
          (setq mail-app-marked-messages (delete id mail-app-marked-messages))
          (mail-app--update-mark-indicator)
          (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
            (emacspeak-icon 'delete-object))
          (forward-line 1)
          (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
            (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
              (when speech-text
                (dtk-speak speech-text)))))
      ;; Mark
      (progn
        (push id mail-app-marked-messages)
        (mail-app--update-mark-indicator)
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (emacspeak-icon 'mark-object))
        (forward-line 1)
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
            (when speech-text
              (dtk-speak speech-text))))))))

(defun mail-app-unmark-at-point ()
  "Unmark the message at point."
  (interactive)
  (when-let* ((message (mail-app--get-message-at-point))
              (id (plist-get message :id)))
    (setq mail-app-marked-messages (delete id mail-app-marked-messages))
    (mail-app--update-mark-indicator)
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (emacspeak-icon 'delete-object))
    (forward-line 1)
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
        (when speech-text
          (dtk-speak speech-text))))))

(defun mail-app-unmark-all ()
  "Unmark all marked messages."
  (interactive)
  (setq mail-app-marked-messages nil)
  (message "All unmarked")
  (mail-app-refresh))

(defun mail-app-delete-marked ()
  "Delete all marked messages."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (when (yes-or-no-p (format "Delete %d marked messages? " (length mail-app-marked-messages)))
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak (format "Deleting %d messages" (length mail-app-marked-messages)))
        (emacspeak-icon 'select-object))
      (let ((count 0)
            (errors 0))
        (dolist (id mail-app-marked-messages)
          (condition-case err
              (progn
                (mail-app--run-command "messages" "delete" id
                                       "-a" mail-app-current-account
                                       "-m" mail-app-current-mailbox)
                (setq count (1+ count)))
            (error
             (setq errors (1+ errors))
             (message "Error deleting message %s: %s" id (error-message-string err)))))
        (setq mail-app-marked-messages nil)
        (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
          (dtk-speak (format "Deleted %d messages%s" count
                             (if (> errors 0) (format ", %d errors" errors) "")))
          (emacspeak-icon 'task-done))
        (mail-app-refresh)))))

(defun mail-app-archive-marked ()
  "Archive all marked messages."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (dtk-speak (format "Archiving %d messages" (length mail-app-marked-messages)))
      (emacspeak-icon 'select-object))
    (let ((count 0)
          (errors 0))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (progn
              (mail-app--run-command "messages" "archive" id
                                     "-a" mail-app-current-account
                                     "-m" mail-app-current-mailbox)
              (setq count (1+ count)))
          (error
           (setq errors (1+ errors))
           (message "Error archiving message %s: %s" id (error-message-string err)))))
      (setq mail-app-marked-messages nil)
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak (format "Archived %d messages%s" count
                           (if (> errors 0) (format ", %d errors" errors) "")))
        (emacspeak-icon 'task-done))
      (mail-app-refresh))))

(defun mail-app-flag-marked ()
  "Flag all marked messages."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (dtk-speak (format "Flagging %d messages" (length mail-app-marked-messages)))
      (emacspeak-icon 'select-object))
    (let ((count 0)
          (errors 0))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (progn
              (mail-app--run-command "messages" "flag" id
                                     "-a" mail-app-current-account
                                     "-m" mail-app-current-mailbox
                                     "--flagged" "true")
              (setq count (1+ count)))
          (error
           (setq errors (1+ errors))
           (message "Error flagging message %s: %s" id (error-message-string err)))))
      (setq mail-app-marked-messages nil)
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak (format "Flagged %d messages%s" count
                           (if (> errors 0) (format ", %d errors" errors) "")))
        (emacspeak-icon 'task-done))
      (mail-app-refresh))))

(defun mail-app-mark-marked-as-read ()
  "Mark all marked messages as read."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (dtk-speak (format "Marking %d messages as read" (length mail-app-marked-messages)))
      (emacspeak-icon 'select-object))
    (let ((count 0)
          (errors 0))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (progn
              (mail-app--run-command "messages" "mark" id
                                     "-a" mail-app-current-account
                                     "-m" mail-app-current-mailbox
                                     "--read" "true")
              (setq count (1+ count)))
          (error
           (setq errors (1+ errors))
           (message "Error marking message %s: %s" id (error-message-string err)))))
      (setq mail-app-marked-messages nil)
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak (format "Marked %d messages as read%s" count
                           (if (> errors 0) (format ", %d errors" errors) "")))
        (emacspeak-icon 'task-done))
      (mail-app-refresh))))

(defun mail-app-mark-marked-as-unread ()
  "Mark all marked messages as unread."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
      (dtk-speak (format "Marking %d messages as unread" (length mail-app-marked-messages)))
      (emacspeak-icon 'select-object))
    (let ((count 0)
          (errors 0))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (progn
              (mail-app--run-command "messages" "mark" id
                                     "-a" mail-app-current-account
                                     "-m" mail-app-current-mailbox
                                     "--read" "false")
              (setq count (1+ count)))
          (error
           (setq errors (1+ errors))
           (message "Error marking message %s: %s" id (error-message-string err)))))
      (setq mail-app-marked-messages nil)
      (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
        (dtk-speak (format "Marked %d messages as unread%s" count
                           (if (> errors 0) (format ", %d errors" errors) "")))
        (emacspeak-icon 'task-done))
      (mail-app-refresh))))

;;; Search

;;;###autoload
(defun mail-app-search (query)
  "Search for messages matching QUERY."
  (interactive "sSearch query: ")
  (let* ((output (mail-app--run-command "search" query
                                         "-l" (number-to-string mail-app-message-limit)))
         (messages (mail-app--parse-messages-output output))
         (buf (get-buffer-create (format "*Mail.app Search: %s*" query))))
    (with-current-buffer buf
      (mail-app-messages-mode)
      (setq mail-app-messages-data messages)
      (mail-app--format-messages messages))
    (switch-to-buffer buf)))

;;; Major modes

(define-derived-mode mail-app-accounts-mode special-mode "Mail-App-Accounts"
  "Major mode for viewing mail-app accounts.

\\{mail-app-accounts-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t)))

(define-derived-mode mail-app-mailboxes-mode special-mode "Mail-App-Mailboxes"
  "Major mode for viewing mail-app mailboxes.

\\{mail-app-mailboxes-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t)))

(define-derived-mode mail-app-messages-mode special-mode "Mail-App-Messages"
  "Major mode for viewing mail-app messages.

\\{mail-app-messages-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t)))

(define-derived-mode mail-app-message-view-mode special-mode "Mail-App-Message"
  "Major mode for viewing a single mail-app message.

\\{mail-app-message-view-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines nil)
  (when (and (boundp 'emacspeak-speak-mode) emacspeak-speak-mode)
    (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t)))

;;; Evil mode integration

(with-eval-after-load 'evil
  (when (fboundp 'evil-set-initial-state)
    (evil-set-initial-state 'mail-app-accounts-mode 'normal)
    (evil-set-initial-state 'mail-app-mailboxes-mode 'normal)
    (evil-set-initial-state 'mail-app-messages-mode 'normal)
    (evil-set-initial-state 'mail-app-message-view-mode 'normal))

  (when (fboundp 'evil-define-key)
    (evil-define-key 'normal mail-app-accounts-mode-map
      (kbd "RET") 'mail-app-view-mailboxes-at-point
      "c" 'mail-app-compose
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key 'normal mail-app-mailboxes-mode-map
      (kbd "RET") 'mail-app-view-messages-at-point
      "c" 'mail-app-compose
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key 'normal mail-app-messages-mode-map
      (kbd "RET") 'mail-app-view-message-at-point
      "c" 'mail-app-compose
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "f" 'mail-app-flag-message-at-point
      "d" 'mail-app-delete-message-at-point
      "a" 'mail-app-archive-message-at-point
      "t" 'mail-app-mark-message-at-point
      "u" 'mail-app-show-unread
      ;; Marking for bulk operations
      "m" 'mail-app-toggle-mark-at-point
      "M" 'mail-app-unmark-at-point
      "U" 'mail-app-unmark-all
      "x" 'mail-app-delete-marked
      ",a" 'mail-app-archive-marked
      ",f" 'mail-app-flag-marked
      ",r" 'mail-app-mark-marked-as-read
      ",u" 'mail-app-mark-marked-as-unread
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key 'normal mail-app-message-view-mode-map
      "r" 'mail-app-reply-current-message
      "R" 'mail-app-reply-all-current-message
      "c" 'mail-app-compose
      "f" 'mail-app-flag-current-message
      "d" 'mail-app-delete-current-message
      "a" 'mail-app-archive-current-message
      "t" 'mail-app-mark-current-message
      "g" nil
      "gr" 'mail-app-refresh
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)))

;;; Emacspeak advice

(with-eval-after-load 'emacspeak
  (defadvice mail-app-list-accounts (after emacspeak pre act comp)
    "Speak when opening accounts list."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'open-object)
      (dtk-speak "Opened accounts list")))

  (defadvice mail-app-list-mailboxes (after emacspeak pre act comp)
    "Speak when opening mailboxes list."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'open-object)
      (dtk-speak "Opened mailboxes list")))

  (defadvice mail-app-list-messages (after emacspeak pre act comp)
    "Speak when opening messages list."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'open-object)
      (dtk-speak (format "Opened messages for %s" mail-app-current-mailbox))))

  (defadvice mail-app-view-message (after emacspeak pre act comp)
    "Speak when opening message view."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'open-object)
      (dtk-speak "Opened message view")))

  (defadvice mail-app-flag-message-at-point (after emacspeak pre act comp)
    "Speak when flagging a message."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'select-object)))

  (defadvice mail-app-delete-message-at-point (after emacspeak pre act comp)
    "Speak when deleting a message."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'delete-object)))

  (defadvice mail-app-archive-message-at-point (after emacspeak pre act comp)
    "Speak when archiving a message."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'select-object)))

  (defadvice mail-app-mark-message-at-point (after emacspeak pre act comp)
    "Speak when marking a message."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'select-object)))

  (defadvice mail-app-search (after emacspeak pre act comp)
    "Speak when opening search results."
    (when (called-interactively-p 'interactive)
      (emacspeak-icon 'open-object)
      (dtk-speak "Opened search results"))))

(provide 'mail-app)

;;; mail-app.el ends here

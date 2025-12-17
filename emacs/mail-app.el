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
(require 'json)

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

(defcustom mail-app-message-limit 20
  "Default number of messages to display."
  :type 'integer
  :group 'mail-app)

(defcustom mail-app-read-message-content nil
  "If non-nil, fetch and read message content in message lists.
This is helpful for screen reader users who want to hear message
content without opening each message. Set to nil by default as it
is slower and may be overwhelming for some users.

To enable by default, add to your init.el:
  (setq mail-app-read-message-content t)

You can also toggle it on-the-fly in message buffers with 'C' key."
  :type 'boolean
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
    (define-key map (kbd "S") 'mail-app-search-all)
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
    (define-key map (kbd "d") 'mail-app-delete-message-at-point)
    (define-key map (kbd "a") 'mail-app-archive-message-at-point)
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
    (define-key map (kbd "TAB") 'mail-app-cycle-view)
    (define-key map (kbd "<backtab>") 'mail-app-cycle-view-reverse)
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

(defvar-local mail-app-current-offset 0
  "Current pagination offset for messages.")

(defvar-local mail-app-current-view-mode 'plain
  "Current view mode for message: 'plain (content only), 'full (with headers), or 'attachments.")

(defvar-local mail-app-message-sort-key 'date
  "Current sort key for messages: 'date, 'subject, 'from, or 'read.")

(defvar-local mail-app-message-sort-reverse nil
  "If non-nil, reverse the sort order.")

;;; Utility functions

(defun mail-app--get-account-email (account-name)
  "Get the email address for ACCOUNT-NAME.
Returns the email address associated with the account, or the account name if not found."
  (condition-case err
      (let* ((output (mail-app--run-command "accounts" "list"))
             (accounts (mail-app--parse-accounts-output output))
             (account (seq-find (lambda (acc)
                                  (string= (plist-get acc :name) account-name))
                                accounts)))
        (if account
            (plist-get account :email)
          account-name))
    (error account-name)))

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
  "Parse accounts list OUTPUT (JSON) into a list of plists."
  (condition-case err
      (let* ((json-array (json-parse-string output :object-type 'alist :array-type 'list))
             (accounts '()))
        (dolist (acc json-array)
          (push (list :name (alist-get 'Name acc)
                      :email (alist-get 'EmailAddress acc)
                      :username (alist-get 'UserName acc)
                      :enabled (eq (alist-get 'Enabled acc) t))
                accounts))
        (nreverse accounts))
    (error
     (message "Failed to parse accounts JSON: %s\nOutput: %s" err output)
     nil)))

(defun mail-app--parse-mailboxes-output (output)
  "Parse mailboxes list OUTPUT (JSON) into a list of plists."
  (condition-case err
      (let* ((json-array (json-parse-string output :object-type 'alist :array-type 'list))
             (mailboxes '()))
        (dolist (mbox json-array)
          (push (list :account (alist-get 'Account mbox)
                      :name (alist-get 'Name mbox)
                      :unread (alist-get 'UnreadCount mbox)
                      :total (alist-get 'TotalCount mbox))
                mailboxes))
        (nreverse mailboxes))
    (error
     (message "Failed to parse mailboxes JSON: %s\nOutput: %s" err output)
     nil)))

(defun mail-app--parse-messages-output (output)
  "Parse messages list OUTPUT (JSON) into a list of plists."
  (condition-case err
      (let* ((json-array (json-parse-string output :object-type 'alist :array-type 'list))
             (messages '()))
        (dolist (msg json-array)
          (push (list :id (alist-get 'ID msg)
                      :read (eq (alist-get 'Read msg) t)
                      :flagged (eq (alist-get 'Flagged msg) t)
                      :from (alist-get 'Sender msg)
                      :subject (alist-get 'Subject msg)
                      :date (alist-get 'DateReceived msg)
                      :account (alist-get 'Account msg)
                      :mailbox (alist-get 'Mailbox msg)
                      :content (alist-get 'Content msg))
                messages))
        (nreverse messages))
    (error
     (message "Failed to parse messages JSON: %s\nOutput: %s" err output)
     nil)))

(defun mail-app--parse-search-output (output)
  "Parse search results OUTPUT (JSON) into a list of plists."
  (condition-case err
      (let* ((json-array (json-parse-string output :object-type 'alist :array-type 'list))
             (messages '()))
        (dolist (msg json-array)
          (push (list :id (alist-get 'ID msg)
                      :account (alist-get 'Account msg)
                      :mailbox (alist-get 'Mailbox msg)
                      :read (eq (alist-get 'Read msg) t)
                      :flagged (eq (alist-get 'Flagged msg) t)
                      :from (alist-get 'Sender msg)
                      :subject (alist-get 'Subject msg)
                      :date (alist-get 'DateReceived msg))
                messages))
        (nreverse messages))
    (error
     (message "Failed to parse search JSON: %s\nOutput: %s" err output)
     nil)))

(defun mail-app--get-account-at-point ()
  "Get the account data at point."
  (get-text-property (point) 'mail-app-account-data))

(defun mail-app--get-mailbox-at-point ()
  "Get the mailbox data at point."
  (get-text-property (point) 'mail-app-mailbox-data))

(defun mail-app--get-message-at-point ()
  "Get the message data at point."
  (get-text-property (point) 'mail-app-message-data))

(defun mail-app--get-attachment-at-point ()
  "Get the attachment data at point."
  (get-text-property (point) 'mail-app-attachment-data))

(defun mail-app--sort-messages (messages sort-key reverse)
  "Sort MESSAGES by SORT-KEY. Reverse if REVERSE is non-nil."
  (let ((sorted (sort (copy-sequence messages)
                     (lambda (a b)
                       (let ((val-a (pcase sort-key
                                     ('date (plist-get a :date))
                                     ('subject (downcase (or (plist-get a :subject) "")))
                                     ('from (downcase (or (plist-get a :from) "")))
                                     ('read (if (plist-get a :read) "1" "0"))
                                     (_ (plist-get a :date))))
                             (val-b (pcase sort-key
                                     ('date (plist-get b :date))
                                     ('subject (downcase (or (plist-get b :subject) "")))
                                     ('from (downcase (or (plist-get b :from) "")))
                                     ('read (if (plist-get b :read) "1" "0"))
                                     (_ (plist-get b :date)))))
                         (if (eq sort-key 'read)
                             (string< val-a val-b)
                           (string< (format "%s" val-a) (format "%s" val-b))))))))
    (if reverse (nreverse sorted) sorted)))

(defun mail-app--parse-attachments-output (output)
  "Parse attachments list OUTPUT (JSON) into a list of plists."
  (condition-case err
      (let* ((json-array (json-parse-string output :object-type 'alist :array-type 'list))
             (attachments '()))
        (dolist (att json-array)
          (push (list :name (alist-get 'Name att)
                      :size (alist-get 'FileSize att)
                      :mime-type (alist-get 'MimeType att))
                attachments))
        (nreverse attachments))
    (error
     (message "Failed to parse attachments JSON: %s\nOutput: %s" err output)
     nil)))

;;; Jump to Mail.app

(defun mail-app-jump-to-mail-app ()
  "Open Mail.app and jump to the current context (account, mailbox, or message)."
  (interactive)
  (cond
   ;; In message view - open the specific message
   ((and (eq major-mode 'mail-app-message-view-mode) mail-app-current-message-id)
    (mail-app--speak "Opening message in Mail.app" 'open-object)
    (let ((script (format "tell application \"Mail\"
  activate
  set targetAccount to account \"%s\"
  set targetMailbox to mailbox \"%s\" of targetAccount
  set msgs to messages of targetMailbox
  repeat with msg in msgs
    if id of msg as string is \"%s\" then
      set selected messages of message viewer 1 to {msg}
      open msg
      exit repeat
    end if
  end repeat
end tell"
                          (replace-regexp-in-string "\"" "\\\\\"" mail-app-current-account)
                          (replace-regexp-in-string "\"" "\\\\\"" mail-app-current-mailbox)
                          mail-app-current-message-id)))
      (call-process "osascript" nil nil nil "-e" script)
      (message "Opened message in Mail.app")))

   ;; In messages mode - open the mailbox
   ((and (eq major-mode 'mail-app-messages-mode) mail-app-current-mailbox)
    (mail-app--speak "Opening mailbox in Mail.app" 'open-object)
    (let ((script (format "tell application \"Mail\"
  activate
  set targetAccount to account \"%s\"
  set targetMailbox to mailbox \"%s\" of targetAccount
  set selected mailboxes of message viewer 1 to {targetMailbox}
end tell"
                          (replace-regexp-in-string "\"" "\\\\\"" mail-app-current-account)
                          (replace-regexp-in-string "\"" "\\\\\"" mail-app-current-mailbox))))
      (call-process "osascript" nil nil nil "-e" script)
      (message "Opened mailbox in Mail.app")))

   ;; In mailboxes mode - open mailbox at point or just the account
   ((eq major-mode 'mail-app-mailboxes-mode)
    (let ((mailbox (mail-app--get-mailbox-at-point)))
      (if mailbox
          (let ((account (plist-get mailbox :account))
                (name (plist-get mailbox :name)))
            (mail-app--speak "Opening mailbox in Mail.app" 'open-object)
            (let ((script (format "tell application \"Mail\"
  activate
  set targetAccount to account \"%s\"
  set targetMailbox to mailbox \"%s\" of targetAccount
  set selected mailboxes of message viewer 1 to {targetMailbox}
end tell"
                                  (replace-regexp-in-string "\"" "\\\\\"" account)
                                  (replace-regexp-in-string "\"" "\\\\\"" name))))
              (call-process "osascript" nil nil nil "-e" script)
              (message "Opened mailbox in Mail.app")))
        ;; No mailbox at point, just open Mail.app
        (mail-app--speak "Opening Mail.app" 'open-object)
        (call-process "osascript" nil nil nil "-e" "tell application \"Mail\" to activate")
        (message "Opened Mail.app"))))

   ;; In accounts mode or anywhere else - just open Mail.app
   (t
    (mail-app--speak "Opening Mail.app" 'open-object)
    (call-process "osascript" nil nil nil "-e" "tell application \"Mail\" to activate")
    (message "Opened Mail.app"))))

;;; Emacspeak integration

(defun mail-app--speak (text &optional icon)
  "Speak TEXT using Emacspeak.
Optionally play audio ICON."
  (when (featurep 'emacspeak)
    (when icon
      (emacspeak-icon icon))
    (dtk-speak text)))

(defun mail-app--emacspeak-speak-line ()
  "Custom Emacspeak line speaking for mail-app."
  (when (featurep 'emacspeak)
    (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
      (when speech-text
        (dtk-speak speech-text)))))

(defun mail-app--emacspeak-post-command ()
  "Emacspeak post-command hook for mail-app modes."
  (when (and (featurep 'emacspeak)
             (memq this-command '(next-line previous-line evil-next-line evil-previous-line
                                  mail-app-toggle-mark-at-point mail-app-toggle-mark-backward)))
    (mail-app--emacspeak-speak-line)))

;;; Display functions

(defun mail-app--format-accounts (accounts)
  "Format ACCOUNTS for display."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "Mail.app Accounts\n" 'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] mailboxes  [c] compose  [s] search  [S] search all\n")
    (insert "          [J] jump to Mail.app  [g/r] refresh  [q] quit  [?] help\n\n")
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
    (forward-line 6)))  ; Skip title, blank, commands (2 lines), blank, header

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
    (insert "Commands: [RET] messages  [c] compose  [s] search  [S] search all\n")
    (insert "          [J] jump to Mail.app  [g/r] refresh  [q] quit  [?] help\n\n")
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
    (forward-line 6)))  ; Skip title, blank, commands (2 lines), blank, header

(defun mail-app--format-messages (messages)
  "Format MESSAGES for display."
  (let* ((inhibit-read-only t)
         ;; Check if these are search results - simpler: just check if current mailbox is a search
         (is-search (and mail-app-current-mailbox
                        (string-match-p "^Search:" mail-app-current-mailbox)))
         ;; Sort messages
         (sorted-messages (mail-app--sort-messages messages
                                                   mail-app-message-sort-key
                                                   mail-app-message-sort-reverse))
         (sort-indicator (format " [%s%s]"
                                (pcase mail-app-message-sort-key
                                  ('date "date")
                                  ('subject "subject")
                                  ('from "from")
                                  ('read "unread"))
                                (if mail-app-message-sort-reverse " ↓" " ↑"))))
    (erase-buffer)
    (insert (propertize (format "Mail.app Messages: %s/%s%s\n"
                                (or mail-app-current-account "Search Results")
                                (or mail-app-current-mailbox "All")
                                sort-indicator)
                        'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] read  [c] compose  [f] flag  [d] delete  [a] archive\n")
    (insert "          [t] toggle read  [C] toggle content  [o] sort  [u] unread\n")
    (insert "          [s] search  [S] search all  [J] jump  [N] more  [g/r] refresh\n")
    (insert "Marking:  [m] mark  [M] unmark  [U] unmark-all  [x] delete marked\n")
    (insert "          [,a] archive  [,f] flag  [,r] read  [,u] unread  [?] help\n\n")
    (if is-search
        ;; Search results: show ACCOUNT and MAILBOX columns
        (progn
          (insert (format "%-2s %-20s %-15s %-40s %-30s\n"
                          "" "ACCOUNT" "MAILBOX" "SUBJECT" "FROM"))
          (insert (make-string 110 ?-) "\n")
          (dolist (message sorted-messages)
            (let* ((id (plist-get message :id))
                   (account (plist-get message :account))
                   (mailbox (plist-get message :mailbox))
                   (from (plist-get message :from))
                   (subject (plist-get message :subject))
                   (content (plist-get message :content))
                   (read (plist-get message :read))
                   (marked (member id mail-app-marked-messages))
                   (mark-str (if marked ">" " "))
                   (line (format "%-2s %-20s %-15s %-40s %-30s\n"
                                 mark-str
                                 (truncate-string-to-width account 20 nil nil "...")
                                 (truncate-string-to-width mailbox 15 nil nil "...")
                                 (truncate-string-to-width subject 40 nil nil "...")
                                 (truncate-string-to-width from 30 nil nil "...")))
                   (speech-text (if (and content (not (string-empty-p content)))
                                   (format "%s%s from %s in %s %s. Message content: %s"
                                          (if marked "Marked. " "")
                                          subject from account mailbox
                                          (truncate-string-to-width content 300 nil nil "..."))
                                 (format "%s%s from %s in %s %s"
                                        (if marked "Marked. " "")
                                        subject from account mailbox)))
                   (start (point)))
              (insert line)
              (let ((line-end (1- (point))))  ; Exclude the newline
                (put-text-property start line-end 'mail-app-message-data message)
                (put-text-property start line-end 'emacspeak-speak speech-text)
                ;; Make the mark indicator audibly invisible to Emacspeak
                (when marked
                  (put-text-property start (1+ start) 'auditory-icon nil))
                (cond
                 (marked
                  (put-text-property start line-end 'face 'highlight))
                 ((not read)
                  (put-text-property start line-end 'face 'bold))))))))
      ;; Regular message list: show SUBJECT and FROM only (no redundant account/mailbox)
      (progn
        (insert (format "%-2s %-4s %-60s %-40s\n"
                        "" "FLAG" "SUBJECT" "FROM"))
        (insert (make-string 110 ?-) "\n")
        (dolist (message sorted-messages)
          (let* ((id (plist-get message :id))
                 (read (plist-get message :read))
                 (flagged (plist-get message :flagged))
                 (from (plist-get message :from))
                 (subject (plist-get message :subject))
                 (content (plist-get message :content))
                 (marked (member id mail-app-marked-messages))
                 (mark-str (if marked ">" " "))
                 (flag-str (concat (if read "✓" " ") (if flagged "⚑" " ")))
                 (line (format "%-2s %-4s %-60s %-40s\n"
                               mark-str
                               flag-str
                               (truncate-string-to-width subject 60 nil nil "...")
                               (truncate-string-to-width from 40 nil nil "...")))
                 (speech-text (if (and content (not (string-empty-p content)))
                                 (format "%s%s%s from %s. Message content: %s"
                                        (if marked "Marked. " "")
                                        (if flagged "Flagged. " "")
                                        subject from
                                        (truncate-string-to-width content 300 nil nil "..."))
                               (format "%s%s%s from %s"
                                      (if marked "Marked. " "")
                                      (if flagged "Flagged. " "")
                                      subject from)))
                 (start (point)))
            (insert line)
            (let ((line-end (1- (point))))  ; Exclude the newline
              (put-text-property start line-end 'mail-app-message-data message)
              (put-text-property start line-end 'emacspeak-speak speech-text)
              ;; Make the mark indicator audibly invisible to Emacspeak
              (when marked
                (put-text-property start (1+ start) 'auditory-icon nil))
              (cond
               (marked
                (put-text-property start line-end 'face 'highlight))
               ((not read)
                (put-text-property start line-end 'face 'bold))))))))
    (goto-char (point-min))
    (forward-line 9))  ; Skip title, blank, command lines (5), blank, header

(defun mail-app--format-message-view (message-id account mailbox)
  "Format message view for MESSAGE-ID in ACCOUNT and MAILBOX based on view mode."
  (let* ((output (mail-app--run-command "messages" "show" message-id
                                         "-a" account "-m" mailbox))
         (inhibit-read-only t)
         (view-mode (or mail-app-current-view-mode 'plain))
         (details (mail-app--parse-message-details output)))
    (erase-buffer)
    (insert (propertize (format "Mail.app Message [%s view]: %s/%s\n"
                                (symbol-name view-mode) account mailbox)
                        'face 'bold))
    (insert "\n")
    (insert "Commands: [r] reply  [R] reply-all  [TAB] cycle view  [S-TAB] cycle reverse\n")
    (insert "          [f] flag  [d] delete  [a] archive  [t] unread  [c] compose\n")
    (insert "          [J] jump to Mail.app  [g] refresh  [q] quit  [?] help\n\n")
    (insert (make-string 80 ?=) "\n\n")
    (cond
     ((eq view-mode 'plain)
      ;; Show basic headers and content
      (when-let* ((from (plist-get details :from)))
        (insert (propertize "From: " 'face 'bold) from "\n"))
      (when-let* ((to (plist-get details :to)))
        (insert (propertize "To: " 'face 'bold) to "\n"))
      (when-let* ((subject (plist-get details :subject)))
        (insert (propertize "Subject: " 'face 'bold) subject "\n"))
      (when-let* ((date (plist-get details :date-received)))
        (insert (propertize "Date: " 'face 'bold) date "\n"))
      (insert "\n")
      (when-let* ((content (plist-get details :content)))
        (insert content)))
     ((eq view-mode 'full)
      ;; Show all headers plus content
      (when-let* ((subject (plist-get details :subject)))
        (insert (propertize "Subject: " 'face 'bold) subject "\n"))
      (when-let* ((from (plist-get details :from)))
        (insert (propertize "From: " 'face 'bold) from "\n"))
      (when-let* ((to (plist-get details :to)))
        (insert (propertize "To: " 'face 'bold) to "\n"))
      (when-let* ((cc (plist-get details :cc)))
        (insert (propertize "Cc: " 'face 'bold) cc "\n"))
      (when-let* ((date-sent (plist-get details :date-sent)))
        (insert (propertize "Date Sent: " 'face 'bold) date-sent "\n"))
      (when-let* ((date-recv (plist-get details :date-received)))
        (insert (propertize "Date Received: " 'face 'bold) date-recv "\n"))
      (insert (propertize "Read: " 'face 'bold) (if (plist-get details :read) "yes" "no") "\n")
      (insert (propertize "Flagged: " 'face 'bold) (if (plist-get details :flagged) "yes" "no") "\n")
      (when-let* ((size (plist-get details :size)))
        (insert (propertize "Size: " 'face 'bold) (format "%d bytes" size) "\n"))
      (insert "\n")
      (when-let* ((content (plist-get details :content)))
        (insert content)))
     ((eq view-mode 'attachments)
      ;; Show attachment list
      (let* ((attach-output (mail-app--run-command "attachments" "list" message-id
                                                    "-a" account "-m" mailbox))
             (attachments (mail-app--parse-attachments-output attach-output)))
        (if (null attachments)
            (insert "No attachments found.\n")
          (insert (propertize "Attachments\n\n" 'face 'bold))
          (insert "Commands: [RET/s] save  [q] quit\n\n")
          (insert (format "%-40s %-12s %-30s\n" "NAME" "SIZE" "TYPE"))
          (insert (make-string 80 ?-) "\n")
          (dolist (attachment attachments)
            (let* ((name (plist-get attachment :name))
                   (size (plist-get attachment :size))
                   (mime-type (plist-get attachment :mime-type))
                   (line (format "%-40s %-12d %-30s\n" name size mime-type))
                   (speech-text (format "%s, %d bytes, %s" name size mime-type)))
              (insert (propertize line
                                  'mail-app-attachment-data attachment
                                  'emacspeak-speak speech-text))))))))
    (goto-char (point-min))
    (forward-line 7)))

;;; Interactive commands - Accounts

;;;###autoload
(defun mail-app-list-accounts (&optional force-refresh)
  "List all Mail.app accounts.
With optional FORCE-REFRESH, bypass cache and fetch fresh data."
  (interactive "P")
  (let ((buf (get-buffer-create "*Mail.app Accounts*")))
    (with-current-buffer buf
      (mail-app-accounts-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Loading accounts...\n")))
    (switch-to-buffer buf)
    (mail-app--speak "Loading accounts" 'select-object)
    (let ((args (list "accounts" "list")))
      (when force-refresh
        (setq args (append args '("--force-refresh"))))
      (apply 'mail-app--run-command-async
             (lambda (output)
               (let ((accounts (mail-app--parse-accounts-output output)))
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (setq mail-app-accounts-data accounts)
                     (mail-app--format-accounts accounts)
                     (mail-app--speak (format "Loaded %d accounts" (length accounts)) 'task-done)))))
             args))))

(defun mail-app-view-mailboxes-at-point ()
  "View mailboxes for the account at point."
  (interactive)
  (let ((account (mail-app--get-account-at-point)))
    (if (not account)
        (message "No account at point")
      (let ((name (plist-get account :name)))
        (mail-app-list-mailboxes-for-account name)))))

;;; Interactive commands - Mailboxes

(defun mail-app-list-mailboxes-for-account (account &optional force-refresh)
  "List mailboxes for ACCOUNT.
With optional FORCE-REFRESH, bypass cache and fetch fresh data."
  (interactive
   (list (read-string "Account: " mail-app-default-account)
         current-prefix-arg))
  (let ((buf (get-buffer-create (format "*Mail.app Mailboxes: %s*" account))))
    (with-current-buffer buf
      (mail-app-mailboxes-mode)
      (setq mail-app-current-account account)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Loading mailboxes for %s...\n" account))))
    (switch-to-buffer buf)
    (mail-app--speak (format "Loading mailboxes for %s" account) 'select-object)
    (let ((args (list "mailboxes" "list" "-a" account)))
      (when force-refresh
        (setq args (append args '("--force-refresh"))))
      (apply 'mail-app--run-command-async
             (lambda (output)
               (let ((mailboxes (mail-app--parse-mailboxes-output output)))
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (setq mail-app-mailboxes-data mailboxes)
                     (mail-app--format-mailboxes mailboxes)
                     (mail-app--speak (format "Loaded %d mailboxes" (length mailboxes)) 'task-done)))))
             args))))

;;;###autoload
(defun mail-app-list-mailboxes (&optional force-refresh)
  "List all Mail.app mailboxes.
With optional FORCE-REFRESH, bypass cache and fetch fresh data."
  (interactive "P")
  (let ((buf (get-buffer-create "*Mail.app Mailboxes*")))
    (with-current-buffer buf
      (mail-app-mailboxes-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Loading all mailboxes...\n")))
    (switch-to-buffer buf)
    (mail-app--speak "Loading all mailboxes" 'select-object)
    (let ((args (list "mailboxes" "list")))
      (when force-refresh
        (setq args (append args '("--force-refresh"))))
      (apply 'mail-app--run-command-async
             (lambda (output)
               (let ((mailboxes (mail-app--parse-mailboxes-output output)))
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (setq mail-app-mailboxes-data mailboxes)
                     (mail-app--format-mailboxes mailboxes)
                     (mail-app--speak (format "Loaded %d mailboxes" (length mailboxes)) 'task-done)))))
             args))))

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
  "Refresh the current view (with cache refresh)."
  (interactive)
  (mail-app--speak "Refreshing" 'select-object)
  (cond
   ((eq major-mode 'mail-app-accounts-mode)
    (mail-app-list-accounts t))
   ((eq major-mode 'mail-app-mailboxes-mode)
    (if mail-app-current-account
        (mail-app-list-mailboxes-for-account mail-app-current-account t)
      (mail-app-list-mailboxes t)))
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
  (mail-app--speak (format "Loading messages from %s" mailbox) 'select-object)
  (let* ((args (list "messages" "list" "-a" account "-m" mailbox
                     "-l" (number-to-string mail-app-message-limit)
                     "-o" "0"))
         (args (if mail-app-read-message-content
                   (append args '("--with-content"))
                 args))
         (args (if mail-app-show-only-unread
                   (append args '("-u"))
                 args))
         (buf (get-buffer-create (format "*Mail.app Messages: %s/%s*" account mailbox))))
    ;; Setup buffer immediately with loading message
    (with-current-buffer buf
      (mail-app-messages-mode)
      (setq mail-app-current-account account)
      (setq mail-app-current-mailbox mailbox)
      (setq mail-app-current-offset 0)
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
                   (mail-app--speak (format "Loaded %d messages" (length messages)) 'task-done)))))
           args)))

(defun mail-app-load-more-messages ()
  "Load next page of messages and append to current list."
  (interactive)
  (unless (and mail-app-current-account mail-app-current-mailbox)
    (error "No mailbox context"))
  (let ((new-offset (+ mail-app-current-offset mail-app-message-limit)))
    (mail-app--speak (format "Loading more messages, offset %d" new-offset) 'select-object)
    (let* ((args (list "messages" "list"
                       "-a" mail-app-current-account
                       "-m" mail-app-current-mailbox
                       "-l" (number-to-string mail-app-message-limit)
                       "-o" (number-to-string new-offset)))
           (args (if mail-app-read-message-content
                     (append args '("--with-content"))
                   args))
           (args (if mail-app-show-only-unread
                     (append args '("-u"))
                   args))
           (buf (current-buffer)))
      (apply 'mail-app--run-command-async
             (lambda (output)
               (let ((new-messages (mail-app--parse-messages-output output)))
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (if (null new-messages)
                         (mail-app--speak "No more messages" 'warn-user)
                       (setq mail-app-current-offset new-offset)
                       (setq mail-app-messages-data (append mail-app-messages-data new-messages))
                       (mail-app--format-messages mail-app-messages-data)
                       (mail-app--speak (format "Loaded %d more messages, total %d"
                                                (length new-messages)
                                                (length mail-app-messages-data))
                                        'task-done))))))
             args))))

(defun mail-app-view-message-at-point ()
  "View the full message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let* ((id (plist-get message :id))
             ;; For search results, use account/mailbox from message data
             (account (or (plist-get message :account) mail-app-current-account))
             (mailbox (or (plist-get message :mailbox) mail-app-current-mailbox)))
        (mail-app-view-message id account mailbox)))))

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
      (setq mail-app-current-view-mode 'plain)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Loading message...\n")))
    (switch-to-buffer buf)
    (mail-app--speak "Loading message" 'select-object)
    (mail-app--run-command-async
     (lambda (output)
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (let ((inhibit-read-only t)
                 (view-mode (or mail-app-current-view-mode 'plain))
                 (details (mail-app--parse-message-details output)))
             (erase-buffer)
             (insert (propertize (format "Mail.app Message [%s view]: %s/%s\n"
                                        (symbol-name view-mode) account mailbox)
                                'face 'bold))
             (insert "\n")
             (insert "Commands: [r] reply  [R] reply-all  [TAB] cycle view  [S-TAB] cycle reverse\n")
             (insert "          [f] flag  [d] delete  [a] archive  [t] unread  [c] compose\n")
             (insert "          [J] jump to Mail.app  [g] refresh  [q] quit  [?] help\n\n")
             (insert (make-string 80 ?=) "\n\n")
             (cond
              ((eq view-mode 'plain)
               (when-let* ((from (plist-get details :from)))
                 (insert (propertize "From: " 'face 'bold) from "\n"))
               (when-let* ((to (plist-get details :to)))
                 (insert (propertize "To: " 'face 'bold) to "\n"))
               (when-let* ((subject (plist-get details :subject)))
                 (insert (propertize "Subject: " 'face 'bold) subject "\n"))
               (when-let* ((date (plist-get details :date-received)))
                 (insert (propertize "Date: " 'face 'bold) date "\n"))
               (insert "\n")
               (when-let* ((content (plist-get details :content)))
                 (insert content)))
              ((eq view-mode 'full)
               (when-let* ((subject (plist-get details :subject)))
                 (insert (propertize "Subject: " 'face 'bold) subject "\n"))
               (when-let* ((from (plist-get details :from)))
                 (insert (propertize "From: " 'face 'bold) from "\n"))
               (when-let* ((to (plist-get details :to)))
                 (insert (propertize "To: " 'face 'bold) to "\n"))
               (when-let* ((cc (plist-get details :cc)))
                 (insert (propertize "Cc: " 'face 'bold) cc "\n"))
               (when-let* ((date-sent (plist-get details :date-sent)))
                 (insert (propertize "Date Sent: " 'face 'bold) date-sent "\n"))
               (when-let* ((date-recv (plist-get details :date-received)))
                 (insert (propertize "Date Received: " 'face 'bold) date-recv "\n"))
               (insert (propertize "Read: " 'face 'bold) (if (plist-get details :read) "yes" "no") "\n")
               (insert (propertize "Flagged: " 'face 'bold) (if (plist-get details :flagged) "yes" "no") "\n")
               (when-let* ((size (plist-get details :size)))
                 (insert (propertize "Size: " 'face 'bold) (format "%d bytes" size) "\n"))
               (insert "\n")
               (when-let* ((content (plist-get details :content)))
                 (insert content)))
              ((eq view-mode 'attachments)
               (insert "Loading attachments...\n")))
             (goto-char (point-min))
             (forward-line 7)
             (mail-app--speak "Message loaded" 'task-done)))))
     "messages" "show" message-id "-a" account "-m" mailbox)))

(defun mail-app-cycle-view ()
  "Cycle through message view modes: plain, attachments, full."
  (interactive)
  (unless mail-app-current-message-id
    (error "No message loaded"))
  (let* ((current (or mail-app-current-view-mode 'plain))
         (next (cond
                ((eq current 'plain) 'attachments)
                ((eq current 'attachments) 'full)
                ((eq current 'full) 'plain)
                (t 'plain)))
         (buf (current-buffer)))
    (setq mail-app-current-view-mode next)
    (mail-app--speak (format "Switching to %s view" (symbol-name next)) 'select-object)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Loading %s view...\n" (symbol-name next))))
    (if (eq next 'attachments)
        ;; Load attachments
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (let* ((inhibit-read-only t)
                      (attachments (mail-app--parse-attachments-output output)))
                 (erase-buffer)
                 (insert (propertize (format "Mail.app Message [attachments view]: %s/%s\n"
                                            mail-app-current-account mail-app-current-mailbox)
                                    'face 'bold))
                 (insert "\n")
                 (insert "Commands: [r] reply  [R] reply-all  [TAB] cycle view  [S-TAB] cycle reverse\n")
                 (insert "          [f] flag  [d] delete  [a] archive  [t] unread  [c] compose\n")
                 (insert "          [J] jump to Mail.app  [g] refresh  [q] quit  [?] help\n\n")
                 (insert (make-string 80 ?=) "\n\n")
                 (if (null attachments)
                     (insert "No attachments found.\n")
                   (insert (propertize "Attachments\n\n" 'face 'bold))
                   (insert "Commands: [RET/s] save  [q] quit\n\n")
                   (insert (format "%-40s %-12s %-30s\n" "NAME" "SIZE" "TYPE"))
                   (insert (make-string 80 ?-) "\n")
                   (dolist (attachment attachments)
                     (let* ((name (plist-get attachment :name))
                            (size (plist-get attachment :size))
                            (mime-type (plist-get attachment :mime-type))
                            (line (format "%-40s %-12d %-30s\n" name size mime-type))
                            (speech-text (format "%s, %d bytes, %s" name size mime-type)))
                       (insert (propertize line
                                          'mail-app-attachment-data attachment
                                          'emacspeak-speak speech-text)))))
                 (goto-char (point-min))
                 (forward-line 7)
                 (mail-app--speak "Attachments view loaded" 'task-done)))))
         "attachments" "list" mail-app-current-message-id
         "-a" mail-app-current-account "-m" mail-app-current-mailbox)
      ;; Load plain or full view
      (mail-app--run-command-async
       (lambda (output)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (let ((inhibit-read-only t)
                   (details (mail-app--parse-message-details output)))
               (erase-buffer)
               (insert (propertize (format "Mail.app Message [%s view]: %s/%s\n"
                                          (symbol-name next) mail-app-current-account mail-app-current-mailbox)
                                  'face 'bold))
               (insert "\n")
               (insert "Commands: [r] reply  [R] reply-all  [TAB] cycle view  [S-TAB] cycle reverse\n")
               (insert "          [f] flag  [d] delete  [a] archive  [t] unread  [c] compose\n")
               (insert "          [J] jump to Mail.app  [g] refresh  [q] quit  [?] help\n\n")
               (insert (make-string 80 ?=) "\n\n")
               (cond
                ((eq next 'plain)
                 (when-let* ((from (plist-get details :from)))
                   (insert (propertize "From: " 'face 'bold) from "\n"))
                 (when-let* ((to (plist-get details :to)))
                   (insert (propertize "To: " 'face 'bold) to "\n"))
                 (when-let* ((subject (plist-get details :subject)))
                   (insert (propertize "Subject: " 'face 'bold) subject "\n"))
                 (when-let* ((date (plist-get details :date-received)))
                   (insert (propertize "Date: " 'face 'bold) date "\n"))
                 (insert "\n")
                 (when-let* ((content (plist-get details :content)))
                   (insert content)))
                ((eq next 'full)
                 (when-let* ((subject (plist-get details :subject)))
                   (insert (propertize "Subject: " 'face 'bold) subject "\n"))
                 (when-let* ((from (plist-get details :from)))
                   (insert (propertize "From: " 'face 'bold) from "\n"))
                 (when-let* ((to (plist-get details :to)))
                   (insert (propertize "To: " 'face 'bold) to "\n"))
                 (when-let* ((cc (plist-get details :cc)))
                   (insert (propertize "Cc: " 'face 'bold) cc "\n"))
                 (when-let* ((date-sent (plist-get details :date-sent)))
                   (insert (propertize "Date Sent: " 'face 'bold) date-sent "\n"))
                 (when-let* ((date-recv (plist-get details :date-received)))
                   (insert (propertize "Date Received: " 'face 'bold) date-recv "\n"))
                 (insert (propertize "Read: " 'face 'bold) (if (plist-get details :read) "yes" "no") "\n")
                 (insert (propertize "Flagged: " 'face 'bold) (if (plist-get details :flagged) "yes" "no") "\n")
                 (when-let* ((size (plist-get details :size)))
                   (insert (propertize "Size: " 'face 'bold) (format "%d bytes" size) "\n"))
                 (insert "\n")
                 (when-let* ((content (plist-get details :content)))
                   (insert content))))
               (goto-char (point-min))
               (forward-line 7)
               (mail-app--speak (format "%s view loaded" (symbol-name next)) 'task-done)))))
       "messages" "show" mail-app-current-message-id
       "-a" mail-app-current-account "-m" mail-app-current-mailbox))))

(defun mail-app-cycle-view-reverse ()
  "Cycle through message view modes in reverse: plain, full, attachments."
  (interactive)
  (unless mail-app-current-message-id
    (error "No message loaded"))
  (let* ((current (or mail-app-current-view-mode 'plain))
         (next (cond
                ((eq current 'plain) 'full)
                ((eq current 'full) 'attachments)
                ((eq current 'attachments) 'plain)
                (t 'plain))))
    (setq mail-app-current-view-mode next)
    ;; Reuse the cycle-view logic
    (mail-app-cycle-view)))

(defun mail-app-show-unread ()
  "Toggle showing only unread messages."
  (interactive)
  (setq mail-app-show-only-unread (not mail-app-show-only-unread))
  (message "Showing %s messages" (if mail-app-show-only-unread "unread" "all"))
  (mail-app-refresh))

(defun mail-app-toggle-read-content ()
  "Toggle reading message content in message lists.
When enabled, Emacspeak will read the first 300 characters of each
message as you navigate, allowing you to triage email without opening
each message. When disabled, only subject and sender are read."
  (interactive)
  (setq mail-app-read-message-content (not mail-app-read-message-content))
  (let ((status (if mail-app-read-message-content "enabled" "disabled")))
    (message "Message content reading %s" status)
    (mail-app--speak (format "Message content reading %s. Refresh to apply." status) 'select-object)))

(defun mail-app-sort-messages ()
  "Cycle through message sort options: date, subject, from, unread."
  (interactive)
  (unless mail-app-messages-data
    (error "No messages to sort"))
  (let* ((current mail-app-message-sort-key)
         (next (pcase current
                 ('date 'subject)
                 ('subject 'from)
                 ('from 'read)
                 ('read 'date)
                 (_ 'date))))
    (setq mail-app-message-sort-key next)
    (setq mail-app-message-sort-reverse nil)
    (mail-app--format-messages mail-app-messages-data)
    (mail-app--speak (format "Sorted by %s" (symbol-name next)) 'select-object)))

(defun mail-app-reverse-sort ()
  "Reverse the current sort order."
  (interactive)
  (unless mail-app-messages-data
    (error "No messages to sort"))
  (setq mail-app-message-sort-reverse (not mail-app-message-sort-reverse))
  (mail-app--format-messages mail-app-messages-data)
  (mail-app--speak (format "Sort %s" (if mail-app-message-sort-reverse "reversed" "normal")) 'select-object))

;;; Interactive commands - Message actions

(defun mail-app-flag-message-at-point ()
  "Toggle flag on message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let* ((id (plist-get message :id))
             (flagged (plist-get message :flagged))
             (new-state (not flagged))
             (buf (current-buffer)))
        (mail-app--speak (if new-state "Flagging message" "Unflagging message") 'select-object)
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (mail-app--speak (if new-state "Flagged" "Unflagged") 'task-done)
               (mail-app-refresh))))
         "messages" "flag" id
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox
         "--flagged" (if new-state "true" "false"))))))

(defun mail-app-delete-message-at-point ()
  "Delete message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (when (yes-or-no-p "Delete this message? ")
        (mail-app--speak "Deleting message" 'delete-object)
        (let ((id (plist-get message :id))
              (buf (current-buffer)))
          (mail-app--run-command-async
           (lambda (output)
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (mail-app--speak "Deleted" 'task-done)
                 (mail-app-refresh))))
           "messages" "delete" id
           "-a" mail-app-current-account
           "-m" mail-app-current-mailbox))))))

(defun mail-app-archive-message-at-point ()
  "Archive message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (mail-app--speak "Archiving message" 'select-object)
      (let ((id (plist-get message :id))
            (buf (current-buffer)))
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (mail-app--speak "Archived" 'task-done)
               (mail-app-refresh))))
         "messages" "archive" id
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox)))))

(defun mail-app-mark-message-at-point ()
  "Toggle read status of message at point."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (let* ((id (plist-get message :id))
             (read (plist-get message :read))
             (new-state (not read))
             (buf (current-buffer)))
        (mail-app--speak (format "Marking as %s" (if new-state "read" "unread")) 'select-object)
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (mail-app--speak (format "Marked as %s" (if new-state "read" "unread")) 'task-done)
               (mail-app-refresh))))
         "messages" "mark" id
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox
         "--read" (if new-state "true" "false"))))))

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

(defun mail-app-save-attachment-at-point ()
  "Save attachment at point to Downloads folder."
  (interactive)
  (let ((attachment (mail-app--get-attachment-at-point)))
    (if (not attachment)
        (message "No attachment at point")
      (unless mail-app-current-message-id
        (error "No message context available"))
      (unless mail-app-current-account
        (error "No account context available"))
      (unless mail-app-current-mailbox
        (error "No mailbox context available"))
      (let* ((name (plist-get attachment :name))
             (output-path (expand-file-name
                          (read-file-name "Save attachment to: " "~/Downloads/" nil nil name))))
        (mail-app--speak (format "Saving %s" name) 'select-object)
        (mail-app--run-command-async
         (lambda (output)
           (if (string-match-p "error\\|Error\\|failed" output)
               (progn
                 (message "Failed to save attachment: %s" output)
                 (mail-app--speak "Save failed" 'warn-user))
             (message "Saved attachment to: %s" output-path)
             (mail-app--speak (format "Saved %s" name) 'task-done)))
         "attachments" "save" mail-app-current-message-id name
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox
         "-o" output-path)))))

(defun mail-app--parse-message-details (output)
  "Parse message details from OUTPUT (JSON) and return plist."
  (condition-case err
      (let* ((json-obj (json-parse-string output :object-type 'alist :array-type 'list))
             (to-recipients (alist-get 'ToRecipients json-obj))
             (cc-recipients (alist-get 'CcRecipients json-obj)))
        (list :subject (alist-get 'Subject json-obj)
              :from (alist-get 'Sender json-obj)
              :to (when to-recipients (string-join (append to-recipients nil) ", "))
              :cc (when cc-recipients (string-join (append cc-recipients nil) ", "))
              :date-sent (alist-get 'DateSent json-obj)
              :date-received (alist-get 'DateReceived json-obj)
              :content (alist-get 'Content json-obj)
              :read (eq (alist-get 'Read json-obj) t)
              :flagged (eq (alist-get 'Flagged json-obj) t)
              :size (alist-get 'MessageSize json-obj)))
    (error
     (message "Failed to parse message details JSON: %s" err)
     nil)))

(defun mail-app-reply-current-message ()
  "Reply to current message."
  (interactive)
  (when mail-app-current-message-id
    (let* ((output (mail-app--run-command "messages" "show" mail-app-current-message-id
                                          "-a" mail-app-current-account
                                          "-m" mail-app-current-mailbox))
           (details (mail-app--parse-message-details output))
           (from (plist-get details :from))
           (subject (plist-get details :subject))
           (body (plist-get details :content))
           (reply-subject (if (string-prefix-p "Re: " subject)
                              subject
                            (concat "Re: " subject)))
           (from-email (mail-app--get-account-email mail-app-current-account)))
      (compose-mail from reply-subject)
      ;; Now we're in the message buffer - set message-options here
      (setq-local message-options `((account . ,mail-app-current-account)))
      ;; Override send function to use mail-app-cli
      (setq-local message-send-mail-function 'mail-app--message-send-mail)
      ;; Set From header based on account email
      (message-goto-from)
      (beginning-of-line)
      (kill-line)
      (insert (format "From: %s" from-email))
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
           (details (mail-app--parse-message-details output))
           (from (plist-get details :from))
           (to (plist-get details :to))
           (cc (plist-get details :cc))
           (subject (plist-get details :subject))
           (body (plist-get details :content))
           (reply-subject (if (string-prefix-p "Re: " subject)
                              subject
                            (concat "Re: " subject)))
           (all-recipients (string-join (delq nil (list from to cc)) ", "))
           (from-email (mail-app--get-account-email mail-app-current-account)))
      (compose-mail all-recipients reply-subject)
      ;; Now we're in the message buffer - set message-options here
      (setq-local message-options `((account . ,mail-app-current-account)))
      ;; Override send function to use mail-app-cli
      (setq-local message-send-mail-function 'mail-app--message-send-mail)
      ;; Set From header based on account email
      (message-goto-from)
      (beginning-of-line)
      (kill-line)
      (insert (format "From: %s" from-email))
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
           ;; Extract attachments from MML tags
           (attachments '())
           (body-start (save-excursion
                         (goto-char (point-min))
                         (search-forward mail-header-separator nil t)
                         (forward-line 1)
                         (point)))
           (body-text (buffer-substring-no-properties body-start (point-max))))
      ;; Find MML attachment tags
      (goto-char body-start)
      (while (re-search-forward "<#part[^>]+filename=\"\\([^\"]+\\)\"[^>]*disposition=attachment" nil t)
        (let ((filename (match-string 1)))
          (push (expand-file-name filename) attachments)))
      ;; Remove MML tags from body for plain text sending
      (setq body-text (replace-regexp-in-string "<#/?part[^>]*>" "" body-text))
      (setq body-text (string-trim body-text))

      (unless to
        (error "No recipients specified"))
      (unless subject
        (error "No subject specified"))
      (unless account
        (error "No account specified"))
      (let ((args (list "send" "-a" account "-s" subject "--body" body-text)))
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
        ;; Add attachments if present
        (dolist (attachment (nreverse attachments))
          (setq args (append args (list "--attach" attachment))))
        (apply 'mail-app--run-command args)
        (if (> (length attachments) 0)
            (message "Message sent via %s with %d attachment(s)" account (length attachments))
          (message "Message sent via %s" account))
        (kill-buffer)))))

;; Custom send function for message-mode
(defun mail-app--message-send-mail ()
  "Send mail using mail-app-cli instead of default sendmail."
  (mail-app-send-message))

;;;###autoload
(defun mail-app-compose ()
  "Compose a new email message."
  (interactive)
  (let* ((accounts-output (mail-app--run-command "accounts" "list"))
         (accounts (mail-app--parse-accounts-output accounts-output))
         (account-names (mapcar (lambda (acc) (plist-get acc :name)) accounts))
         (account (if (and mail-app-current-account (not current-prefix-arg))
                      mail-app-current-account
                    (completing-read "Account: " account-names nil t
                                   (or mail-app-current-account mail-app-default-account))))
         (from-email (mail-app--get-account-email account)))
    ;; Open compose buffer
    (compose-mail)
    ;; Now we're in the message buffer - set message-options here
    (setq-local message-options `((account . ,account)))
    ;; Override send function to use mail-app-cli
    (setq-local message-send-mail-function 'mail-app--message-send-mail)
    ;; Set From header based on account email
    (message-goto-from)
    (beginning-of-line)
    (kill-line)
    (insert (format "From: %s" from-email))
    (message-goto-to)
    (message "Composing new message...")))

;;; Marking and bulk operations

(defun mail-app--update-speech-text-for-line (message marked)
  "Update the emacspeak-speak property for the current line based on MESSAGE and MARKED status."
  (let* ((flagged (plist-get message :flagged))
         (subject (plist-get message :subject))
         (from (plist-get message :from))
         (content (plist-get message :content))
         (is-search (and mail-app-current-mailbox
                        (string-match-p "^Search:" mail-app-current-mailbox)))
         (line-end (line-end-position))
         (speech-text (if is-search
                         ;; Search results - include account/mailbox
                         (let ((account (plist-get message :account))
                               (mailbox (plist-get message :mailbox)))
                           (if (and content (not (string-empty-p content)) mail-app-read-message-content)
                               (format "%s%s from %s in %s %s. Message content: %s"
                                      (if marked "Marked. " "")
                                      subject from account mailbox
                                      (truncate-string-to-width content 300 nil nil "..."))
                             (format "%s%s from %s in %s %s"
                                    (if marked "Marked. " "")
                                    subject from account mailbox)))
                       ;; Regular list - no account/mailbox
                       (if (and content (not (string-empty-p content)) mail-app-read-message-content)
                           (format "%s%s%s from %s. Message content: %s"
                                  (if marked "Marked. " "")
                                  (if flagged "Flagged. " "")
                                  subject from
                                  (truncate-string-to-width content 300 nil nil "..."))
                         (format "%s%s%s from %s"
                                (if marked "Marked. " "")
                                (if flagged "Flagged. " "")
                                subject from)))))
    (put-text-property (line-beginning-position) line-end 'emacspeak-speak speech-text)))

(defun mail-app-toggle-mark-at-point ()
  "Toggle mark on the message at point for bulk operations."
  (interactive)
  (when-let* ((message (mail-app--get-message-at-point))
              (id (plist-get message :id)))
    (let ((current-line (line-number-at-pos)))
      (if (member id mail-app-marked-messages)
          (progn
            (setq mail-app-marked-messages (delete id mail-app-marked-messages))
            (mail-app--speak "Unmarked" 'delete-object))
        (progn
          (push id mail-app-marked-messages)
          (mail-app--speak "Marked" 'mark-object)))
      ;; Re-format the buffer with updated marks
      (when mail-app-messages-data
        (mail-app--format-messages mail-app-messages-data)
        ;; Return to the next line
        (goto-char (point-min))
        (forward-line current-line)))))

(defun mail-app-toggle-mark-backward ()
  "Toggle mark and move backward (opposite of toggle-mark-at-point)."
  (interactive)
  (when-let* ((message (mail-app--get-message-at-point))
              (id (plist-get message :id)))
    (let ((current-line (line-number-at-pos)))
      (if (member id mail-app-marked-messages)
          (progn
            (setq mail-app-marked-messages (delete id mail-app-marked-messages))
            (mail-app--speak "Unmarked" 'delete-object))
        (progn
          (push id mail-app-marked-messages)
          (mail-app--speak "Marked" 'mark-object)))
      ;; Re-format the buffer with updated marks
      (when mail-app-messages-data
        (mail-app--format-messages mail-app-messages-data)
        ;; Return to the previous line
        (goto-char (point-min))
        (forward-line (max 0 (- current-line 2)))))))

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
      (mail-app--speak (format "Deleting %d messages" (length mail-app-marked-messages)) 'select-object)
      (let ((count 0)
            (errors 0)
            (total (length mail-app-marked-messages)))
        (dolist (id mail-app-marked-messages)
          (condition-case err
              (let* ((msg (seq-find (lambda (m) (string= (plist-get m :id) id))
                                   mail-app-messages-data))
                     (account (or (plist-get msg :account) mail-app-current-account))
                     (mailbox (or (plist-get msg :mailbox) mail-app-current-mailbox)))
                (when (and account mailbox)
                  (mail-app--run-command "messages" "delete" id
                                         "-a" account
                                         "-m" mailbox)
                  (setq count (1+ count))
                  (when (zerop (mod count 5))
                    (message "Deleted %d/%d..." count total))))
            (error
             (setq errors (1+ errors))
             ;; Don't spam with individual errors, just count them
             nil)))
        (setq mail-app-marked-messages nil)
        (let ((msg (format "Deleted %d of %d messages%s"
                          count total
                          (if (> errors 0) (format " (%d failed)" errors) ""))))
          (message msg)
          (mail-app--speak msg 'task-done))
        (mail-app-refresh)))))

(defun mail-app-archive-marked ()
  "Archive all marked messages."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Archiving %d messages" (length mail-app-marked-messages)) 'select-object)
    (let ((count 0)
          (errors 0)
          (total (length mail-app-marked-messages)))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (let* ((msg (seq-find (lambda (m) (string= (plist-get m :id) id))
                                 mail-app-messages-data))
                   (account (or (plist-get msg :account) mail-app-current-account))
                   (mailbox (or (plist-get msg :mailbox) mail-app-current-mailbox)))
              (when (and account mailbox)
                (mail-app--run-command "messages" "archive" id
                                       "-a" account
                                       "-m" mailbox)
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Archived %d/%d..." count total))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Archived %d of %d messages%s"
                        count total
                        (if (> errors 0) (format " (%d failed)" errors) ""))))
        (message msg)
        (mail-app--speak msg 'task-done))
      (mail-app-refresh))))

(defun mail-app-flag-marked ()
  "Flag all marked messages."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Flagging %d messages" (length mail-app-marked-messages)) 'select-object)
    (let ((count 0)
          (errors 0)
          (total (length mail-app-marked-messages)))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (let* ((msg (seq-find (lambda (m) (string= (plist-get m :id) id))
                                 mail-app-messages-data))
                   (account (or (plist-get msg :account) mail-app-current-account))
                   (mailbox (or (plist-get msg :mailbox) mail-app-current-mailbox)))
              (when (and account mailbox)
                (mail-app--run-command "messages" "flag" id
                                       "-a" account
                                       "-m" mailbox
                                       "--flagged" "true")
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Flagged %d/%d..." count total))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Flagged %d of %d messages%s"
                        count total
                        (if (> errors 0) (format " (%d failed)" errors) ""))))
        (message msg)
        (mail-app--speak msg 'task-done))
      (mail-app-refresh))))

(defun mail-app-mark-marked-as-read ()
  "Mark all marked messages as read."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Marking %d messages as read" (length mail-app-marked-messages)) 'select-object)
    (let ((count 0)
          (errors 0)
          (total (length mail-app-marked-messages)))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (let* ((msg (seq-find (lambda (m) (string= (plist-get m :id) id))
                                 mail-app-messages-data))
                   (account (or (plist-get msg :account) mail-app-current-account))
                   (mailbox (or (plist-get msg :mailbox) mail-app-current-mailbox)))
              (when (and account mailbox)
                (mail-app--run-command "messages" "mark" id
                                       "-a" account
                                       "-m" mailbox
                                       "--read" "true")
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Marked %d/%d as read..." count total))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Marked %d of %d messages as read%s"
                        count total
                        (if (> errors 0) (format " (%d failed)" errors) ""))))
        (message msg)
        (mail-app--speak msg 'task-done))
      (mail-app-refresh))))

(defun mail-app-mark-marked-as-unread ()
  "Mark all marked messages as unread."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Marking %d messages as unread" (length mail-app-marked-messages)) 'select-object)
    (let ((count 0)
          (errors 0)
          (total (length mail-app-marked-messages)))
      (dolist (id mail-app-marked-messages)
        (condition-case err
            (let* ((msg (seq-find (lambda (m) (string= (plist-get m :id) id))
                                 mail-app-messages-data))
                   (account (or (plist-get msg :account) mail-app-current-account))
                   (mailbox (or (plist-get msg :mailbox) mail-app-current-mailbox)))
              (when (and account mailbox)
                (mail-app--run-command "messages" "mark" id
                                       "-a" account
                                       "-m" mailbox
                                       "--read" "false")
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Marked %d/%d as unread..." count total))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Marked %d of %d messages as unread%s"
                        count total
                        (if (> errors 0) (format " (%d failed)" errors) ""))))
        (message msg)
        (mail-app--speak msg 'task-done))
      (mail-app-refresh))))

;;; Search

;;;###autoload
(defun mail-app-search (query)
  "Search for messages matching QUERY in current context.
If in a mailbox, searches that mailbox. Otherwise searches all INBOX mailboxes."
  (interactive "sSearch query: ")
  (let* ((account (if (and mail-app-current-account
                           (not (string-equal mail-app-current-account "Search Results")))
                      mail-app-current-account
                    ""))
         (mailbox (if (and mail-app-current-mailbox
                           (not (string-equal mail-app-current-mailbox "Search Results")))
                      mail-app-current-mailbox
                    ""))
         (context-desc (cond
                        ((and (not (string-empty-p account)) (not (string-empty-p mailbox)))
                         (format " in %s/%s" account mailbox))
                        ((not (string-empty-p account))
                         (format " in %s" account))
                        (t " in all INBOX mailboxes"))))
    (mail-app--speak (format "Searching for %s%s" query context-desc) 'select-object)
    (let ((buf (get-buffer-create (format "*Mail.app Search: %s*" query))))
      ;; Setup buffer immediately with loading message
      (with-current-buffer buf
        (mail-app-messages-mode)
        (setq mail-app-current-account account)
        (setq mail-app-current-mailbox (format "Search: %s" query))
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert "Searching...\n")))
      (switch-to-buffer buf)
      ;; Search asynchronously
      (let ((args (list "search" query "-l" (number-to-string mail-app-message-limit))))
        (unless (string-empty-p account)
          (setq args (append args (list "-a" account))))
        (unless (string-empty-p mailbox)
          (setq args (append args (list "-m" mailbox))))
        (apply 'mail-app--run-command-async
               (lambda (output)
                 (let ((messages (mail-app--parse-search-output output)))
                   (when (buffer-live-p buf)
                     (with-current-buffer buf
                       (setq mail-app-messages-data messages)
                       (mail-app--format-messages messages)
                       (mail-app--speak (format "Found %d messages" (length messages)) 'task-done)))))
               args)))))

;;;###autoload
(defun mail-app-search-all (query)
  "Search for messages matching QUERY across all INBOX mailboxes."
  (interactive "sSearch all query: ")
  (mail-app--speak (format "Searching all accounts for %s" query) 'select-object)
  (let ((buf (get-buffer-create (format "*Mail.app Search: %s*" query))))
    ;; Setup buffer immediately with loading message
    (with-current-buffer buf
      (mail-app-messages-mode)
      (setq mail-app-current-account "")
      (setq mail-app-current-mailbox (format "Search: %s" query))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Searching all accounts...\n")))
    (switch-to-buffer buf)
    ;; Search asynchronously
    (mail-app--run-command-async
     (lambda (output)
       (let ((messages (mail-app--parse-search-output output)))
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (setq mail-app-messages-data messages)
             (mail-app--format-messages messages)
             (mail-app--speak (format "Found %d messages" (length messages)) 'task-done)))))
     "search" query "-l" (number-to-string mail-app-message-limit))))

;;; Major modes

(define-derived-mode mail-app-accounts-mode special-mode "Mail-App-Accounts"
  "Major mode for viewing mail-app accounts.

\\{mail-app-accounts-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))

(define-derived-mode mail-app-mailboxes-mode special-mode "Mail-App-Mailboxes"
  "Major mode for viewing mail-app mailboxes.

\\{mail-app-mailboxes-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))

(define-derived-mode mail-app-messages-mode special-mode "Mail-App-Messages"
  "Major mode for viewing mail-app messages.

\\{mail-app-messages-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))

(define-derived-mode mail-app-message-view-mode special-mode "Mail-App-Message"
  "Major mode for viewing a single mail-app message.

\\{mail-app-message-view-mode-map}"
  (setq buffer-read-only t)
  (setq truncate-lines nil)
  (add-hook 'post-command-hook 'mail-app--emacspeak-post-command nil t))

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
      "J" 'mail-app-jump-to-mail-app
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "S" 'mail-app-search-all
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key 'normal mail-app-mailboxes-mode-map
      (kbd "RET") 'mail-app-view-messages-at-point
      "c" 'mail-app-compose
      "J" 'mail-app-jump-to-mail-app
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "S" 'mail-app-search-all
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key 'normal mail-app-messages-mode-map
      (kbd "RET") 'mail-app-view-message-at-point
      "c" 'mail-app-compose
      "C" 'mail-app-toggle-read-content
      "J" 'mail-app-jump-to-mail-app
      "o" 'mail-app-sort-messages
      "O" 'mail-app-reverse-sort
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "S" 'mail-app-search-all
      "f" 'mail-app-flag-message-at-point
      "d" 'mail-app-delete-message-at-point
      "a" 'mail-app-archive-message-at-point
      "t" 'mail-app-mark-message-at-point
      "u" 'mail-app-show-unread
      "N" 'mail-app-load-more-messages
      ;; Marking for bulk operations
      "m" 'mail-app-toggle-mark-at-point
      "M" 'mail-app-toggle-mark-backward
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
      (kbd "RET") 'mail-app-save-attachment-at-point
      "r" 'mail-app-reply-current-message
      "R" 'mail-app-reply-all-current-message
      (kbd "TAB") 'mail-app-cycle-view
      (kbd "<backtab>") 'mail-app-cycle-view-reverse
      "c" 'mail-app-compose
      "J" 'mail-app-jump-to-mail-app
      "f" 'mail-app-flag-current-message
      "d" 'mail-app-delete-current-message
      "a" 'mail-app-archive-current-message
      "t" 'mail-app-mark-current-message
      "s" 'mail-app-save-attachment-at-point
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

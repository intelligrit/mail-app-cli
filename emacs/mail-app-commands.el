;;; mail-app-commands.el --- All interactive commands for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; All interactive commands for mail-app

(require 'message)
(require 'mml)
(require 'sendmail)
(require 'mail-app-core)
(require 'mail-app-display)
(require 'mail-app-modes)



;;; Code:


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



(defun mail-app-toggle-accounts-sort ()
  "Toggle between alphabetical and natural (setup) order for accounts."
  (interactive)
  (unless mail-app-accounts-data
    (error "No accounts to sort"))
  (setq mail-app-accounts-sort-alphabetical (not mail-app-accounts-sort-alphabetical))
  (mail-app--format-accounts mail-app-accounts-data)
  (mail-app--speak (format "Sorted by %s order"
                          (if mail-app-accounts-sort-alphabetical "alphabetical" "natural"))
                  'select-object))



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



(defun mail-app-junk-message-at-point ()
  "Mark message at point as junk (move to Junk mailbox)."
  (interactive)
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (mail-app--speak "Marking as junk" 'select-object)
      (let ((id (plist-get message :id))
            (buf (current-buffer)))
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (mail-app--speak "Marked as junk" 'task-done)
               (mail-app-refresh))))
         "messages" "move" id "Junk"
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox)))))



(defun mail-app-move-message-at-point (target-mailbox)
  "Move message at point to TARGET-MAILBOX."
  (interactive
   (list (completing-read "Move to mailbox: "
                         (let* ((output (mail-app--run-command "mailboxes" "list"
                                                              "-a" mail-app-current-account))
                                (mailboxes (mail-app--parse-mailboxes-output output)))
                           (mapcar (lambda (mbox) (plist-get mbox :name)) mailboxes))
                         nil t)))
  (let ((message (mail-app--get-message-at-point)))
    (if (not message)
        (message "No message at point")
      (mail-app--speak (format "Moving to %s" target-mailbox) 'select-object)
      (let ((id (plist-get message :id))
            (buf (current-buffer)))
        (mail-app--run-command-async
         (lambda (output)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (mail-app--speak (format "Moved to %s" target-mailbox) 'task-done)
               (mail-app-refresh))))
         "messages" "move" id target-mailbox
         "-a" mail-app-current-account
         "-m" mail-app-current-mailbox)))))



(defun mail-app-forward-message-at-point ()
  "Forward message at point."
  (interactive)
  (when-let* ((message (mail-app--get-message-at-point)))
    (let* ((account (or (plist-get message :account) mail-app-current-account))
           (mailbox (or (plist-get message :mailbox) mail-app-current-mailbox))
           (id (plist-get message :id)))
      ;; Set current context for the forward function
      (setq mail-app-current-account account)
      (setq mail-app-current-mailbox mailbox)
      (setq mail-app-current-message-id id)
      ;; Call the forward function
      (mail-app-forward-current-message))))



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
      (message-goto-body)
      ;; Insert signature if configured
      (when-let* ((signature (mail-app--get-signature mail-app-current-account)))
        (insert "\n" signature "\n"))
      ;; Insert quoted original message
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
      (message-goto-body)
      ;; Insert signature if configured
      (when-let* ((signature (mail-app--get-signature mail-app-current-account)))
        (insert "\n" signature "\n"))
      ;; Insert quoted original message
      (when body
        (goto-char (point-max))
        (insert "\n\n")
        (insert (replace-regexp-in-string "^" "> " body)))
      (message-goto-body)
      (message "Composing reply to all..."))))



(defun mail-app-forward-current-message ()
  "Forward the current message."
  (interactive)
  (when mail-app-current-message-id
    (let* ((output (mail-app--run-command "messages" "show" mail-app-current-message-id
                                          "-a" mail-app-current-account
                                          "-m" mail-app-current-mailbox))
           (details (mail-app--parse-message-details output))
           (from (plist-get details :from))
           (date (plist-get details :date-sent))
           (to (plist-get details :to))
           (subject (plist-get details :subject))
           (body (plist-get details :content))
           (fwd-subject (if (string-prefix-p "Fwd: " subject)
                            subject
                          (concat "Fwd: " subject)))
           (from-email (mail-app--get-account-email mail-app-current-account)))
      (compose-mail nil fwd-subject)
      ;; Now we're in the message buffer - set message-options here
      (setq-local message-options `((account . ,mail-app-current-account)))
      ;; Override send function to use mail-app-cli
      (setq-local message-send-mail-function 'mail-app--message-send-mail)
      ;; Set From header based on account email
      (message-goto-from)
      (beginning-of-line)
      (kill-line)
      (insert (format "From: %s" from-email))
      (message-goto-body)
      ;; Insert signature if configured
      (when-let* ((signature (mail-app--get-signature mail-app-current-account)))
        (insert "\n" signature "\n\n"))
      ;; Insert forwarded message header and body
      (insert "---------- Forwarded message ----------\n")
      (insert (format "From: %s\n" from))
      (when date
        (insert (format "Date: %s\n" date)))
      (when to
        (insert (format "To: %s\n" to)))
      (insert (format "Subject: %s\n\n" subject))
      (when body
        (insert body))
      (message-goto-to)
      (message "Composing forward..."))))



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
           ;; Parse MML to extract attachments and body
           (attachments '())
           (body-start (save-excursion
                         (goto-char (point-min))
                         (search-forward mail-header-separator nil t)
                         (forward-line 1)
                         (point)))
           (mml-structure (condition-case nil
                              (mml-parse)
                            (error nil)))
           (body-text ""))
      ;; Extract attachments from MML structure
      (when mml-structure
        (let ((parts (if (eq (car mml-structure) 'multipart)
                         (cddr mml-structure)
                       (list mml-structure))))
          (dolist (part parts)
            (when (listp part)
              (let ((type (cdr (assq 'type (cdr part))))
                    (filename (cdr (assq 'filename (cdr part))))
                    (disposition (cdr (assq 'disposition (cdr part)))))
                (when (and filename
                          (or (equal disposition "attachment")
                              (not (or (equal type "text/plain")
                                      (equal type "text/html")))))
                  (push (expand-file-name filename) attachments))))))
        ;; Get the text body by generating without attachments
        (setq body-text
              (with-temp-buffer
                (insert (buffer-substring-no-properties body-start (point-max)))
                ;; Remove attachment tags but keep text parts
                (goto-char (point-min))
                (while (re-search-forward "<#part[^>]+disposition=attachment[^>]*>.*?<#/part>" nil t)
                  (replace-match ""))
                (goto-char (point-min))
                (while (re-search-forward "<#/?\\(multipart\\|part\\)[^>]*>" nil t)
                  (replace-match ""))
                (buffer-substring-no-properties (point-min) (point-max)))))
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
    ;; Insert signature if configured
    (when-let* ((signature (mail-app--get-signature account)))
      (message-goto-body)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert "\n" signature))
    (message-goto-to)
    (message "Composing new message...")))



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



(defun mail-app-junk-marked ()
  "Mark all marked messages as junk (move to Junk mailbox)."
  (interactive)
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Marking %d messages as junk" (length mail-app-marked-messages)) 'select-object)
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
                (mail-app--run-command "messages" "move" id "Junk"
                                       "-a" account
                                       "-m" mailbox)
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Marked %d/%d as junk..." count total))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Marked %d of %d messages as junk%s"
                        count total
                        (if (> errors 0) (format " (%d failed)" errors) ""))))
        (message msg)
        (mail-app--speak msg 'task-done))
      (mail-app-refresh))))



(defun mail-app-move-marked (target-mailbox)
  "Move all marked messages to TARGET-MAILBOX."
  (interactive
   (list (completing-read "Move to mailbox: "
                         (let* ((output (mail-app--run-command "mailboxes" "list"
                                                              "-a" (or mail-app-current-account "")))
                                (mailboxes (mail-app--parse-mailboxes-output output)))
                           (mapcar (lambda (mbox) (plist-get mbox :name)) mailboxes))
                         nil t)))
  (if (null mail-app-marked-messages)
      (message "No messages marked")
    (mail-app--speak (format "Moving %d messages to %s" (length mail-app-marked-messages) target-mailbox) 'select-object)
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
                (mail-app--run-command "messages" "move" id target-mailbox
                                       "-a" account
                                       "-m" mailbox)
                (setq count (1+ count))
                (when (zerop (mod count 5))
                  (message "Moved %d/%d to %s..." count total target-mailbox))))
          (error
           (setq errors (1+ errors))
           nil)))
      (setq mail-app-marked-messages nil)
      (let ((msg (format "Moved %d of %d messages to %s%s"
                        count total target-mailbox
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


(provide 'mail-app-commands)

;;; mail-app-commands.el ends here

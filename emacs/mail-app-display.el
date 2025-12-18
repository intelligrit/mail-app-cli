;;; mail-app-display.el --- Display and formatting functions for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Display and formatting functions for mail-app

(require 'mail-app-core)



;;; Code:


;;; Display functions

(defun mail-app--format-accounts (accounts)
  "Format ACCOUNTS for display."
  (let ((inhibit-read-only t)
        (sorted-accounts (if mail-app-accounts-sort-alphabetical
                             (sort (copy-sequence accounts)
                                   (lambda (a b)
                                     (string< (plist-get a :name)
                                             (plist-get b :name))))
                           accounts)))
    (erase-buffer)
    (insert (propertize "Mail.app Accounts\n" 'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] mailboxes  [c] compose  [s] search  [S] search all\n")
    (insert "          [o] toggle sort  [J] jump to Mail.app  [g/r] refresh  [q] quit  [?] help\n\n")
    (insert (format "%-30s %-40s %-10s  Sort: %s\n"
                    "ACCOUNT" "EMAIL" "ENABLED"
                    (if mail-app-accounts-sort-alphabetical "alphabetical" "natural")))
    (insert (make-string 85 ?-) "\n")
    (dolist (account sorted-accounts)
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
    (forward-line 6))) 


(defun mail-app--format-mailboxes (mailboxes)
  "Format MAILBOXES for display."
  (let* ((inhibit-read-only t)
         (sorted-mailboxes (mail-app--sort-mailboxes mailboxes))
         (single-account (and mail-app-current-account
                             (not (string= mail-app-current-account "")))))
    (erase-buffer)
    (insert (propertize (format "Mail.app Mailboxes%s\n"
                                (if single-account
                                    (format ": %s" mail-app-current-account)
                                  ""))
                        'face 'bold))
    (insert "\n")
    (insert "Commands: [RET] messages  [c] compose  [s] search  [S] search all\n")
    (insert "          [J] jump to Mail.app  [g/r] refresh  [q] quit  [?] help\n\n")
    (if single-account
        (progn
          (insert (format "%-60s %8s %8s\n"
                          "MAILBOX" "UNREAD" "TOTAL"))
          (insert (make-string 80 ?-) "\n"))
      (progn
        (insert (format "%-30s %-40s %8s %8s\n"
                        "ACCOUNT" "MAILBOX" "UNREAD" "TOTAL"))
        (insert (make-string 90 ?-) "\n")))
    (dolist (mailbox sorted-mailboxes)
      (let* ((account (plist-get mailbox :account))
             (name (plist-get mailbox :name))
             (unread (plist-get mailbox :unread))
             (total (plist-get mailbox :total))
             (line (if single-account
                       (format "%-60s %8d %8d\n" name unread total)
                     (format "%-30s %-40s %8d %8d\n" account name unread total)))
             (speech-text (if single-account
                              (format "%s mailbox, %d unread, %d total"
                                     name unread total)
                            (format "%s mailbox in %s account, %d unread, %d total"
                                   name account unread total)))
             (start (point)))
        (insert line)
        (put-text-property start (point) 'mail-app-mailbox-data mailbox)
        (put-text-property start (point) 'emacspeak-speak speech-text)
        (when (> unread 0)
          (put-text-property start (point) 'face 'bold))))
    (goto-char (point-min))
    (forward-line 6))) 

 ; Skip title, blank, commands (2 lines), blank, header

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
    (forward-line 9)) 

 ; Skip title, blank, command lines (5), blank, header

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


(provide 'mail-app-display)

;;; mail-app-display.el ends here

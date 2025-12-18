;;; mail-app-core.el --- Core functionality for mail-app including customization, variables, and utilities -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Core functionality for mail-app including customization, variables, and utilities



;;; Code:


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



(defcustom mail-app-message-limit 15
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



(defcustom mail-app-signatures nil
  "Alist mapping account names to signatures.
Each element is (ACCOUNT-NAME . SIGNATURE) where SIGNATURE can be:
  - A string containing the signature text
  - A file path (starting with ~/ or /) to read signature from
  - A function that returns the signature string

Example:
  (setq mail-app-signatures
        '((\"Skyward\" . \"--\\nRobert Melton\\nSkyward IT\")
          (\"Gmail\" . \"~/signatures/gmail.txt\")
          (\"Fastmail\" . my-fastmail-signature-function)))"
  :type '(alist :key-type (string :tag "Account name")
                :value-type (choice
                             (string :tag "Signature text")
                             (file :tag "Signature file path")
                             (function :tag "Signature function")))
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



(defvar-local mail-app-accounts-sort-alphabetical nil
  "If non-nil, sort accounts alphabetically. Otherwise use natural (setup) order.")



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



(defun mail-app--get-signature (account-name)
  "Get the signature for ACCOUNT-NAME.
Returns the signature text or nil if none is configured."
  (when-let* ((sig-config (cdr (assoc account-name mail-app-signatures))))
    (cond
     ;; Function - call it
     ((functionp sig-config)
      (funcall sig-config))
     ;; File path - read from file
     ((and (stringp sig-config)
           (or (string-prefix-p "~/" sig-config)
               (string-prefix-p "/" sig-config)))
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents (expand-file-name sig-config))
            (buffer-string))
        (error nil)))
     ;; Plain string - use as-is
     ((stringp sig-config)
      sig-config)
     (t nil))))



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


 ; Skip title, blank, commands (2 lines), blank, header

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



;; Custom send function for message-mode
(defun mail-app--message-send-mail ()
  "Send mail using mail-app-cli instead of default sendmail."
  (mail-app-send-message))



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


(provide 'mail-app-core)

;;; mail-app-core.el ends here

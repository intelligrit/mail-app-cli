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



(defconst mail-app-required-cli-version "1.2.0"
  "Minimum mail-app-cli version this package needs.
Bump when the Elisp starts relying on new CLI behaviour.")

(defvar mail-app--cli-version-checked nil
  "Non-nil once the installed mail-app-cli version has been verified this session.")

(defun mail-app--installed-cli-version ()
  "Return the installed mail-app-cli version string, or nil if unavailable."
  (condition-case nil
      (with-temp-buffer
        (when (zerop (call-process mail-app-command nil t nil "--version"))
          (goto-char (point-min))
          (when (re-search-forward "\\([0-9]+\\(?:\\.[0-9]+\\)+\\)" nil t)
            (match-string 1))))
    (error nil)))

(defun mail-app--check-cli-version (&optional force)
  "Warn once per session if the installed mail-app-cli is too old.
Returns non-nil when the binary satisfies `mail-app-required-cli-version'.
With FORCE, re-check even if already verified."
  (if (and mail-app--cli-version-checked (not force))
      (eq mail-app--cli-version-checked 'ok)
    (let* ((installed (mail-app--installed-cli-version))
           (ok (and installed (version<= mail-app-required-cli-version installed))))
      (setq mail-app--cli-version-checked (if ok 'ok 'old))
      (unless ok
        (let ((msg (if installed
                       (format "mail-app-cli %s is older than the %s this package needs; run `make install' in the mail-app-cli repo"
                               installed mail-app-required-cli-version)
                     (format "mail-app-cli not found or does not report a version (`%s --version'); expected %s or newer"
                             mail-app-command mail-app-required-cli-version))))
          (display-warning 'mail-app msg :warning)
          (when (fboundp 'mail-app--speak)
            (mail-app--speak msg 'warn-user))))
      ok)))



(defcustom mail-app-default-account nil
  "Default Mail.app account to use.
If nil, you will be prompted to select one when needed."
  :type '(choice (const :tag "Prompt each time" nil)
                 (string :tag "Account name"))
  :group 'mail-app)



(defcustom mail-app-gmail-archive-action 'skip
  "What archiving does to messages in Gmail accounts.
Mail.app offers no safe scriptable archive for Gmail (scripted moves out
of INBOX revert on the next sync).  `skip' leaves them untouched and
reports them; `delete' moves them to Trash (Gmail's own delete); `read'
marks them read and leaves them in the inbox."
  :type '(choice (const :tag "Skip and report" skip)
                 (const :tag "Move to Trash" delete)
                 (const :tag "Mark read" read))
  :group 'mail-app)

(defun mail-app--gmail-archive-flag ()
  "Return the `--gmail' argument list for archive commands."
  (list (format "--gmail=%s" mail-app-gmail-archive-action)))



(defcustom mail-app-mailbox-counts nil
  "If non-nil, ask mail-app-cli for total message counts in mailbox lists.
Totals require enumerating every mailbox (roughly 3s instead of under 1s
across all accounts), so they are off by default."
  :type 'boolean
  :group 'mail-app)



(defcustom mail-app-no-content-mailbox-regexp
  "\\`\\(?:trash\\|deleted items\\|deleted messages\\|spam\\|junk\\(?: e-?mail\\)?\\|bulk mail\\)\\'"
  "Mailboxes whose bodies are never fetched, even with content reading on.
Matched case-insensitively against the mailbox name.  Fetching bodies in
trash/junk is what most often wedges Mail.app's scripting interface (the
body is rarely cached locally and the download can stall), and reading
spam aloud is rarely useful anyway."
  :type 'regexp
  :group 'mail-app)



(defcustom mail-app-message-limit 15
  "Minimum number of messages to fetch.  The actual fetch count is computed
dynamically from the window height; this value is the floor."
  :type 'integer
  :group 'mail-app)



(defcustom mail-app-render-html t
  "If non-nil, render HTML email content using Emacs's shr renderer.
shr produces clean, screen-reader-friendly output: links are announced
with their text, headings use a different voice, and Emacspeak's full
shr integration applies.  Requires Emacs built with libxml2 (check with
`(fboundp 'libxml-parse-html-region)').  Set to nil to see raw text."
  :type 'boolean
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



(defcustom mail-app-default-accounts-sort-method 'natural
  "Default sort method for accounts list.
Options:
  'natural - As returned by mail-app-cli (setup order)
  'alpha   - Alphabetical by account name"
  :type '(choice (const :tag "Natural (setup order)" natural)
                 (const :tag "Alphabetical" alpha))
  :group 'mail-app)



(defcustom mail-app-default-mailboxes-sort-method 'smart
  "Default sort method for mailboxes list.
Options:
  'default - As returned by mail-app-cli
  'smart   - INBOX first, then by unread count, then alphabetical
  'unread  - Pure unread count (descending)
  'alpha   - Alphabetical by mailbox name"
  :type '(choice (const :tag "Default (as returned by CLI)" default)
                 (const :tag "Smart (INBOX first, then unread)" smart)
                 (const :tag "Unread count" unread)
                 (const :tag "Alphabetical" alpha))
  :group 'mail-app)



(defcustom mail-app-default-messages-sort-method 'date
  "Default sort method for messages list.
Options:
  'date    - Sort by date received
  'subject - Sort by subject
  'from    - Sort by sender
  'unread  - Unread messages first, then by date"
  :type '(choice (const :tag "Date" date)
                 (const :tag "Subject" subject)
                 (const :tag "Sender" from)
                 (const :tag "Unread first" unread))
  :group 'mail-app)



(defcustom mail-app-default-messages-sort-reverse nil
  "If non-nil, reverse the default message sort order."
  :type 'boolean
  :group 'mail-app)



(defcustom mail-app-mark-as-read-on-view t
  "If non-nil, automatically mark messages as read when viewing them."
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
    (define-key map (kbd "o") 'mail-app-toggle-accounts-sort)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    ;; Unified mailbox shortcuts
    (define-key map (kbd "I") 'mail-app-list-inbox)
    (define-key map (kbd "U") 'mail-app-list-unread)
    (define-key map (kbd "G") 'mail-app-list-sent)      ; G = "sent/gone"
    (define-key map (kbd "D") 'mail-app-list-drafts)
    (define-key map (kbd "*") 'mail-app-list-flagged)
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
    (define-key map (kbd "o") 'mail-app-toggle-mailboxes-sort)
    (define-key map (kbd "T") 'mail-app-mark-mailbox-as-read)
    (define-key map (kbd "R") 'mail-app-mark-special-read)
    (define-key map (kbd "c") 'mail-app-compose)
    (define-key map (kbd "J") 'mail-app-jump-to-mail-app)
    ;; Unified mailbox shortcuts
    (define-key map (kbd "I") 'mail-app-list-inbox)
    (define-key map (kbd "U") 'mail-app-list-unread)
    (define-key map (kbd "G") 'mail-app-list-sent)      ; G = "sent/gone"
    (define-key map (kbd "D") 'mail-app-list-drafts)
    (define-key map (kbd "*") 'mail-app-list-flagged)
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
    (define-key map (kbd "T") 'mail-app-mark-all-as-read)
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



(defvar-local mail-app-current-limit nil
  "Number of messages fetched per page in this buffer.
Set when the buffer is first loaded; reused by `mail-app-load-more-messages'
so that every page uses the same batch size even if the window is resized.")



(defun mail-app--compute-message-limit ()
  "Return how many messages to fetch based on the current window height.
Uses `mail-app-message-limit' as the minimum."
  (let* ((height (window-body-height))
         ;; 4 fixed header rows (title blank col-headers separator) + 2 safety
         (usable (- height 6)))
    (max mail-app-message-limit usable)))



(defvar-local mail-app-body-start nil
  "Marker at the start of message body content in a message-view buffer.
Set when the message is rendered; used by `mail-app-jump-to-body'.")



(defvar-local mail-app-current-view-mode 'plain
  "Current view mode for message: 'plain (content only), 'full (with headers), or 'attachments.")



(defvar-local mail-app-message-sort-key nil
  "Current sort key for messages: 'date, 'subject, 'from, or 'unread.")



(defvar-local mail-app-message-sort-reverse nil
  "If non-nil, reverse the sort order.")



(defvar-local mail-app-unified-view nil
  "Type of unified view being displayed.
Possible values: nil (standard account/mailbox view), 'inbox, 'unread,
'sent, 'drafts, 'flagged, 'trash, 'junk.")



(defvar-local mail-app-accounts-sort-method nil
  "Current sort method for accounts: 'natural or 'alpha.")



(defvar-local mail-app-mailboxes-sort-method nil
  "Current sort method for mailboxes: 'default, 'smart, 'unread, or 'alpha.")



(defvar-local mail-app--sort-initialized nil
  "Flag to track if sort settings have been initialized from defaults.")



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



(defun mail-app--content-args (&optional mailbox)
  "Return the `--with-content' argument list for the current view, or nil.
Content is requested only when `mail-app-read-message-content' is non-nil
and the view is not trash or junk: either the unified `trash'/`junk' view
(`mail-app-unified-view') or a MAILBOX (default `mail-app-current-mailbox')
matching `mail-app-no-content-mailbox-regexp'."
  (let ((name (or mailbox mail-app-current-mailbox))
        (case-fold-search t))
    (when (and mail-app-read-message-content
               (not (memq mail-app-unified-view '(trash junk)))
               (not (and name (string-match-p mail-app-no-content-mailbox-regexp name))))
      '("--with-content"))))



(defun mail-app--run-command (&rest args)
  "Run mail-app-cli command with ARGS and return output."
  (with-temp-buffer
    (let ((exit-code (apply 'call-process mail-app-command nil '(t t) nil args)))
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
       (condition-case sentinel-err
           (let ((buf (process-buffer process)))
             (when (and (buffer-live-p buf)
                        (string-match-p "\\(?:finished\\|exited abnormally\\)" event))
               (let ((output (with-current-buffer buf
                               (buffer-substring-no-properties (point-min) (point-max)))))
                 (kill-buffer buf)
                 (if (string-match-p "finished" event)
                     (condition-case err
                         (funcall callback output)
                       (error (message "Mail-app callback error: %S\nCommand: %S" err args)))
                   ;; Abnormal exit: log and call callback with error-prefixed output so
                   ;; bulk runners can count it as a failure and keep the chain moving.
                   (message "Mail-app command failed: %s\nCommand: %S" output args)
                   (condition-case err
                       (funcall callback (concat "error: " output))
                     (error (message "Mail-app callback error: %S\nCommand: %S" err args)))))))
         (error (message "Mail-app sentinel CRASH: %S\nCommand: %S" sentinel-err args)))))))


(defun mail-app--run-bulk-async (operations on-complete &optional progress-callback)
  "Run OPERATIONS asynchronously and call ON-COMPLETE when done.
OPERATIONS is a list of (args-list) where each args-list is passed to mail-app-cli.
ON-COMPLETE is called with (success-count error-count total).
PROGRESS-CALLBACK if provided is called with (completed total) for each operation."
  (let* ((total (length operations))
         (remaining (copy-sequence operations))
         (success-count 0)
         (error-count 0))
    (if (null remaining)
        ;; No operations - call completion immediately
        (funcall on-complete 0 0 0)
      ;; Process operations one at a time asynchronously
      (letrec ((process-next
                (lambda ()
                  (if (null remaining)
                      ;; All done
                      (funcall on-complete success-count error-count total)
                    ;; Process next operation
                    (let ((args (pop remaining)))
                      (apply #'mail-app--run-command-async
                             (lambda (output)
                               ;; Check for errors in output
                               (if (string-match-p "error\\|Error\\|failed\\|Failed" output)
                                   (setq error-count (1+ error-count))
                                 (setq success-count (1+ success-count)))
                               ;; Progress callback
                               (when progress-callback
                                 (funcall progress-callback (+ success-count error-count) total))
                               ;; Process next
                               (funcall process-next))
                             args))))))
        (funcall process-next)))))


(defun mail-app--parse-mutation-output (output)
  "Parse the JSON summary a global-ID mutation prints to stdout.
OUTPUT may also contain the stderr summary line before or after the JSON.
Returns a plist (:ok N :missing N :failed N :skipped N :results LIST) or
nil if no JSON object is present."
  (condition-case nil
      (let ((start (string-match "{" output))
            (end (and (string-match "}[^}]*\\'" output) (match-beginning 0))))
        (when (and start end (< start end))
          (let ((obj (json-parse-string (substring output start (1+ end))
                                        :object-type 'alist :array-type 'list)))
            (list :ok (or (alist-get 'ok obj) 0)
                  :missing (or (alist-get 'missing obj) 0)
                  :failed (or (alist-get 'failed obj) 0)
                  :skipped (or (alist-get 'skipped obj) 0)
                  :results (alist-get 'results obj)))))
    (error nil)))

(defun mail-app--run-mutation-async (ids on-complete &rest args)
  "Run one global-ID mutation on IDS in a single mail-app-cli process.
ARGS are the leading arguments, e.g. (\"messages\" \"archive\"); IDS are
appended, followed by any strings in the tail of ARGS after the symbol
`:after' (used for move's target and for flags).  Because Mail.app message
IDs are unique across accounts, no account/mailbox context is needed and
messages from any mix of accounts go in one round trip.
ON-COMPLETE is called with the plist from `mail-app--parse-mutation-output',
or with (:ok 0 :failed N :error STRING) if the output could not be parsed."
  (let* ((split (memq :after args))
         (head (if split (seq-take args (- (length args) (length split))) args))
         (tail (cdr split))
         (n (length ids)))
    (apply #'mail-app--run-command-async
           (lambda (output)
             (funcall on-complete
                      (or (mail-app--parse-mutation-output output)
                          (list :ok 0 :missing 0 :failed n :skipped 0
                                :error (string-trim output)))))
           (append head (mapcar (lambda (id) (format "%s" id)) ids) tail))))

(defun mail-app--mutation-summary (result verb-past)
  "Build a human/speech summary string for mutation RESULT.
VERB-PAST is e.g. \"Archived\"."
  (let ((ok (plist-get result :ok))
        (failed (+ (plist-get result :missing) (plist-get result :failed)))
        (skipped (plist-get result :skipped))
        (err (plist-get result :error)))
    (concat (format "%s %d message%s" verb-past ok (if (= ok 1) "" "s"))
            (if (> skipped 0)
                (format ", %d Gmail skipped (archive them in Mail or Gmail)" skipped)
              "")
            (if (> failed 0) (format ", %d failed" failed) "")
            (if err (format ": %s" err) ""))))

(defun mail-app--parse-mark-read-output (output)
  "Parse `mailboxes mark-read' JSON OUTPUT into total changed count.
Returns nil if OUTPUT is not parseable."
  (condition-case nil
      (let ((json-start (string-match "\\[" output))
            (json-end (and (string-match "\\][^]]*\\'" output) (match-beginning 0))))
        (when (and json-start json-end (< json-start json-end))
          (let ((results (json-parse-string (substring output json-start (1+ json-end))
                                            :object-type 'alist :array-type 'list)))
            (apply #'+ (mapcar (lambda (r) (or (alist-get 'changed r) 0)) results)))))
    (error nil)))

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
  "Sort MESSAGES by SORT-KEY. Reverse if REVERSE is non-nil.
For 'thread, returns threaded and flattened messages; for other keys, sorts linearly."
  (if (eq sort-key 'thread)
      ;; Thread view: group by Message-ID/In-Reply-To/References, flatten for display
      (mail-app--flatten-threads (mail-app--build-threads messages))
    ;; Linear sorts
    (let ((sorted (sort (copy-sequence messages)
                       (lambda (a b)
                         (let ((val-a (pcase sort-key
                                       ('date (plist-get a :date))
                                       ('subject (downcase (or (plist-get a :subject) "")))
                                       ('from (downcase (or (plist-get a :from) "")))
                                       ('unread (if (plist-get a :read) "1" "0"))
                                       ('read (if (plist-get a :read) "1" "0")) ; backwards compatibility
                                       (_ (plist-get a :date))))
                               (val-b (pcase sort-key
                                       ('date (plist-get b :date))
                                       ('subject (downcase (or (plist-get b :subject) "")))
                                       ('from (downcase (or (plist-get b :from) "")))
                                       ('unread (if (plist-get b :read) "1" "0"))
                                       ('read (if (plist-get b :read) "1" "0")) ; backwards compatibility
                                       (_ (plist-get b :date)))))
                           (if (memq sort-key '(unread read))
                               (string< val-a val-b)
                             (string< (format "%s" val-a) (format "%s" val-b))))))))
      (if reverse (nreverse sorted) sorted))))


(defun mail-app--build-threads (messages)
  "Build a threaded view of MESSAGES using Message-ID/In-Reply-To/References.
Returns a list where each element is either a single message or
a cons (root . children) representing a thread tree.
Messages without threading headers are grouped with others by subject."
  (let ((by-id (make-hash-table :test 'equal))
        (by-subject (make-hash-table :test 'equal))
        (roots '())
        (visited (make-hash-table :test 'equal)))
    ;; Index all messages by Message-ID
    (dolist (msg messages)
      (let ((msg-id (plist-get msg :message-id)))
        (when msg-id
          (puthash msg-id msg by-id))))
    ;; Build parent-child relationships
    (let ((threads (make-hash-table :test 'equal)))
      (dolist (msg messages)
        (let* ((in-reply-to (plist-get msg :in-reply-to))
               (parent-id (and in-reply-to
                              (substring in-reply-to 1 -1)))) ; strip < >
          (if (and parent-id (gethash parent-id by-id))
              ;; Message has a known parent
              (let ((parent-thread (gethash parent-id threads)))
                (if parent-thread
                    (nconc parent-thread (list msg))
                  (puthash (plist-get msg :id) (list msg) threads)))
            ;; No parent or parent not found: treat as potential root
            (unless (gethash (plist-get msg :id) threads)
              (puthash (plist-get msg :id) (list msg) threads)))))
      ;; Identify actual roots (messages with no parent in our set)
      (dolist (msg messages)
        (let* ((in-reply-to (plist-get msg :in-reply-to))
               (parent-id (and in-reply-to
                              (substring in-reply-to 1 -1)))
               (msg-id (plist-get msg :id)))
          (when (or (not in-reply-to)
                   (not (gethash parent-id by-id)))
            (unless (gethash msg-id visited)
              (puthash msg-id t visited)
              (let ((thread (gethash msg-id threads)))
                (if (and thread (> (length thread) 1))
                    (push thread roots)
                  (push msg roots)))))))
      (nreverse roots))))


(defun mail-app--flatten-threads (threads)
  "Flatten threaded view THREADS back into a message list.
For now, returns messages in thread order without visual markers
(display integration is a separate task).  Each message gains :indent and
:thread-marker keys for future display use."
  ;; TODO: Properly flatten thread tree with indentation markers
  ;; For now, return messages sorted by thread root date, then by reply date
  (let ((result '()))
    (dolist (item threads)
      (if (and (listp item) (plist-get item :id))
          ;; Single message
          (push item result)
        ;; Thread list — add all messages in the thread
        (dolist (msg (if (listp item) item (list item)))
          (push msg result))))
    (nreverse result)))



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

(defun mail-app--sort-mailboxes (mailboxes sort-method)
  "Sort MAILBOXES according to SORT-METHOD.
SORT-METHOD can be:
  'default - As returned by mail-app-cli (no sorting)
  'smart   - INBOX first, then by unread count, then alphabetical
  'unread  - Pure unread count (descending)
  'alpha   - Alphabetical by mailbox name"
  (pcase sort-method
    ('default mailboxes)
    ('alpha
     (sort mailboxes
           (lambda (a b)
             (string< (plist-get a :name) (plist-get b :name)))))
    ('unread
     (sort mailboxes
           (lambda (a b)
             (> (or (plist-get a :unread) 0)
                (or (plist-get b :unread) 0)))))
    ('smart
     (sort mailboxes
           (lambda (a b)
             (let ((name-a (plist-get a :name))
                   (name-b (plist-get b :name))
                   (unread-a (or (plist-get a :unread) 0))
                   (unread-b (or (plist-get b :unread) 0)))
               (cond
                ;; INBOX always comes first (case-insensitive)
                ((string-equal (upcase name-a) "INBOX") t)
                ((string-equal (upcase name-b) "INBOX") nil)
                ;; Then sort by unread count (descending)
                ((not (= unread-a unread-b)) (> unread-a unread-b))
                ;; Finally alphabetically
                (t (string< name-a name-b)))))))
    (_ mailboxes)))



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
         (read (plist-get message :read))
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
                               (format "%s%s%s from %s in %s %s. Message content: %s"
                                      (if marked "Marked. " "")
                                      (if (not read) "Unread. " "")
                                      subject from account mailbox
                                      (truncate-string-to-width content 300 nil nil "..."))
                             (format "%s%s%s from %s in %s %s"
                                    (if marked "Marked. " "")
                                    (if (not read) "Unread. " "")
                                    subject from account mailbox)))
                       ;; Regular list - no account/mailbox
                       (if (and content (not (string-empty-p content)) mail-app-read-message-content)
                           (format "%s%s%s%s from %s. Message content: %s"
                                  (if marked "Marked. " "")
                                  (if (not read) "Unread. " "")
                                  (if flagged "Flagged. " "")
                                  subject from
                                  (truncate-string-to-width content 300 nil nil "..."))
                         (format "%s%s%s%s from %s"
                                (if marked "Marked. " "")
                                (if (not read) "Unread. " "")
                                (if flagged "Flagged. " "")
                                subject from)))))
    (put-text-property (line-beginning-position) line-end 'emacspeak-speak speech-text)))


(provide 'mail-app-core)

;;; mail-app-core.el ends here

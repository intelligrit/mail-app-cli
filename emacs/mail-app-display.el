;;; mail-app-display.el --- Display and formatting functions for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Display and formatting functions for mail-app

(require 'mail-app-core)



;;; Code:

(defun mail-app--escape-for-speech (text)
  "Escape TEXT for emacspeak by replacing colons with commas."
  (when text
    (replace-regexp-in-string ":" "," text)))


;;; Message body rendering

(defun mail-app--content-html-p (content)
  "Return t if CONTENT appears to be HTML rather than plain text."
  (and (stringp content)
       (string-match-p "<[a-zA-Z!][^>]*>" content)))

(defun mail-app--insert-html (html)
  "Render HTML string into the current buffer using shr.
shr is Emacs's built-in HTML renderer (used by EWW).  Emacspeak advises
shr extensively, so links, headings, and emphasis are all spoken correctly."
  (require 'shr)
  (let* ((dom (with-temp-buffer
                (insert html)
                (libxml-parse-html-region (point-min) (point-max))))
         ;; Leave a small right margin; avoid variable-width fonts
         (shr-width (max 40 (- (window-width) 4)))
         (shr-use-fonts nil)
         (shr-inhibit-images t)
         ;; Don't apply email's background/foreground colors — respect Emacs theme
         (shr-use-colors nil)
         ;; Skip aria-hidden content (decorative elements, tracking pixels)
         (shr-discard-aria-hidden t)
         ;; Don't fetch external images even if shr tries
         (shr-image-animate nil))
    (shr-insert-document dom)))

(defun mail-app--scrub-text (text)
  "Remove invisible junk characters from email TEXT.
Strips object-replacement characters (U+FFFC — Mail.app's plain-text
rendition leaves one per inline image, displayed as a boxed OBJ glyph),
zero-width spaces and joiners used for address obfuscation (U+200B,
U+2060, U+FEFF), and soft hyphens (U+00AD).  These all render as
clutter and are read aloud by screen readers."
  (if (stringp text)
      (replace-regexp-in-string "[\ufffc\u200b\u2060\ufeff\u00ad]+" "" text)
    text))

(defun mail-app--insert-plain (text)
  "Insert plain-text email body TEXT with readability cleanup.
Formatted for screen-reader flow: meaningful lines only, never more
than one consecutive blank line.
- Scrubs invisible junk (image placeholders, zero-width characters)
- Deletes decoration-only lines (ruled lines, stray punctuation) that
  screen readers would speak as noise
- Strips trailing whitespace per line, collapses all blank runs to a
  single blank line, drops leading blanks
- Marks quoted lines (starting with >) with `shadow' face and,
  when Emacspeak is present, a monotone personality so they are
  spoken in a clearly different voice."
  (setq text (replace-regexp-in-string "\r\n" "\n" text))
  ;; Scrub junk: lines holding only image placeholders become blank,
  ;; and the blank-collapsing below swallows them.
  (setq text (mail-app--scrub-text text))
  ;; Decoration-only lines (no letters or digits): ruled lines, table
  ;; borders, stray punctuation.  Emptied here, collapsed below.
  ;; Quoted lines are kept.
  (setq text (replace-regexp-in-string "^[^[:alnum:]>\n]+$" "" text))
  (setq text (replace-regexp-in-string "[ \t]+\n" "\n" text))
  (setq text (replace-regexp-in-string "\n\n+" "\n\n" text))
  (setq text (string-trim text))
  (let ((start (point)))
    (insert text "\n")
    ;; Heuristic paragraph breaks: HTML block elements lose their
    ;; spacing in Mail.app's text rendition, so paragraphs run
    ;; together.  A longish line ending in sentence punctuation that is
    ;; directly followed by text gets a blank line after it.  Short
    ;; lines (nav items, addresses, list labels) never match, and
    ;; quoted/indented lines are left alone.
    (save-excursion
      (goto-char start)
      (while (re-search-forward "^.\\{40,\\}[.!?][\"')]?\n" nil t)
        (unless (looking-at "[>[:space:]\n]")
          (insert "\n"))))
    ;; Style quoted lines for both visual and audio differentiation
    (save-excursion
      (goto-char start)
      (while (re-search-forward "^>.*" nil t)
        (let ((qs (match-beginning 0))
              (qe (match-end 0)))
          (put-text-property qs qe 'face 'shadow)
          (when (and (featurep 'emacspeak)
                     (boundp 'voice-monotone-medium))
            (put-text-property qs qe 'personality voice-monotone-medium)))))))

(defun mail-app--insert-content (content)
  "Insert email body CONTENT into the current buffer.
Dispatches to shr HTML rendering when `mail-app-render-html' is non-nil
and the content looks like HTML and libxml2 is available.
Falls back to `mail-app--insert-plain' otherwise."
  (when content
    (if (and mail-app-render-html
             (mail-app--content-html-p content)
             (fboundp 'libxml-parse-html-region))
        (mail-app--insert-html content)
      (mail-app--insert-plain content))))


;;; Display functions

(defun mail-app--format-accounts (accounts)
  "Format ACCOUNTS for display."
  ;; Initialize sort method from default on first run
  (unless mail-app--sort-initialized
    (setq mail-app-accounts-sort-method mail-app-default-accounts-sort-method)
    (setq mail-app--sort-initialized t))
  (let ((inhibit-read-only t)
        (sorted-accounts (if (eq mail-app-accounts-sort-method 'alpha)
                             (sort (copy-sequence accounts)
                                   (lambda (a b)
                                     (string< (plist-get a :name)
                                             (plist-get b :name))))
                           accounts)))
    (erase-buffer)
    (insert (propertize "Account List\n" 'face 'bold))
    (insert "\n")
    (insert (format "%-30s %-40s %-10s  Sort: %s\n"
                    "ACCOUNT" "EMAIL" "ENABLED"
                    (if (eq mail-app-accounts-sort-method 'alpha) "alphabetical" "natural")))
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
    (forward-line 4))) 


(defun mail-app--format-mailboxes (mailboxes)
  "Format MAILBOXES for display."
  ;; Initialize sort method from default on first run
  (unless mail-app--sort-initialized
    (setq mail-app-mailboxes-sort-method mail-app-default-mailboxes-sort-method)
    (setq mail-app--sort-initialized t))
  (let* ((inhibit-read-only t)
         (sorted-mailboxes (mail-app--sort-mailboxes mailboxes mail-app-mailboxes-sort-method))
         (single-account (and mail-app-current-account
                             (not (string= mail-app-current-account "")))))
    (erase-buffer)
    (insert (propertize (if single-account
                            (format "%s / Mailboxes\n" mail-app-current-account)
                          "Account / Mailboxes\n")
                        'face 'bold))
    (insert "\n")
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
    (forward-line 4)))



(defun mail-app--format-thread-list (thread-summaries)
  "Format THREAD-SUMMARIES for display in thread list view."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (format "%s / %s / Threads\n"
                                (or mail-app-current-account "Search")
                                (or mail-app-current-mailbox "All"))
                        'face 'bold))
    (insert "\n")
    (insert (format "%-2s %-3s %-45s %-30s %8s\n"
                    "" "   " "THREAD" "LATEST FROM" "COUNT"))
    (insert (make-string 95 ?-) "\n")
    (dolist (summary thread-summaries)
      (let* ((root (plist-get summary :thread-root))
             (unread (plist-get summary :unread))
             (count (plist-get summary :message-count))
             (subject (plist-get root :subject))
             (from (plist-get summary :latest-sender))
             (unread-marker (if unread "●" " "))
             (line (format "%-2s %-3s %-45s %-30s %8d\n"
                           " "
                           unread-marker
                           (truncate-string-to-width subject 45 nil nil "...")
                           (truncate-string-to-width from 30 nil nil "...")
                           count))
             (speech-text (format "%s thread%s, %d messages, from %s"
                                 subject
                                 (if unread " unread" "")
                                 count
                                 from))
             (start (point)))
        (insert line)
        (put-text-property start (point) 'mail-app-thread-data summary)
        (put-text-property start (point) 'emacspeak-speak speech-text)
        (when unread
          (put-text-property start (point) 'face 'bold))))
    (goto-char (point-min))
    (forward-line 4)))


(defun mail-app--format-messages (messages)
  "Format MESSAGES for display."
  ;; Initialize sort settings from defaults on first run
  (unless mail-app--sort-initialized
    (setq mail-app-message-sort-key mail-app-default-messages-sort-method)
    (setq mail-app-message-sort-reverse mail-app-default-messages-sort-reverse)
    (setq mail-app--sort-initialized t))
  (let* ((inhibit-read-only t)
         ;; Check if these are search results or unified views (need account/mailbox columns)
         (is-search (and mail-app-current-mailbox
                        (string-match-p "^Search:" mail-app-current-mailbox)))
         ;; Unified views also need account/mailbox columns
         (is-unified (and (boundp 'mail-app-unified-view) mail-app-unified-view))
         (is-unread-view (eq mail-app-unified-view 'unread))
         (show-account-cols (or is-search is-unified))
         ;; Sort messages
         (sorted-messages (mail-app--sort-messages messages
                                                   mail-app-message-sort-key
                                                   mail-app-message-sort-reverse))
         (sort-indicator (format " [%s%s]"
                                (pcase mail-app-message-sort-key
                                  ('date "date")
                                  ('subject "subject")
                                  ('from "from")
                                  ('thread "thread")
                                  ('unread "unread")
                                  ('read "unread"))
                                (if mail-app-message-sort-reverse " ↓" " ↑")))
         (loaded-count (length messages))
         (page-limit (or mail-app-current-limit mail-app-message-limit))
         (count-indicator (format "  (%d shown)" loaded-count)))
    (erase-buffer)
    (insert (propertize (format "%s / %s / %s%s%s\n"
                                (or mail-app-current-account "Search")
                                (or mail-app-current-mailbox "All")
                                (if mail-app-thread-view "Thread" "Messages")
                                sort-indicator
                                count-indicator)
                        'face 'bold))
    (insert "\n")
    (if show-account-cols
        ;; Search results or unified views: show read status, subject, from, then account/mailbox
        (progn
          (insert (format "%-2s %-3s %-45s %-30s %-15s %-15s\n"
                          "" "   " "SUBJECT" "FROM" "ACCOUNT" "MAILBOX"))
          (insert (make-string 115 ?-) "\n")
          (dolist (message sorted-messages)
            (let* ((id (plist-get message :id))
                   (account (or (plist-get message :account) ""))
                   (mailbox (or (plist-get message :mailbox) ""))
                   (from (or (plist-get message :from) ""))
                   (subject (or (plist-get message :subject) ""))
                   (content (plist-get message :content))
                   (read (plist-get message :read))
                   (flagged (plist-get message :flagged))
                   (marked (member id mail-app-marked-messages))
                   (mark-str (if marked ">" " "))
                   (flag-str (concat (if read " " "●") (if flagged "⚑" " ")))
                   (line (format "%-2s %-3s %-45s %-30s %-15s %-15s\n"
                                 mark-str
                                 flag-str
                                 (truncate-string-to-width subject 45 nil nil "...")
                                 (truncate-string-to-width from 30 nil nil "...")
                                 (truncate-string-to-width account 15 nil nil "...")
                                 (truncate-string-to-width mailbox 15 nil nil "...")))
                   (speech-text (mail-app--escape-for-speech
                                 (concat
                                  (if (and (not read) (not is-unread-view)) "Unread. " "")
                                  (if marked "Marked. " "")
                                  (if flagged "Flagged. " "")
                                  subject ". From " from ". "
                                  (when (and content (not (string-empty-p content)))
                                    (format "Content, %s"
                                            (truncate-string-to-width (mail-app--scrub-text content) 300 nil nil "..."))))))
                   (start (point)))
              (insert line)
              (let ((line-end (1- (point))))
                (put-text-property start line-end 'mail-app-message-data message)
                (put-text-property start line-end 'emacspeak-speak speech-text)
                (when marked
                  (put-text-property start (1+ start) 'auditory-icon nil))
                (cond
                 (marked
                  (put-text-property start line-end 'face 'highlight))
                 ((not read)
                  (put-text-property start line-end 'face 'bold)))))))
      ;; Regular message list: show SUBJECT and FROM only
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
                 (indent (plist-get message :indent))
                 (indent-str (if (and indent (> indent 0))
                                 (concat (make-string (* 2 indent) ?\s) "→ ")
                               ""))
                 (marked (member id mail-app-marked-messages))
                 (mark-str (if marked ">" " "))
                 (flag-str (concat (if read " " "●") (if flagged "⚑" " ")))
                 (subject-display (truncate-string-to-width
                                   subject (max 20 (- 60 (length indent-str)))
                                   nil nil "..."))
                 (line (format "%-2s %-4s %-60s %-40s\n"
                               mark-str
                               flag-str
                               (concat indent-str subject-display)
                               (truncate-string-to-width from 40 nil nil "...")))
                 (speech-text (mail-app--escape-for-speech
                               (concat
                                (if (and indent (> indent 0)) "Reply. " "")
                                (if (and (not read) (not is-unread-view)) "Unread. " "")
                                (if marked "Marked. " "")
                                (if flagged "Flagged. " "")
                                subject ". From " from ". "
                                (when (and content (not (string-empty-p content)))
                                  (format "Content, %s"
                                          (truncate-string-to-width (mail-app--scrub-text content) 300 nil nil "..."))))))
                 (start (point)))
            (insert line)
            (let ((line-end (1- (point))))
              (put-text-property start line-end 'mail-app-message-data message)
              (put-text-property start line-end 'emacspeak-speak speech-text)
              (when marked
                (put-text-property start (1+ start) 'auditory-icon nil))
              (cond
               (marked
                (put-text-property start line-end 'face 'highlight))
               ((not read)
                (put-text-property start line-end 'face 'bold))))))))
    ;; Footer: pagination status
    (let* ((more-available (>= loaded-count page-limit))
           (footer (if more-available
                       (format "── %d messages  [N: load more] ──\n" loaded-count)
                     (format "── %d messages  [end] ──\n" loaded-count))))
      (insert (propertize footer 'face 'shadow
                          'emacspeak-speak (if more-available
                                              (format "%d messages shown, press N to load more" loaded-count)
                                            (format "%d messages, end of list" loaded-count)))))
    (goto-char (point-min))
    (forward-line 4)))

(defun mail-app--format-message-view (message-id account mailbox)
  "Format message view for MESSAGE-ID in ACCOUNT and MAILBOX based on view mode."
  (let* ((output (mail-app--run-command "messages" "show" message-id
                                         "-a" account "-m" mailbox))
         (inhibit-read-only t)
         (view-mode (or mail-app-current-view-mode 'plain))
         (details (mail-app--parse-message-details output)))
    (erase-buffer)
    (insert (propertize (format "%s / %s / Message [%s]\n"
                                account mailbox (symbol-name view-mode))
                        'face 'bold))
    (insert "\n")
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
        (mail-app--insert-content content)))
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
        (mail-app--insert-content content)))
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
    (forward-line 4)))


(provide 'mail-app-display)

;;; mail-app-display.el ends here

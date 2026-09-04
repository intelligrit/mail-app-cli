;;; test-highlight-and-open.el --- Tests for hl-line contrast and CLI open -*- lexical-binding: t -*-

(require 'ert)
(require 'hl-line)
(require 'mail-app-core)
(require 'mail-app-commands)
(require 'mail-app-display)

(ert-deftest mail-app-test-color-luminance-and-dark-p ()
  "Test luminance calculation and dark color predicate."
  (should (mail-app--dark-color-p "black"))
  (should (mail-app--dark-color-p "#000000"))
  (should (mail-app--dark-color-p "dark blue"))
  (should (mail-app--dark-color-p "#1a365d"))
  (should-not (mail-app--dark-color-p "white"))
  (should-not (mail-app--dark-color-p "#ffffff")))

(ert-deftest mail-app-test-get-marked-face-dark-hl-line ()
  "Test that marked face does not produce black text or white background on dark hl-line."
  (cl-letf (((symbol-function 'mail-app--hl-line-dark-p) (lambda () t)))
    (let ((face (mail-app--get-marked-face)))
      ;; Should be a face or plist with light foreground and dark background
      (if (listp face)
          (let ((fg (plist-get face :foreground))
                (bg (plist-get face :background)))
            (should-not (mail-app--dark-color-p fg))
            (should (mail-app--dark-color-p bg)))
        (let ((fg (face-attribute face :foreground nil t))
              (bg (face-attribute face :background nil t)))
          (when (and fg (stringp fg))
            (should-not (mail-app--dark-color-p fg)))
          (when (and bg (stringp bg))
            (should (mail-app--dark-color-p bg))))))))

(ert-deftest mail-app-test-update-line-highlight-overlay ()
  "Test that mail-app--update-line-highlight creates high priority contrast overlay."
  (with-temp-buffer
    (insert "Row 1: Unmarked\n")
    (insert "Row 2: Marked\n")
    (insert "Row 3: Unmarked\n")
    (goto-char (point-min))
    (forward-line 1)
    (put-text-property (line-beginning-position) (line-end-position) 'mail-app-marked t)
    (let ((hl-line-mode t)
          (mail-app--hl-line-contrast-overlay nil))
      (cl-letf (((symbol-function 'mail-app--hl-line-dark-p) (lambda () t))
                ((symbol-function 'mail-app--hl-line-background) (lambda () "dark blue")))
        (mail-app--update-line-highlight)
        (should (overlayp mail-app--hl-line-contrast-overlay))
        (should (= (overlay-get mail-app--hl-line-contrast-overlay 'priority) 100))
        (let ((face (overlay-get mail-app--hl-line-contrast-overlay 'face)))
          (should (equal (plist-get face :foreground) "#ffffff"))
          (should (equal (plist-get face :background) "dark blue")))
        ;; Move to unmarked line
        (forward-line 1)
        (mail-app--update-line-highlight)
        ;; Overlay should be deleted or hidden
        (should-not (and (overlayp mail-app--hl-line-contrast-overlay)
                         (overlay-buffer mail-app--hl-line-contrast-overlay)))))))

(ert-deftest mail-app-test-jump-to-mail-app-cli ()
  "Test that mail-app-jump-to-mail-app delegates to mail-app-cli open."
  (let ((captured-args nil))
    (cl-letf (((symbol-function 'mail-app--run-command-async)
               (lambda (_cb &rest args) (setq captured-args args))))
      ;; Case 1: In message view mode
      (let ((major-mode 'mail-app-message-view-mode)
            (mail-app-current-message-id "msg-123")
            (mail-app-current-account "Skyward")
            (mail-app-current-mailbox "INBOX"))
        (mail-app-jump-to-mail-app)
        (should (equal captured-args '("open" "msg-123" "-a" "Skyward" "-m" "INBOX"))))

      ;; Case 2: In messages mode with mailbox
      (let ((major-mode 'mail-app-messages-mode)
            (mail-app-current-account "Skyward")
            (mail-app-current-mailbox "Archive"))
        (mail-app-jump-to-mail-app)
        (should (equal captured-args '("open" "-a" "Skyward" "-m" "Archive"))))

      ;; Case 3: Default fallback
      (let ((major-mode 'fundamental-mode))
        (mail-app-jump-to-mail-app)
        (should (equal captured-args '("open")))))))

(provide 'test-highlight-and-open)
;;; test-highlight-and-open.el ends here

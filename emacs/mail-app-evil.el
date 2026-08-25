;;; mail-app-evil.el --- Evil mode integration for mail-app -*- lexical-binding: t; no-byte-compile: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1") (evil "1.0"))

;;; Commentary:

;; Evil mode integration for mail-app, providing vim-like keybindings.

;;; Code:

(require 'mail-app-core)
(require 'mail-app-modes)
(require 'mail-app-commands)

(eval-when-compile
  (unless (require 'evil nil 'noerror)
    (error "mail-app-evil requires Evil; install evil before compiling")))

(defun mail-app-evil--setup ()
  "Initialize Evil bindings and state for mail-app buffers."
  (require 'evil)
  ;; Set initial states for all mail-app modes
  (when (fboundp 'evil-set-initial-state)
    (evil-set-initial-state 'mail-app-accounts-mode 'normal)
    (evil-set-initial-state 'mail-app-mailboxes-mode 'normal)
    (evil-set-initial-state 'mail-app-messages-mode 'normal)
    (evil-set-initial-state 'mail-app-message-view-mode 'normal))

  ;; Add hooks to ensure Evil enters normal state immediately
  (add-hook 'mail-app-accounts-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-mailboxes-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-messages-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-message-view-mode-hook 'evil-normal-state)

  ;; Use evil-local-set-key in mode hooks for highest-priority RET bindings.
  ;; evil-define-key on the mode map is sometimes overridden by evil's own
  ;; state maps; buffer-local keys set via evil-local-set-key always win.
  (when (fboundp 'evil-local-set-key)
    (add-hook 'mail-app-accounts-mode-hook
              (lambda ()
                (evil-local-set-key 'normal (kbd "RET") 'mail-app-view-mailboxes-at-point)
                (evil-local-set-key 'motion (kbd "RET") 'mail-app-view-mailboxes-at-point)))
    (add-hook 'mail-app-mailboxes-mode-hook
              (lambda ()
                (evil-local-set-key 'normal (kbd "RET") 'mail-app-view-messages-at-point)
                (evil-local-set-key 'motion (kbd "RET") 'mail-app-view-messages-at-point)))
    (add-hook 'mail-app-messages-mode-hook
              (lambda ()
                (evil-local-set-key 'normal (kbd "RET") 'mail-app-view-message-at-point)
                (evil-local-set-key 'motion (kbd "RET") 'mail-app-view-message-at-point)))
    (add-hook 'mail-app-message-view-mode-hook
              (lambda ()
                (evil-local-set-key 'normal (kbd "RET") 'mail-app-save-attachment-at-point)
                (evil-local-set-key 'motion (kbd "RET") 'mail-app-save-attachment-at-point))))

  ;; Define evil keybindings
  (when (fboundp 'evil-define-key)
    (evil-define-key '(normal motion) mail-app-accounts-mode-map
      (kbd "RET") 'mail-app-view-mailboxes-at-point
      "c" 'mail-app-compose
      "J" 'mail-app-jump-to-mail-app
      "o" 'mail-app-toggle-accounts-sort
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "S" 'mail-app-search-all
      ;; Unified mailbox shortcuts
      "I" 'mail-app-list-inbox
      "U" 'mail-app-list-unread
      "G" 'mail-app-list-sent
      "D" 'mail-app-list-drafts
      "*" 'mail-app-list-flagged
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key '(normal motion) mail-app-mailboxes-mode-map
      (kbd "RET") 'mail-app-view-messages-at-point
      "c" 'mail-app-compose
      "J" 'mail-app-jump-to-mail-app
      "o" 'mail-app-toggle-mailboxes-sort
      "T" 'mail-app-mark-mailbox-as-read
      "R" 'mail-app-mark-special-read
      "g" nil
      "gr" 'mail-app-refresh
      "r" 'mail-app-refresh
      "s" 'mail-app-search
      "S" 'mail-app-search-all
      ;; Unified mailbox shortcuts
      "I" 'mail-app-list-inbox
      "U" 'mail-app-list-unread
      "G" 'mail-app-list-sent
      "D" 'mail-app-list-drafts
      "*" 'mail-app-list-flagged
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key '(normal motion) mail-app-messages-mode-map
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
      "F" 'mail-app-forward-message-at-point
      "d" 'mail-app-delete-message-at-point
      "a" 'mail-app-archive-message-at-point
      "!" 'mail-app-junk-message-at-point
      "v" 'mail-app-move-message-at-point
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
      ",!" 'mail-app-junk-marked
      ",v" 'mail-app-move-marked
      ",r" 'mail-app-mark-marked-as-read
      ",u" 'mail-app-mark-marked-as-unread
      "q" 'quit-window
      "ZZ" 'quit-window
      "ZQ" 'quit-window
      "?" 'describe-mode)

    (evil-define-key '(normal motion) mail-app-message-view-mode-map
      (kbd "RET") 'mail-app-save-attachment-at-point
      "r" 'mail-app-reply-current-message
      "R" 'mail-app-reply-all-current-message
      "F" 'mail-app-forward-current-message
      (kbd "TAB") 'mail-app-cycle-view
      (kbd "<backtab>") 'mail-app-cycle-view-reverse
      "b" 'mail-app-jump-to-body
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
      "?" 'describe-mode)

    ;; Remap Evil's RET command to the appropriate mail-app action
    (define-key mail-app-accounts-mode-map [remap evil-ret] #'mail-app-view-mailboxes-at-point)
    (define-key mail-app-mailboxes-mode-map [remap evil-ret] #'mail-app-view-messages-at-point)
    (define-key mail-app-messages-mode-map [remap evil-ret] #'mail-app-view-message-at-point)
    (define-key mail-app-message-view-mode-map [remap evil-ret] #'mail-app-save-attachment-at-point))

  ;; Force Evil to update keymaps once bindings are defined
  (when (fboundp 'evil-normalize-keymaps)
    (evil-normalize-keymaps)))

(if (featurep 'evil)
    (mail-app-evil--setup)
  (with-eval-after-load 'evil
    (mail-app-evil--setup)))

(provide 'mail-app-evil)

;;; mail-app-evil.el ends here

;;; mail-app-evil.el --- Evil mode integration for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1") (evil "1.0"))

;;; Commentary:

;; Evil mode integration for mail-app, providing vim-like keybindings.

;;; Code:

(require 'mail-app-core)
(require 'mail-app-modes)
(require 'mail-app-commands)

;;; Evil mode integration

;; Only configure Evil if it's actually loaded
(when (fboundp 'evil-define-key)

  ;; Set initial states for all mail-app modes
  (evil-set-initial-state 'mail-app-accounts-mode 'normal)
  (evil-set-initial-state 'mail-app-mailboxes-mode 'normal)
  (evil-set-initial-state 'mail-app-messages-mode 'normal)
  (evil-set-initial-state 'mail-app-message-view-mode 'normal)

  ;; Add hooks to ensure Evil enters normal state immediately
  (add-hook 'mail-app-accounts-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-mailboxes-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-messages-mode-hook 'evil-normal-state)
  (add-hook 'mail-app-message-view-mode-hook 'evil-normal-state)

  ;; Define evil keybindings for accounts mode (both normal and motion state)
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
		 "q" 'quit-window
		 "ZZ" 'quit-window
		 "ZQ" 'quit-window
		 "?" 'describe-mode)

(evil-define-key '(normal motion) mail-app-mailboxes-mode-map
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

  ;; Force Evil to update keymaps
  (evil-normalize-keymaps))

(provide 'mail-app-evil)

;;; mail-app-evil.el ends here

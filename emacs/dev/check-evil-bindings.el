;;; check-evil-bindings.el --- Verify Evil RET bindings -*- lexical-binding: t -*-

;;; Commentary:
;; Run via: emacs -Q --batch -L .. -l dev/check-evil-bindings.el
;; Ensures Evil's RET invocation maps to the correct mail-app action
;; in every major mode.

(setq debug-on-error t)

(defvar mail-app-check-base-dir
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "Top-level mail-app directory.")

(add-to-list 'load-path mail-app-check-base-dir)

(unless (require 'evil nil 'noerror)
  (error "Evil is not available; install/require it before running this check"))

(require 'mail-app)
(evil-mode 1)

(defconst mail-app-check--specs
  '((mail-app-accounts-mode mail-app-accounts-mode-map mail-app-view-mailboxes-at-point)
    (mail-app-mailboxes-mode mail-app-mailboxes-mode-map mail-app-view-messages-at-point)
    (mail-app-messages-mode mail-app-messages-mode-map mail-app-view-message-at-point)
    (mail-app-message-view-mode mail-app-message-view-mode-map mail-app-save-attachment-at-point))
  "Mode/keymap/RET-command triples for Evil verification.")

(defun mail-app-check--assert (pred fmt &rest args)
  "Raise an error if PRED is nil."
  (unless pred
    (apply #'error fmt args)))

(dolist (spec mail-app-check--specs)
  (pcase-let ((`(,mode ,map-sym ,expected) spec))
    (let ((map (symbol-value map-sym)))
      (mail-app-check--assert (eq (lookup-key map [remap evil-ret]) expected)
                              "Map %s missing evil-ret remap to %s"
                              map-sym expected))
    (with-temp-buffer
      (funcall mode)
      (evil-local-mode 1)
      (setq evil-state 'normal)
      (mail-app-check--assert (eq (key-binding (kbd "RET")) expected)
                              "RET resolves to %s instead of %s in %s"
                              (key-binding (kbd "RET")) expected mode))))

(message "mail-app Evil RET bindings OK")

;;; check-evil-bindings.el ends here

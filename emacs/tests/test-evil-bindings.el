;;; test-evil-bindings.el --- Tests for Evil bindings -*- lexical-binding: t -*-

(require 'ert)

(defvar mail-app-test-base-dir
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name (buffer-file-name))))
  "Base directory of the project.")

(add-to-list 'load-path mail-app-test-base-dir)

(require 'mail-app)

(defvar mail-app-test-evil-available (require 'evil nil 'noerror)
  "Non-nil when Evil can be loaded for binding tests.")

(when mail-app-test-evil-available
  (evil-mode 1))

(defconst mail-app-test--evil-maps
  '((mail-app-accounts-mode mail-app-accounts-mode-map mail-app-view-mailboxes-at-point)
    (mail-app-mailboxes-mode mail-app-mailboxes-mode-map mail-app-view-messages-at-point)
    (mail-app-messages-mode mail-app-messages-mode-map mail-app-view-message-at-point)
    (mail-app-message-view-mode mail-app-message-view-mode-map mail-app-save-attachment-at-point))
  "Mode/keymap/command triples for verifying Evil RET remaps.")

(ert-deftest mail-app-evil-ret-remaps-exist ()
  "RET should be remapped for every mail-app mode."
  (unless mail-app-test-evil-available
    (ert-skip "Evil not available in batch Emacs"))
  (dolist (spec mail-app-test--evil-maps)
    (let* ((map (symbol-value (nth 1 spec)))
           (expected (nth 2 spec)))
      (should (eq (lookup-key map [remap evil-ret]) expected)))))

(ert-deftest mail-app-evil-ret-invokes-action ()
  "Pressing RET in Evil normal state should call the correct command."
  (unless mail-app-test-evil-available
    (ert-skip "Evil not available in batch Emacs"))
  (dolist (spec mail-app-test--evil-maps)
    (let ((mode (nth 0 spec))
          (expected (nth 2 spec)))
      (with-temp-buffer
        (funcall mode)
        (evil-local-mode 1)
        (setq evil-state 'normal)
        (should (eq (key-binding (kbd "RET")) expected))))))

(provide 'test-evil-bindings)
;;; test-evil-bindings.el ends here

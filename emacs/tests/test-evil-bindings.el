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

(ert-deftest mail-app-junk-bindings-in-all-message-views ()
  "Junk must override Evil's shell operator and work without Evil."
  (dolist (spec '((mail-app-messages-mode mail-app-junk-message-at-point)
                  (mail-app-thread-list-mode mail-app-junk-thread-at-point)
                  (mail-app-message-view-mode mail-app-junk-current-message)))
    (dolist (state (if mail-app-test-evil-available '(nil normal motion) '(nil)))
      (with-temp-buffer
        (funcall (car spec))
        (when mail-app-test-evil-available
          (if state
              (progn (evil-local-mode 1) (evil-change-state state))
            (evil-local-mode -1)))
        (should (eq (key-binding "!") (cadr spec)))))))

(ert-deftest mail-app-junk-thread-uses-selected-scope ()
  "Junk only the messages returned by the thread scope selector."
  (with-temp-buffer
    (insert (propertize "Thread" 'mail-app-thread-data
                        '(:all-messages ((:id "1") (:id "2")))))
    (goto-char (point-min))
    (let (captured)
      (cl-letf (((symbol-function 'mail-app--thread-action-scope)
                 (lambda (_thread _verb) '((:id "2"))))
                ((symbol-function 'mail-app--act-on-messages)
                 (lambda (&rest args) (setq captured args))))
        (mail-app-junk-thread-at-point)
        (should (equal captured
                       '(((:id "2")) "Marking as junk" "Junked" nil
                         "messages" "move" :after "@junk")))))))

(ert-deftest mail-app-junk-current-uses-current-id ()
  "Junk the open message using its global ID."
  (with-temp-buffer
    (setq-local mail-app-current-message-id "42")
    (let (captured)
      (cl-letf (((symbol-function 'mail-app--speak) #'ignore)
                ((symbol-function 'mail-app--run-mutation-async)
                 (lambda (ids _callback &rest args)
                   (setq captured (cons ids args)))))
        (mail-app-junk-current-message)
        (should (equal captured '(("42") "messages" "move" :after "@junk")))))))

(provide 'test-evil-bindings)
;;; test-evil-bindings.el ends here

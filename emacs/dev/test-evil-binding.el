;;; test-evil-binding.el --- Test Evil bindings for mail-app

;; Test script to diagnose the RET binding issue

(require 'mail-app)

(defun test-mail-app-bindings ()
  "Test if Evil bindings are working correctly."
  (interactive)
  (with-current-buffer (get-buffer-create "*Mail App Binding Test*")
    (mail-app-accounts-mode)

    (let ((results '()))
      ;; Test 1: Check if mode is set
      (push (format "Major mode: %s" major-mode) results)

      ;; Test 2: Check base keymap binding
      (let ((base-binding (lookup-key mail-app-accounts-mode-map (kbd "RET"))))
        (push (format "Base keymap RET: %s" base-binding) results))

      ;; Test 3: Check if Evil is loaded
      (push (format "Evil loaded: %s" (featurep 'evil)) results)

      ;; Test 4: Check Evil state (if Evil is loaded)
      (when (boundp 'evil-state)
        (push (format "Evil state: %s" evil-state) results))

      ;; Test 5: Check what RET actually does in current context
      (when (fboundp 'evil-define-key)
        (let ((evil-binding (lookup-key (current-local-map) (kbd "RET"))))
          (push (format "Effective RET binding: %s" evil-binding) results)))

      ;; Display results
      (switch-to-buffer (get-buffer-create "*Binding Test Results*"))
      (erase-buffer)
      (insert "=== Mail-App Evil Binding Test ===\n\n")
      (dolist (result (nreverse results))
        (insert result "\n"))
      (insert "\n--- End of test ---\n")
      (goto-char (point-min)))))

(message "Test loaded. Run M-x test-mail-app-bindings")

;;; test-evil-binding.el ends here

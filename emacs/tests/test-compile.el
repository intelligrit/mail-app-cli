;;; test-compile.el --- Verify all source files compile -*- lexical-binding: t -*-

(require 'ert)

(defvar mail-app-test-source-files
  '("mail-app-core.el"
    "mail-app-modes.el"
    "mail-app-display.el"
    "mail-app-commands.el"
    "mail-app-evil.el"
    "mail-app-emacspeak.el"
    "mail-app.el")
  "List of source files to test for compilation.")

;; Adjusting base-dir logic to be robust when run from different contexts
(defvar mail-app-test-base-dir
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name (buffer-file-name))))
  "Base directory of the project.")

(ert-deftest mail-app-compile-all-files ()
  "Test that all source files compile without errors."
  (let ((load-path (cons mail-app-test-base-dir load-path)))
    (dolist (file mail-app-test-source-files)
      (let* ((full-path (expand-file-name file mail-app-test-base-dir))
             (byte-compile-dest-file nil) ; Don't actually write .elc file
             (compilation-result (byte-compile-file full-path)))
        (message "Compiling %s... Result: %S" file compilation-result)
        (should-not (eq compilation-result 'error))
        (should compilation-result)))))

(ert-deftest mail-app-require-all-modules ()
  "Test that all modules can be required successfully."
  (let ((load-path (cons mail-app-test-base-dir load-path)))
    (dolist (module '(mail-app-core
                      mail-app-modes
                      mail-app-display
                      mail-app-commands
                      mail-app-evil
                      mail-app-emacspeak
                      mail-app))
      (message "Requiring %s..." module)
      (should (require module nil t)))))

(provide 'test-compile)
;;; test-compile.el ends here

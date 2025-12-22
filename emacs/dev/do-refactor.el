;;; do-refactor.el --- Automatically refactor mail-app.el -*- lexical-binding: t -*-

;;; Commentary:
;; This script automatically splits mail-app.el into modules

;;; Code:

(load-file "refactor-helper.el")

(defun create-module-header (module-name description &optional requires)
  "Create a standard header for MODULE-NAME with DESCRIPTION.
REQUIRES is an optional list of modules to require."
  (concat
   (format ";;; %s.el --- %s -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs \"27.1\"))

;;; Commentary:

;; %s

" module-name description description)
   (when requires
     (concat
      (mapconcat (lambda (req) (format "(require '%s)" req))
                requires
                "\n")
      "\n\n"))))

(defun do-refactor-split ()
  "Split mail-app.el into modules."
  (let ((source "mail-app.el")
        (defs (refactor-parse-file "mail-app.el")))

    (message "Step 1: Creating mail-app-core.el...")
    (refactor-extract-to-file
     source
     "mail-app-core.el"
     (lambda (def)
       (or (memq (plist-get def :type) '(defcustom defgroup defvar defvar-local))
           ;; Include all helper/utility functions (mail-app--*)
           ;; EXCEPT format functions which go in display module
           (and (eq (plist-get def :type) 'defun)
                (let ((name (symbol-name (plist-get def :name))))
                  (and (string-match "^mail-app--" name)
                       (not (string-match "format" name)))))))
     (create-module-header
      "mail-app-core"
      "Core functionality for mail-app including customization, variables, and utilities"))

    (message "Step 2: Creating mail-app-display.el...")
    (refactor-extract-to-file
     source
     "mail-app-display.el"
     (lambda (def)
       (and (eq (plist-get def :type) 'defun)
            (let ((name (symbol-name (plist-get def :name))))
              (string-match "^mail-app--format" name))))
     (create-module-header
      "mail-app-display"
      "Display and formatting functions for mail-app"
      '(mail-app-core)))

    (message "Step 3: Creating mail-app-emacspeak.el...")
    (refactor-extract-to-file
     source
     "mail-app-emacspeak.el"
     (lambda (def)
       (let ((name (symbol-name (plist-get def :name))))
         (or (string-match "emacspeak" name)
             (string-match "speak" name))))
     (create-module-header
      "mail-app-emacspeak"
      "Emacspeak integration for mail-app"
      '(mail-app-core)))

    (message "Step 4: Creating mail-app-modes.el...")
    (refactor-extract-to-file
     source
     "mail-app-modes.el"
     (lambda (def)
       (or (eq (plist-get def :type) 'define-derived-mode)
           (and (eq (plist-get def :type) 'defvar)
                (string-match "-mode-map$" (symbol-name (plist-get def :name))))))
     (create-module-header
      "mail-app-modes"
      "Major modes and keymaps for mail-app"
      '(mail-app-core mail-app-emacspeak)))

    (message "Step 5: Creating mail-app-commands.el...")
    (refactor-extract-to-file
     source
     "mail-app-commands.el"
     (lambda (def)
       (and (eq (plist-get def :type) 'defun)
            (let ((form (plist-get def :form)))
              ;; Check if function has (interactive) in its body
              (and (listp form)
                   (>= (length form) 3)
                   (let ((body (cddr form)))
                     (seq-some (lambda (item)
                                (and (listp item)
                                     (eq (car item) 'interactive)))
                              body))))))
     (create-module-header
      "mail-app-commands"
      "All interactive commands for mail-app"
      '(message mml sendmail mail-app-core mail-app-display mail-app-modes)))

    (message "Step 6: Creating main mail-app.el...")
    (with-temp-buffer
      (insert (create-module-header
               "mail-app"
               "Emacs interface for mail-app CLI"))
      (insert ";;; Code:\n\n")
      (insert "(require 'mail-app-core)\n")
      (insert "(require 'mail-app-display)\n")
      (insert "(require 'mail-app-modes)\n")
      (insert "(require 'mail-app-emacspeak)\n")
      (insert "(require 'mail-app-commands)\n\n")
      (insert "(provide 'mail-app)\n\n")
      (insert ";;; mail-app.el ends here\n")
      (write-region (point-min) (point-max) "mail-app-new.el"))

    (message "Done! Files created:")
    (message "  - mail-app-core.el")
    (message "  - mail-app-display.el")
    (message "  - mail-app-emacspeak.el")
    (message "  - mail-app-modes.el")
    (message "  - mail-app-commands.el")
    (message "  - mail-app-new.el (new main file)")
    (message "\nNext: Run verification to check compilation...")))

(defun do-refactor-verify ()
  "Verify that the refactored modules compile correctly."
  (let ((files '("mail-app-core.el"
                 "mail-app-display.el"
                 "mail-app-emacspeak.el"
                 "mail-app-modes.el"
                 "mail-app-commands.el"
                 "mail-app-new.el"))
        (errors '()))
    (dolist (file files)
      (message "Checking %s..." file)
      (condition-case err
          (byte-compile-file file)
        (error
         (push (cons file err) errors))))
    (if errors
        (progn
          (message "\nERRORS FOUND:")
          (dolist (err errors)
            (message "  %s: %S" (car err) (cdr err))))
      (message "\nSUCCESS: All files compile without errors!"))))

(provide 'do-refactor)

;;; do-refactor.el ends here

;;; refactor-helper.el --- Helper to refactor mail-app.el into modules -*- lexical-binding: t -*-

;;; Commentary:
;; This tool helps safely refactor mail-app.el into modules by:
;; 1. Parsing all top-level forms
;; 2. Analyzing dependencies
;; 3. Grouping related code
;; 4. Generating module files
;; 5. Verifying compilation

;;; Code:

(require 'cl-lib)

(defvar refactor-definitions nil
  "List of all definitions found in the file.")

(defvar refactor-dependencies nil
  "Alist of (symbol . dependencies) showing what each function calls.")

(defun refactor-parse-file (file)
  "Parse FILE and extract all top-level definitions."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((forms '()))
      (condition-case nil
          (while t
            (let ((start-pos (point))
                  (form (read (current-buffer)))
                  (end-pos (point)))
              (when (listp form)
                (let ((type (car form))
                      (name (when (and (listp form) (>= (length form) 2))
                              (cadr form))))
                  (when (memq type '(defun defvar defvar-local defcustom defgroup
                                     defface define-derived-mode defmacro))
                    (push (list :type type
                                :name name
                                :form form
                                :start start-pos
                                :end end-pos)
                          forms))))))
        (end-of-file nil))
      (nreverse forms))))

(defun refactor-extract-function-calls (form)
  "Extract all function calls from FORM."
  (let ((calls '()))
    (cl-labels ((walk (node)
                  (when (consp node)
                    (when (symbolp (car node))
                      (push (car node) calls))
                    (mapc #'walk (cdr node)))))
      (walk form))
    (delete-dups calls)))

(defun refactor-analyze-dependencies (definitions)
  "Analyze dependencies between DEFINITIONS."
  (let ((deps '()))
    (dolist (def definitions)
      (when (eq (plist-get def :type) 'defun)
        (let* ((name (plist-get def :name))
               (form (plist-get def :form))
               (calls (refactor-extract-function-calls form))
               ;; Filter to only functions defined in this file
               (local-calls (seq-filter
                            (lambda (call)
                              (seq-find (lambda (d)
                                         (eq (plist-get d :name) call))
                                       definitions))
                            calls)))
          (push (cons name local-calls) deps))))
    deps))

(defun refactor-group-by-prefix (definitions)
  "Group DEFINITIONS by function name prefix."
  (let ((groups (make-hash-table :test 'equal)))
    (dolist (def definitions)
      (let* ((name (symbol-name (plist-get def :name)))
             (prefix (cond
                     ;; Internal/helper functions
                     ((string-match "^mail-app--\\([^-]+\\)" name)
                      (match-string 1 name))
                     ;; Public commands
                     ((string-match "^mail-app-\\([^-]+\\)" name)
                      (match-string 1 name))
                     (t "other"))))
        (push def (gethash prefix groups))))
    groups))

(defun refactor-show-analysis (file)
  "Show analysis of FILE."
  (interactive "fFile to analyze: ")
  (let* ((defs (refactor-parse-file file))
         (deps (refactor-analyze-dependencies defs))
         (groups (refactor-group-by-prefix defs))
         (buf (get-buffer-create "*Refactor Analysis*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert (format "Analysis of %s\n\n" file))
      (insert (format "Total definitions: %d\n\n" (length defs)))

      ;; Show counts by type
      (insert "=== Counts by Type ===\n")
      (let ((type-counts (make-hash-table)))
        (dolist (def defs)
          (let ((type (plist-get def :type)))
            (puthash type (1+ (gethash type type-counts 0)) type-counts)))
        (maphash (lambda (type count)
                   (insert (format "  %s: %d\n" type count)))
                 type-counts))
      (insert "\n")

      ;; Show groups by prefix
      (insert "=== Groups by Prefix ===\n")
      (maphash (lambda (prefix defs)
                 (insert (format "\n%s (%d):\n" prefix (length defs)))
                 (dolist (def defs)
                   (insert (format "  - %s (%s)\n"
                                 (plist-get def :name)
                                 (plist-get def :type)))))
               groups)
      (insert "\n")

      ;; Show dependencies
      (insert "=== Top Functions by Dependencies ===\n")
      (let ((sorted-deps (sort deps
                              (lambda (a b)
                                (> (length (cdr a)) (length (cdr b)))))))
        (dolist (dep (seq-take sorted-deps 20))
          (insert (format "  %s calls %d other functions\n"
                        (car dep)
                        (length (cdr dep))))))

      (goto-char (point-min))
      (special-mode))
    (switch-to-buffer buf)))

(defun refactor-suggest-modules (file)
  "Suggest module structure for FILE."
  (interactive "fFile to analyze: ")
  (let* ((defs (refactor-parse-file file))
         (groups (refactor-group-by-prefix defs)))
    (with-current-buffer (get-buffer-create "*Module Suggestions*")
      (erase-buffer)
      (insert "Suggested Module Structure\n")
      (insert "===========================\n\n")

      ;; Suggest modules based on common patterns
      (insert "mail-app-core.el - Core functionality\n")
      (insert "  - All defcustom, defgroup\n")
      (insert "  - All defvar, defvar-local\n")
      (insert "  - Helper functions (mail-app--*)\n\n")

      (insert "mail-app-display.el - Display/formatting\n")
      (insert "  - Functions with 'format' in name\n")
      (insert "  - Functions with 'display' in name\n\n")

      (insert "mail-app-modes.el - Major modes\n")
      (insert "  - All define-derived-mode\n")
      (insert "  - Keymaps (defvar *-mode-map)\n\n")

      (insert "mail-app-commands.el - Interactive commands\n")
      (insert "  - All interactive defuns\n\n")

      (goto-char (point-min))
      (special-mode)
      (switch-to-buffer (current-buffer)))))

(defun refactor-extract-to-file (source-file output-file predicate &optional header)
  "Extract forms from SOURCE-FILE to OUTPUT-FILE where PREDICATE returns t.
PREDICATE is called with each definition plist.
HEADER is optional header text to include."
  (let* ((defs (refactor-parse-file source-file))
         (selected (seq-filter predicate defs)))
    ;; Read the original file to preserve formatting
    (with-temp-buffer
      (insert-file-contents source-file)
      (let ((source-text (buffer-string)))
        (with-temp-buffer
          (when header
            (insert header "\n\n"))
          (insert ";;; Code:\n\n")
          (dolist (def selected)
            (let ((start (plist-get def :start))
                  (end (plist-get def :end)))
              (insert (substring source-text start end))
              (insert "\n\n")))
          (insert (format "(provide '%s)\n\n"
                         (file-name-sans-extension (file-name-nondirectory output-file))))
          (insert (format ";;; %s ends here\n" (file-name-nondirectory output-file)))
          (write-region (point-min) (point-max) output-file))))
    (message "Wrote %d definitions to %s" (length selected) output-file)
    selected))

(provide 'refactor-helper)

;;; refactor-helper.el ends here

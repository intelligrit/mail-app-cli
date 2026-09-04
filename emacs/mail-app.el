;;; mail-app.el --- Emacs front-end for mail-app-cli -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: mail, tools

;;; Commentary:

;; This file is the main entry point for mail-app.
;; It loads the modularized components of the application.
;;
;; Previous monolithic version has been backed up to mail-app.el.monolithic_backup

;;; Code:

;; Core functionality and variables
(require 'mail-app-core)

;; Major modes and keymaps
(require 'mail-app-modes)

;; Display and formatting
(require 'mail-app-display)

;; Interactive commands
(require 'mail-app-commands)

;; Optional Integrations
;; These files contain internal checks (e.g. fboundp) to only activate 
;; if the corresponding subsystem (Evil, Emacspeak) is present.
(require 'mail-app-evil)
(require 'mail-app-emacspeak)

(provide 'mail-app)

;;; mail-app.el ends here

;;; signatures-example.el --- Example signature configuration for mail-app

;; This file shows examples of how to configure per-account signatures
;; for mail-app-wrap.

;; Add this to your init.el or customize via M-x customize-group mail-app

;;; Example 1: Simple string signatures
(setq mail-app-signatures
      '(("Skyward" . "--\nRobert Melton\nSEAS IT Program Tech Lead\nSkyward | Serving CMS\ne: rmelton@skywarditsolutions.com\np: +1 202 525 6382")
        ("Gmail" . "--\nRobert Melton")
        ("Fastmail" . "--\nBest regards,\nRobert")))

;;; Example 2: File-based signatures
;; (setq mail-app-signatures
;;       '(("Skyward" . "~/signatures/skyward.txt")
;;         ("Gmail" . "~/signatures/personal.txt")
;;         ("Fastmail" . "~/signatures/fastmail.txt")))

;;; Example 3: Function-based signatures (dynamic)
;; (defun my-skyward-signature ()
;;   "Generate Skyward signature with current date."
;;   (format "--\nRobert Melton\nSkyward IT\nDate: %s" (format-time-string "%Y-%m-%d")))
;;
;; (setq mail-app-signatures
;;       '(("Skyward" . my-skyward-signature)
;;         ("Gmail" . "~/signatures/gmail.txt")))

;;; Example 4: Mixed approaches
;; (setq mail-app-signatures
;;       '(("Skyward" . my-skyward-signature)  ; Function
;;         ("Gmail" . "~/signatures/gmail.txt") ; File
;;         ("Fastmail" . "--\nRobert")))        ; String

;;; signatures-example.el ends here

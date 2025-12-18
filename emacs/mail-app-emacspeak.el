;;; mail-app-emacspeak.el --- Emacspeak integration for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Emacspeak integration for mail-app

(require 'mail-app-core)



;;; Code:


;;; Emacspeak integration

(defun mail-app--speak (text &optional icon)
  "Speak TEXT using Emacspeak.
Optionally play audio ICON."
  (when (featurep 'emacspeak)
    (when icon
      (emacspeak-icon icon))
    (dtk-speak text)))



(defun mail-app--emacspeak-speak-line ()
  "Custom Emacspeak line speaking for mail-app."
  (when (featurep 'emacspeak)
    (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
      (when speech-text
        (dtk-speak speech-text)))))



(defun mail-app--emacspeak-post-command ()
  "Emacspeak post-command hook for mail-app modes."
  (when (and (featurep 'emacspeak)
             (memq this-command '(next-line previous-line evil-next-line evil-previous-line
                                  mail-app-toggle-mark-at-point mail-app-toggle-mark-backward)))
    (mail-app--emacspeak-speak-line)))


(provide 'mail-app-emacspeak)

;;; mail-app-emacspeak.el ends here

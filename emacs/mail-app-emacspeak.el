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
             (memq this-command '(next-line previous-line evil-next-line evil-previous-line)))
    (mail-app--emacspeak-speak-line)))



;;; Advise emacspeak-speak-line to use our custom property
;;
;; Emacspeak advises navigation commands and calls emacspeak-speak-line after
;; movement.  That function reads the raw buffer text, which causes characters
;; like ● to be spoken as "black circle".  We intercept the call and use the
;; 'emacspeak-speak text property we set on every line instead.

(defun mail-app--emacspeak-speak-line-override (orig-fn &rest args)
  "Use mail-app 'emacspeak-speak property when in a mail-app buffer.
Falls back to ORIG-FN for non-mail-app buffers."
  (if (and (memq major-mode '(mail-app-accounts-mode
                              mail-app-mailboxes-mode
                              mail-app-messages-mode
                              mail-app-thread-list-mode
                              mail-app-message-view-mode))
           (get-text-property (point) 'emacspeak-speak))
      (dtk-speak (get-text-property (point) 'emacspeak-speak))
    (apply orig-fn args)))

(defun mail-app--install-emacspeak-advice ()
  "Install advice on emacspeak-speak-line if emacspeak is available."
  (when (fboundp 'emacspeak-speak-line)
    (advice-add 'emacspeak-speak-line :around
                #'mail-app--emacspeak-speak-line-override
                '((name . mail-app-override)))))

(if (featurep 'emacspeak)
    (mail-app--install-emacspeak-advice)
  (with-eval-after-load 'emacspeak-speak
    (mail-app--install-emacspeak-advice)))


(provide 'mail-app-emacspeak)

;;; mail-app-emacspeak.el ends here

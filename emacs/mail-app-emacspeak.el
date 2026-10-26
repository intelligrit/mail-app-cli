;;; mail-app-emacspeak.el --- Speech integration for mail-app -*- lexical-binding: t -*-

;; Author: Robert Melton
;; Version: 1.0
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:

;; Prefer Emacsvox when loaded, with Emacspeak as a fallback.  Keep the
;; existing helper and text-property names for compatibility with mail-app.

(require 'mail-app-core)

(declare-function emacsvox-icon "emacsvox-sounds" (icon))
(declare-function tts-speak "tts-speak" (text))
(declare-function emacspeak-icon "emacspeak-sounds" (icon))
(declare-function dtk-speak "dtk-speak" (text))



;;; Code:


;;; Speech integration

(defun mail-app--speak (text &optional icon)
  "Speak TEXT using the loaded Emacsvox or Emacspeak backend.
Optionally play audio ICON."
  (cond
   ((featurep 'emacsvox)
    (when icon (emacsvox-icon icon))
    (tts-speak text))
   ((featurep 'emacspeak)
    (when icon (emacspeak-icon icon))
    (dtk-speak text))))



(defun mail-app--emacspeak-speak-line ()
  "Speak mail-app's accessible summary for the current line."
  (let ((speech-text (get-text-property (point) 'emacspeak-speak)))
    (when speech-text
      (mail-app--speak speech-text))))



(defun mail-app--emacspeak-post-command ()
  "Speak line navigation in mail-app modes using the loaded backend."
  (when (and (or (featurep 'emacsvox) (featurep 'emacspeak))
             (memq this-command '(next-line previous-line evil-next-line evil-previous-line)))
    (mail-app--emacspeak-speak-line)))



;;; Advise speech line readers to use our custom property
;;
;; Emacspeak advises navigation commands and calls emacspeak-speak-line after
;; movement.  That function reads the raw buffer text, which causes characters
;; like ● to be spoken as "black circle".  We intercept the call and use the
;; 'emacspeak-speak text property we set on every line instead.

(defun mail-app--emacspeak-speak-line-override (orig-fn &rest args)
  "Use the accessible summary in mail-app buffers.
Call ORIG-FN with ARGS in other buffers."
  (if (and (memq major-mode '(mail-app-accounts-mode
                              mail-app-mailboxes-mode
                              mail-app-messages-mode
                              mail-app-thread-list-mode
                              mail-app-message-view-mode))
           (get-text-property (point) 'emacspeak-speak))
      (mail-app--speak (get-text-property (point) 'emacspeak-speak))
    (apply orig-fn args)))

(defun mail-app--install-emacspeak-advice ()
  "Install summary-reading advice on available speech backends."
  (dolist (reader '(emacsvox-speak-line emacspeak-speak-line))
    (when (and (fboundp reader)
               (not (advice-member-p
                     #'mail-app--emacspeak-speak-line-override reader)))
      (advice-add reader :around
                  #'mail-app--emacspeak-speak-line-override
                  '((name . mail-app-override))))))

(mail-app--install-emacspeak-advice)
(with-eval-after-load 'emacsvox-speak
  (mail-app--install-emacspeak-advice))
(with-eval-after-load 'emacspeak-speak
  (mail-app--install-emacspeak-advice))


(provide 'mail-app-emacspeak)

;;; mail-app-emacspeak.el ends here

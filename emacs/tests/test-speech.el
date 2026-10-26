;;; test-speech.el --- Speech backend tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(defvar features)
(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'mail-app-emacspeak)

(ert-deftest mail-app-speech-prefers-emacsvox ()
  (let ((features (cons 'emacsvox (cons 'emacspeak features)))
        spoken icon)
    (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text)))
              ((symbol-function 'emacsvox-icon) (lambda (value) (setq icon value)))
              ((symbol-function 'dtk-speak) (lambda (&rest _) (ert-fail "Old backend"))))
      (mail-app--speak "Message opened" 'open-object)
      (should (equal spoken "Message opened"))
      (should (eq icon 'open-object)))))

(ert-deftest mail-app-speech-falls-back-to-emacspeak ()
  (let ((features (cons 'emacspeak (remq 'emacsvox features)))
        spoken icon)
    (cl-letf (((symbol-function 'dtk-speak) (lambda (text) (setq spoken text)))
              ((symbol-function 'emacspeak-icon) (lambda (value) (setq icon value))))
      (mail-app--speak "Message opened" 'open-object)
      (should (equal spoken "Message opened"))
      (should (eq icon 'open-object)))))

(ert-deftest mail-app-speech-without-backend-is-silent ()
  (let ((features (remq 'emacsvox (remq 'emacspeak features))))
    (cl-letf (((symbol-function 'tts-speak) (lambda (&rest _) (ert-fail "Speech")))
              ((symbol-function 'dtk-speak) (lambda (&rest _) (ert-fail "Speech"))))
      (should-not (mail-app--speak "Message opened" 'open-object)))))

(ert-deftest mail-app-speech-reads-summary-instead-of-display-symbols ()
  (let ((features (cons 'emacsvox features)) spoken)
    (with-temp-buffer
      (insert (propertize "● Subject" 'emacspeak-speak "Unread message: Subject"))
      (goto-char (point-min))
      (setq major-mode 'mail-app-messages-mode)
      (cl-letf (((symbol-function 'tts-speak) (lambda (text) (setq spoken text))))
        (mail-app--emacspeak-speak-line-override
         (lambda (&rest _) (ert-fail "Raw display text")))
        (should (equal spoken "Unread message: Subject"))))))

(ert-deftest mail-app-speech-preserves-reader-outside-mail ()
  (with-temp-buffer
    (insert (propertize "Text" 'emacspeak-speak "Mail summary"))
    (goto-char (point-min))
    (should (equal (mail-app--emacspeak-speak-line-override #'list 1 2) '(1 2)))))

(ert-deftest mail-app-speech-advice-supports-late-load-and-repeated-setup ()
  (cl-letf (((symbol-function 'emacsvox-speak-line) #'ignore))
    (mail-app--install-emacspeak-advice)
    (mail-app--install-emacspeak-advice)
    (let ((count 0))
      (advice-mapc (lambda (function _props)
                    (when (eq function #'mail-app--emacspeak-speak-line-override)
                      (cl-incf count)))
                  'emacsvox-speak-line)
      (should (= count 1)))))

(provide 'test-speech)
;;; test-speech.el ends here

;;; test-send.el --- Tests for mail-app-send-message -*- lexical-binding: t -*-

(require 'ert)
(require 'mail-app-commands)

(ert-deftest mail-app-test-body-extraction ()
  "Test that mail-app-send-message correctly extracts the body."
  (let ((body-text ""))
    (with-temp-buffer
      (insert "To: test@example.com\nSubject: Test\n--text follows this line--\nThis is the body.\n<#part filename=\"test.txt\"><#/part>\n")
      (let* ((body-start (save-excursion
                           (goto-char (point-min))
                           (search-forward mail-header-separator nil t)
                           (forward-line 1)
                           (point)))
             (raw-body (buffer-substring-no-properties body-start (point-max))))
        (setq body-text 
              (with-temp-buffer
                (insert raw-body)
                (goto-char (point-min))
                (while (re-search-forward "<#part[^>]+disposition=attachment[^>]*>.*?<#/part>" nil t)
                  (replace-match ""))
                (goto-char (point-min))
                (while (re-search-forward "<#/?\\(multipart\\|part\\)[^>]*>" nil t)
                  (replace-match ""))
                (buffer-substring-no-properties (point-min) (point-max))))))
    (should (string-match-p "This is the body." body-text))))

(ert-deftest mail-app-test-send-message-args ()
  "Test that mail-app-send-message passes -f and -a correctly."
  (let ((captured-args nil)
        (mail-app-identities
         '((:name "Work" :email "work@example.com" :full-name "Worker" :account "WorkAcc")))
        (mail-app-auto-discover-identities nil))
    (cl-letf (((symbol-function 'mail-app--run-command)
               (lambda (&rest args) (setq captured-args args))))
      (with-temp-buffer
        (insert "To: recipient@example.com\nSubject: Test Subject\n--text follows this line--\nHello World\n")
        (message-mode)
        (mail-app-apply-identity (car mail-app-identities))
        (mail-app-send-message)
        (should (equal captured-args
                       '("send" "-s" "Test Subject" "--body" "Hello World"
                         "-a" "WorkAcc" "-f" "Worker <work@example.com>"
                         "-t" "recipient@example.com")))))))

(provide 'test-send)
;;; test-send.el ends here

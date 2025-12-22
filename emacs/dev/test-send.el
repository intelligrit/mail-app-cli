;;; test-send.el --- Test mail-app send functionality

(defun test-mail-app-send ()
  "Test sending an email via mail-app-cli."
  (interactive)
  (let ((test-buf (get-buffer-create "*Test Mail Send*")))
    (with-current-buffer test-buf
      (erase-buffer)
      (message-mode)
      (insert "From: rmelton@gmail.com\n")
      (insert "To: robert.melton@gmail.com\n")
      (insert "Subject: Test from mail-app-wrap\n")
      (insert "--text follows this line--\n")
      (insert "This is a test message from mail-app send function test.\n")
      (setq-local message-options '((account . "rmelton@gmail.com")))
      (setq-local message-send-mail-function 'mail-app--message-send-mail)
      (goto-char (point-min)))
    (switch-to-buffer test-buf)
    (message "Test buffer ready. Press C-c C-c to send or manually call (mail-app-send-message)")))

(provide 'test-send)

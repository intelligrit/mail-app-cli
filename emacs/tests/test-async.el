;;; test-async.el --- Tests for async command execution -*- lexical-binding: t -*-

(require 'ert)
(require 'mail-app-core)

(ert-deftest mail-app-test-async-execution-success ()
  "Test that mail-app--run-command-async handles successful execution."
  (let* ((mail-app-command "echo")
         (received-output nil)
         (callback-called nil))
    (mail-app--run-command-async
     (lambda (output)
       (setq received-output output)
       (setq callback-called t))
     "test-output")
    
    ;; Wait for the process to finish (with timeout)
    (let ((timeout 2.0)
          (start-time (float-time)))
      (while (and (not callback-called)
                  (< (- (float-time) start-time) timeout))
        (accept-process-output nil 0.1)))
    
    (should callback-called)
    (should (string-match-p "test-output" received-output))))

(ert-deftest mail-app-test-async-buffer-cleanup ()
  "Test that the temporary buffer is cleaned up after async execution."
  (let* ((mail-app-command "echo")
         (callback-called nil)
         (buffers-before (buffer-list)))
    (mail-app--run-command-async
     (lambda (_)
       (setq callback-called t))
     "test")
    
    ;; Wait for completion
    (let ((timeout 2.0)
          (start-time (float-time)))
      (while (and (not callback-called)
                  (< (- (float-time) start-time) timeout))
        (accept-process-output nil 0.1)))
    
    (should callback-called)
    ;; Check if any new " *mail-app-async*" buffers are left behind
    (let ((async-buffers (seq-filter 
                          (lambda (b) (string-prefix-p " *mail-app-async*" (buffer-name b)))
                          (buffer-list))))
      (should (null async-buffers)))))

(provide 'test-async)
;;; test-async.el ends here

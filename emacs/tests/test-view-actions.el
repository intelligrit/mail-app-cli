;;; test-view-actions.el --- Navigation after archive/junk -*- lexical-binding: t -*-
(require 'ert)
(require 'cl-lib)
(require 'hl-line)
(require 'mail-app-commands)
(require 'mail-app-emacspeak)

(defun mail-app-test--message (id subject &optional account)
  (list :id id :subject subject :from "Sender" :date id
        :message-id (concat "<" id ">") :read t
        :account (or account "Account") :mailbox "INBOX"))

(defmacro mail-app-test--with-action-view (id &rest body)
  (declare (indent 1))
  `(let ((source (generate-new-buffer " *mail-test-source*"))
         (view (generate-new-buffer " *mail-test-view*"))
         (next (generate-new-buffer " *mail-test-next*"))
         callback opened command)
     (unwind-protect
         (save-window-excursion
           (with-current-buffer source
             (setq major-mode 'mail-app-messages-mode)
             (setq-local mail-app-current-account "Account")
             (setq-local mail-app-current-mailbox "INBOX")
             (setq-local mail-app--sort-initialized t)
             (setq-local mail-app-message-sort-key 'subject)
             (setq-local mail-app-message-sort-reverse nil)
             (setq-local mail-app-messages-data
                         (list (mail-app-test--message "3" "C")
                               (mail-app-test--message "1" "A")
                               (mail-app-test--message "2" "B" "Other account"))))
           (switch-to-buffer view)
           (setq major-mode 'mail-app-message-view-mode)
           (setq-local mail-app-current-message-id ,id)
           (setq-local mail-app-current-account "Account")
           (setq-local mail-app-current-mailbox "INBOX")
           (setq-local mail-app-view-source-buffer source)
           (cl-letf (((symbol-function 'mail-app--speak) #'ignore)
                     ((symbol-function 'mail-app--emacspeak-speak-line) #'ignore)
                     ((symbol-function 'mail-app--run-mutation-async)
                      (lambda (ids fn &rest args)
                        (setq callback fn command (cons ids args))))
                     ((symbol-function 'mail-app--run-command-async)
                      (lambda (&rest _) (error "Unexpected CLI read in navigation test")))
                     ((symbol-function 'mail-app-view-message)
                      (lambda (id account mailbox)
                        (setq opened (list 'message id account mailbox (current-buffer)))
                        (switch-to-buffer next)))
                     ((symbol-function 'mail-app-show-thread-view)
                      (lambda (thread)
                        (setq opened (list 'thread thread (current-buffer)))
                        (switch-to-buffer next))))
             (with-current-buffer source (mail-app--format-messages mail-app-messages-data))
             ,@body))
       (dolist (buf (list source view next))
         (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest mail-app-archive-view-advances-in-displayed-order ()
  (mail-app-test--with-action-view "1"
    (mail-app-archive-current-message)
    (should-not opened)
    (funcall callback '(:ok 1))
    (should (equal opened (list 'message "2" "Other account" "INBOX" source)))
    (should-not (buffer-live-p view))
    (with-current-buffer source
      (should (equal (mapcar #'mail-app--entry-message-ids (mail-app--displayed-entries))
                     '(("2") ("3")))))))

(ert-deftest mail-app-junk-view-respects-reverse-sort ()
  (mail-app-test--with-action-view "2"
    (with-current-buffer source
      (setq mail-app-message-sort-reverse t)
      (mail-app--format-messages mail-app-messages-data))
    (mail-app-junk-current-message)
    (should (equal command '(("2") "messages" "move" :after "@junk")))
    (funcall callback '(:ok 1))
    (should (equal (seq-take opened 2) '(message "1")))))

(ert-deftest mail-app-view-action-opens-next-thread-as-thread ()
  (mail-app-test--with-action-view "1"
    (with-current-buffer source
      (setq major-mode 'mail-app-thread-list-mode)
      (setq-local mail-app-threads-data
                  (mail-app--thread-summaries
                   (list (list (mail-app-test--message "1" "A"))
                         (list (mail-app-test--message "2" "B")
                               (mail-app-test--message "3" "B reply")))))
      (mail-app--format-thread-list mail-app-threads-data))
    (mail-app-archive-current-message)
    (funcall callback '(:ok 1))
    (should (eq (car opened) 'thread))
    (should (equal (plist-get (cadr opened) :thread-id) "2"))
    (should (= (length (plist-get (cadr opened) :all-messages)) 2))
    (should (eq (nth 2 opened) source))))

(ert-deftest mail-app-view-action-opens-next-single-thread-as-message ()
  (mail-app-test--with-action-view "1"
    (with-current-buffer source
      (setq major-mode 'mail-app-thread-list-mode)
      (setq-local mail-app-threads-data
                  (mail-app--thread-summaries
                   (list (list (mail-app-test--message "1" "A"))
                         (list (mail-app-test--message "2" "B")))))
      (mail-app--format-thread-list mail-app-threads-data))
    (mail-app-junk-current-message)
    (funcall callback '(:ok 1))
    (should (equal (seq-take opened 2) '(message "2")))))

(ert-deftest mail-app-view-action-within-thread-opens-next-message ()
  (mail-app-test--with-action-view "1"
    (with-current-buffer source
      (setq-local mail-app-thread-view (list :all-messages mail-app-messages-data)))
    (mail-app-junk-current-message)
    (funcall callback '(:ok 1))
    (should (equal (seq-take opened 2) '(message "2")))
    (with-current-buffer source
      (should (= (length (plist-get mail-app-thread-view :all-messages)) 2)))))

(ert-deftest mail-app-thread-list-action-advances-point-without-opening-message ()
  (dolist (action '(mail-app-archive-message-at-point mail-app-junk-message-at-point))
    (mail-app-test--with-action-view "1"
      (switch-to-buffer source)
      (setq-local mail-app-thread-view (list :all-messages mail-app-messages-data))
      (mail-app--goto-entry (list :message (mail-app-test--message "1" "A")))
      (funcall action)
      (funcall callback '(:ok 1))
      (should-not opened)
      (should (eq (window-buffer) source))
      (should (equal (plist-get (mail-app--get-message-at-point) :id) "2")))))

(ert-deftest mail-app-view-action-failure-or-skip-stays-put ()
  (dolist (action '(mail-app-archive-current-message mail-app-junk-current-message))
    (dolist (result '((:ok 0 :failed 1) (:ok 0 :missing 1) (:ok 0 :skipped 1)))
      (mail-app-test--with-action-view "1"
        (funcall action)
        (funcall callback result)
        (should-not opened)
        (should (eq (window-buffer) view))
        (should-not mail-app--view-action-running)
        (with-current-buffer source (should (= (length mail-app-messages-data) 3)))))))

(ert-deftest mail-app-view-action-end-returns-to-source-without-wrapping ()
  (mail-app-test--with-action-view "3"
    (mail-app-archive-current-message)
    (funcall callback '(:ok 1))
    (should-not opened)
    (should (eq (window-buffer) source))
    (should-not (buffer-live-p view))))

(ert-deftest mail-app-view-action-does-not-steal-navigation ()
  (mail-app-test--with-action-view "1"
    (mail-app-archive-current-message)
    (switch-to-buffer next)
    (funcall callback '(:ok 1))
    (should-not opened)
    (should (eq (window-buffer) next))
    (with-current-buffer source (should (= (length mail-app-messages-data) 2)))))

(ert-deftest mail-app-view-action-skips-a-next-entry-removed-while-waiting ()
  (mail-app-test--with-action-view "1"
    (mail-app-junk-current-message)
    (mail-app--remove-source-message source "2")
    (funcall callback '(:ok 1))
    (should (equal (seq-take opened 2) '(message "3")))))

(ert-deftest mail-app-view-action-rejects-duplicate-pending-request ()
  (mail-app-test--with-action-view "1"
    (mail-app-archive-current-message)
    (should-error (mail-app-junk-current-message) :type 'user-error)
    (funcall callback '(:ok 0 :failed 1))
    (should-not mail-app--view-action-running)))

(ert-deftest mail-app-view-action-launch-failure-can-be-retried ()
  (mail-app-test--with-action-view "1"
    (cl-letf (((symbol-function 'mail-app--run-mutation-async)
               (lambda (&rest _) (error "Cannot start CLI"))))
      (should-error (mail-app-junk-current-message)))
    (should-not mail-app--view-action-running)
    (mail-app-junk-current-message)
    (should callback)))

(ert-deftest mail-app-view-action-keeps-the-original-next-entry-during-refresh ()
  (mail-app-test--with-action-view "1"
    (mail-app-archive-current-message)
    (with-current-buffer source
      (setq mail-app-message-sort-reverse t)
      (mail-app--format-messages mail-app-messages-data))
    (funcall callback '(:ok 1))
    (should (equal (seq-take opened 2) '(message "2")))))

(ert-deftest mail-app-load-more-after-removal-does-not-skip-a-row ()
  (mail-app-test--with-action-view "1"
    (mail-app--remove-source-message source "1")
    (with-current-buffer source
      (setq-local mail-app-current-limit 3)
      (setq-local mail-app-current-offset 0)
      (let (args)
        (cl-letf (((symbol-function 'mail-app--run-command-async)
                   (lambda (_callback &rest command) (setq args command))))
          (mail-app-load-more-messages))
        (should (equal (cadr (member "-o" args)) "2"))))))

(provide 'test-view-actions)

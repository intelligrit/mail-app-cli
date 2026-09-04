;;; test-identities.el --- Tests for mail-app send identities -*- lexical-binding: t -*-

(require 'ert)
(require 'mail-app-core)
(require 'mail-app-commands)

(ert-deftest mail-app-test-format-identity-from ()
  "Test formatting of identity From: headers."
  (let ((id1 '(:name "Work" :email "user@work.com" :full-name "Jane Doe" :account "Work"))
        (id2 '(:name "Personal" :email "me@home.org" :account "Personal"))
        (id3 '(:name "Quoted" :email "q@test.com" :full-name "Doe, Jane" :account "Test")))
    (should (equal (mail-app-format-identity-from id1) "Jane Doe <user@work.com>"))
    (should (equal (mail-app-format-identity-from id2) "me@home.org"))
    (should (equal (mail-app-format-identity-from id3) "\"Doe, Jane\" <q@test.com>"))))

(ert-deftest mail-app-test-match-identity ()
  "Test identity matching based on recipients and accounts."
  (let ((mail-app-identities
         '((:name "Work" :email "work@example.com" :full-name "Work Me" :account "WorkAcc")
           (:name "Personal" :email "pers@example.com" :full-name "Pers Me" :account "PersAcc")
           (:name "Alias" :email "alias@example.com" :full-name "Alias Me" :account "PersAcc")))
        (mail-app-auto-discover-identities nil))
    ;; Match by direct recipient
    (let ((matched (mail-app-match-identity "work@example.com" "PersAcc")))
      (should (equal (plist-get matched :email) "work@example.com")))
    ;; Match by alias in Cc/To list
    (let ((matched (mail-app-match-identity "Someone <other@foo.com>, Alias <alias@example.com>" "WorkAcc")))
      (should (equal (plist-get matched :email) "alias@example.com")))
    ;; Match by account when no recipient matches
    (let ((matched (mail-app-match-identity "stranger@somewhere.com" "WorkAcc")))
      (should (equal (plist-get matched :account) "WorkAcc")))
    ;; Default to first
    (let ((matched (mail-app-match-identity nil nil)))
      (should (equal (plist-get matched :email) "work@example.com")))))

(ert-deftest mail-app-test-apply-and-cycle-identity ()
  "Test applying and cycling identities in a message buffer."
  (let ((mail-app-identities
         '((:name "Id1" :email "id1@example.com" :full-name "User One" :account "Acc1" :signature "-- \nSig1")
           (:name "Id2" :email "id2@example.com" :full-name "User Two" :account "Acc2" :signature "-- \nSig2")))
        (mail-app-auto-discover-identities nil))
    (with-temp-buffer
      (insert "To: recipient@example.com\nSubject: Hello\n--text follows this line--\nOriginal body message.\n")
      (message-mode)
      ;; Apply first identity
      (mail-app-apply-identity (car mail-app-identities))
      (should (equal (plist-get mail-app--current-identity :email) "id1@example.com"))
      (should (equal (cdr (assq 'account message-options)) "Acc1"))
      ;; Verify From: header was updated
      (save-excursion
        (goto-char (point-min))
        (should (re-search-forward "^From: User One <id1@example.com>$" nil t)))
      ;; Verify signature was inserted
      (save-excursion
        (goto-char (point-min))
        (should (re-search-forward "-- \nSig1" nil t)))

      ;; Now cycle to next identity
      (mail-app-cycle-identity)
      (should (equal (plist-get mail-app--current-identity :email) "id2@example.com"))
      (should (equal (cdr (assq 'account message-options)) "Acc2"))
      ;; Verify From: was swapped
      (save-excursion
        (goto-char (point-min))
        (should (re-search-forward "^From: User Two <id2@example.com>$" nil t)))
      ;; Verify signature was replaced cleanly
      (save-excursion
        (goto-char (point-min))
        (should (re-search-forward "-- \nSig2" nil t))
        (goto-char (point-min))
        (should-not (re-search-forward "-- \nSig1" nil t)))
      ;; Verify original body message was preserved
      (save-excursion
        (goto-char (point-min))
        (should (re-search-forward "Original body message\\." nil t))))))

(provide 'test-identities)
;;; test-identities.el ends here

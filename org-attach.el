;; Attach from dired.

;; Add the following lines to the config file to get a binding for
;; dired-mode.

;; (add-hook
;;  'dired-mode-hook
;;  (lambda ()
;;    (define-key dired-mode-map (kbd "C-c C-x a") #'org-attach-dired-to-subtree))))

;;;###autoload
(defun org-attach-dired-to-subtree (files)
  "Attach FILES marked or current file in `dired' to subtree in other window.
Takes the method given in `org-attach-method' for the attach action.
Precondition: Point must be in a `dired' buffer.
Idea taken from `gnus-dired-attach'."
  (interactive
   (list (dired-get-marked-files)))
  (unless (eq major-mode 'dired-mode)
    (user-error "This command must be triggered in a `dired' buffer"))
  (let ((start-win (selected-window))
        (other-win
         (get-window-with-predicate
          (lambda (window)
            (with-current-buffer (window-buffer window)
              (eq major-mode 'org-mode))))))
    (unless other-win
      (user-error
       "Can't attach to subtree.  No window displaying an Org buffer"))
    (select-window other-win)
    (dolist (file files)
      (org-attach-attach file))
    (select-window start-win)
    (when (eq 'mv org-attach-method)
      (revert-buffer))))

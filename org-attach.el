(defun org-attach-id-uuid-folder-format (id)
  "Translate an UUID ID into a folder-path.
Default format for how Org translates ID properties to a path for
attachments.  Useful if ID is generated with UUID."
  (and (< 2 (length id))
       (format "%s/%s"
               (substring id 0 2)
               (substring id 2))))

(defun org-attach-id-ts-folder-format (id)
  "Translate an ID based on a timestamp to a folder-path.
Useful way of translation if ID is generated based on ISO8601
timestamp.  Splits the attachment folder hierarchy into
year-month, the rest."
  (and (< 6 (length id))
       (format "%s/%s"
               (substring id 0 6)
               (substring id 6))))

(defun org-attach-id-fallback-folder-format (id)
  "Return \"__/X/ID\" folder path as a dumb fallback.
X is the first character in the ID string.

This function may be appended to `org-attach-id-path-function-list' to
provide a fallback for non-standard ID values that other functions in
`org-attach-id-path-function-list' are unable to handle.  For example,
when the ID is too short for `org-attach-id-ts-folder-format'.

However, we recommend to define a more specific function spreading
entries over multiple folders.  This function may create a large
number of entries in a single folder, which may cause issues on some
systems."
  (format "__/%s/%s" (substring id 0 1) id))





(defun org-attach-set-directory ()
  "Set the DIR node property and ask to move files there.
The property defines the directory that is used for attachments
of the entry.  Creates relative links if `org-attach-dir-relative'
is non-nil.

Return the directory."
  (interactive)
  (let ((old (org-attach-dir))
	(new
	 (let* ((attach-dir (read-directory-name
			     "Attachment directory: "
			     (org-entry-get nil "DIR")))
		(current-dir (file-name-directory (or default-directory
						      buffer-file-name)))
		(attach-dir-relative (file-relative-name attach-dir current-dir)))
	   (org-entry-put nil "DIR" (if org-attach-dir-relative
					attach-dir-relative
				      attach-dir))
           attach-dir)))
    (unless (or (string= old new)
                (not old))
      (when (yes-or-no-p "Copy over attachments from old directory? ")
        (copy-directory old new t t t))
      (when (yes-or-no-p (concat "Delete " old))
        (delete-directory old t)))
    new))

(defun org-attach-unset-directory ()
  "Remove DIR node property.
If attachment folder is changed due to removal of DIR-property
ask to move attachments to new location and ask to delete old
attachment-folder.

Change of attachment-folder due to unset might be if an ID
property is set on the node, or if a separate inherited
DIR-property exists (that is different from the unset one)."
  (interactive)
  (let ((old (org-attach-dir))
	(new
         (progn
	   (org-entry-delete nil "DIR")
	   ;; ATTACH-DIR is deprecated and removed from documentation,
	   ;; but still works. Remove code for it after major nr change.
	   (org-entry-delete nil "ATTACH_DIR")
	   (org-attach-dir))))
    (unless (or (string= old new)
                (not old))
      (when (and new (yes-or-no-p "Copy over attachments from old directory? "))
        (copy-directory old new t nil t))
      (when (yes-or-no-p (concat "Delete " old))
        (delete-directory old t)))))

(defun org-attach-tag (&optional off)
  "Turn the autotag on or (if OFF is set) off."
  (when org-attach-auto-tag
    ;; FIXME: There is currently no way to set #+FILETAGS
    ;; programmatically.  Do nothing when before first heading
    ;; (attaching to file) to avoid blocking error.
    (unless (org-before-first-heading-p)
      (save-excursion
        (org-back-to-heading t)
        (org-toggle-tag org-attach-auto-tag (if off 'off 'on))))))

(defun org-attach-untag ()
  "Turn the autotag off."
  (org-attach-tag 'off))

(defun org-attach-url (url)
  "Attach URL."
  (interactive "MURL of the file to attach: \n")
  (let ((org-attach-method 'url)
        (org-safe-remote-resources ; Assume safety if in an interactive session.
         (if noninteractive org-safe-remote-resources '(""))))
    (org-attach-attach url)))

(defun org-attach-buffer (buffer-name)
  "Attach BUFFER-NAME's contents to current outline node.
BUFFER-NAME is a string.  Signals a `file-already-exists' error
if it would overwrite an existing filename."
  (interactive "bBuffer whose contents should be attached: ")
  (let* ((attach-dir (org-attach-dir 'get-create))
	 (output (expand-file-name buffer-name attach-dir)))
    (when (file-exists-p output)
      (signal 'file-already-exists (list "File exists" output)))
    (run-hook-with-args 'org-attach-after-change-hook attach-dir)
    (org-attach-tag)
    (with-temp-file output
      (insert-buffer-substring buffer-name))))

(defun org-attach-attach (file &optional visit-dir method)
  "Move/copy/link FILE into the attachment directory of the current outline node.
If VISIT-DIR is non-nil, visit the directory with `dired'.
METHOD may be `cp', `mv', `ln', `lns' or `url' default taken from
`org-attach-method'."
  (interactive
   (list
    (read-file-name "File to keep as an attachment: "
                    (or (progn
                          (require 'dired-aux)
                          (dired-dwim-target-directory))
                        default-directory))
    current-prefix-arg
    nil))
  (setq method (or method org-attach-method))
  (when (file-directory-p file)
    (setq file (directory-file-name file)))
  (let ((basename (file-name-nondirectory file)))
    (let* ((attach-dir (org-attach-dir 'get-create))
           (attach-file (expand-file-name basename attach-dir)))
      (cond
       ((eq method 'mv) (rename-file file attach-file))
       ((eq method 'cp)
        (if (file-directory-p file)
            (copy-directory file attach-file nil nil t)
          (copy-file file attach-file)))
       ((eq method 'ln) (add-name-to-file file attach-file))
       ((eq method 'lns) (make-symbolic-link file attach-file 1))
       ((eq method 'url)
        (if (org--should-fetch-remote-resource-p file)
            (url-copy-file file attach-file)
          (error "The remote resource %S is considered unsafe, and will not be downloaded"
                 file))))
      (run-hook-with-args 'org-attach-after-change-hook attach-dir)
      (org-attach-tag)
      (cond ((eq org-attach-store-link-p 'attached)
	     (push (list (concat "attachment:" (file-name-nondirectory attach-file))
			 (file-name-nondirectory attach-file))
		   org-stored-links))
            ((eq org-attach-store-link-p t)
             (push (list (concat "file:" file)
			 (file-name-nondirectory file))
		   org-stored-links))
	    ((eq org-attach-store-link-p 'file)
	     (push (list (concat "file:" attach-file)
			 (file-name-nondirectory attach-file))
		   org-stored-links)))
      (if visit-dir
          (dired attach-dir)
        (message "File %S is now an attachment" basename)))))

(defun org-attach-attach-cp ()
  "Attach a file by copying it."
  (interactive)
  (let ((org-attach-method 'cp)) (call-interactively 'org-attach-attach)))
(defun org-attach-attach-mv ()
  "Attach a file by moving (renaming) it."
  (interactive)
  (let ((org-attach-method 'mv)) (call-interactively 'org-attach-attach)))
(defun org-attach-attach-ln ()
  "Attach a file by creating a hard link to it.
Beware that this does not work on systems that do not support hard links.
On some systems, this apparently does copy the file instead."
  (interactive)
  (let ((org-attach-method 'ln)) (call-interactively 'org-attach-attach)))
(defun org-attach-attach-lns ()
  "Attach a file by creating a symbolic link to it.

Beware that this does not work on systems that do not support symbolic links.
On some systems, this apparently does copy the file instead."
  (interactive)
  (let ((org-attach-method 'lns)) (call-interactively 'org-attach-attach)))

(defun org-attach-new (file)
  "Create a new attachment FILE for the current outline node.
The attachment is created as an Emacs buffer."
  (interactive "sCreate attachment named: ")
  (let ((attach-dir (org-attach-dir 'get-create)))
    (org-attach-tag)
    (find-file (expand-file-name file attach-dir))
    (message "New attachment %s" file)))

(defun org-attach-delete-one (&optional attachment)
  "Delete a single ATTACHMENT."
  (interactive)
  (let* ((attach-dir (org-attach-dir))
	 (files (org-attach-file-list attach-dir))
	 (attachment (or attachment
		   (completing-read
		    "Delete attachment: "
		    (mapcar (lambda (f)
			      (list (file-name-nondirectory f)))
			    files)))))
    (setq attachment (expand-file-name attachment attach-dir))
    (unless (file-exists-p attachment)
      (error "No such attachment: %s" attachment))
    (delete-file attachment)
    (run-hook-with-args 'org-attach-after-change-hook attach-dir)))

(defun org-attach-delete-all (&optional force)
  "Delete all attachments from the current outline node.
This actually deletes the entire attachment directory.
A safer way is to open the directory in `dired' and delete from there.

With prefix argument FORCE, directory will be recursively deleted
with no prompts."
  (interactive "P")
  (let ((attach-dir (org-attach-dir)))
    (when (and attach-dir
	       (or force
		   (yes-or-no-p "Really remove all attachments of this entry? ")))
      (delete-directory attach-dir
			(or force (yes-or-no-p "Recursive?"))
			t)
      (message "Attachment directory removed")
      (run-hook-with-args 'org-attach-after-change-hook attach-dir)
      (org-attach-untag))))

(defun org-attach-sync ()
  "Synchronize the current outline node with its attachments.
Useful after files have been added/removed externally.  Option
`org-attach-sync-delete-empty-dir' controls the behavior for
empty attachment directories."
  (interactive)
  (let ((attach-dir (org-attach-dir)))
    (if (not attach-dir)
        (org-attach-tag 'off)
      (run-hook-with-args 'org-attach-after-change-hook attach-dir)
      (let ((files (org-attach-file-list attach-dir)))
	(org-attach-tag (not files)))
      (when org-attach-sync-delete-empty-dir
        (when (and (org-directory-empty-p attach-dir)
                   (if (eq 'query org-attach-sync-delete-empty-dir)
                       (yes-or-no-p "Attachment directory is empty.  Delete?")
                     t))
          (delete-directory attach-dir))))))

(defun org-attach-file-list (directory)
  "Return a list of files in the attachment DIRECTORY.
This ignores files ending in \"~\"."
  (delq nil
	(mapcar (lambda (x) (if (string-match "^\\.\\.?\\'" x) nil x))
		(directory-files directory nil "[^~]\\'"))))

(defun org-attach-reveal ()
  "Show the attachment directory of the current outline node.
This will attempt to use an external program to show the
directory.  Will create an attachment and folder if it doesn't
exist yet.  Respects `org-attach-preferred-new-method'."
  (interactive)
  (org-open-file (org-attach-dir-get-create)))

(defun org-attach-reveal-in-emacs ()
  "Show the attachment directory of the current outline node in `dired'.
Will create an attachment and folder if it doesn't exist yet.
Respects `org-attach-preferred-new-method'."
  (interactive)
  (dired (org-attach-dir-get-create)))

(defun org-attach-open (&optional in-emacs)
  "Open an attachment of the current outline node.
If there are more than one attachment, you will be prompted for the file name.
This command will open the file using the settings in `org-file-apps'
and in the system-specific variants of this variable.
If IN-EMACS is non-nil, force opening in Emacs."
  (interactive "P")
  (let ((attach-dir (org-attach-dir)))
    (if attach-dir
	(let* ((file (pcase (org-attach-file-list attach-dir)
		       (`(,file) file)
		       (files (completing-read "Open attachment: "
					       (mapcar #'list files) nil t))))
	       (path (expand-file-name file attach-dir)))
	  (run-hook-with-args 'org-attach-open-hook path)
	  (org-open-file path in-emacs))
      (error "No attachment directory exist"))))

(defun org-attach-open-in-emacs ()
  "Open attachment, force opening in Emacs.
See `org-attach-open'."
  (interactive)
  (org-attach-open 'in-emacs))

(defun org-attach-expand (file)
  "Return the full path to the current entry's attachment file FILE.
Basically, this adds the path to the attachment directory."
  (expand-file-name file (org-attach-dir)))

(defun org-attach-expand-links (_)
  "Expand links in current buffer.
It is meant to be added to `org-export-before-parsing-hook'."
  (save-excursion
    (while (re-search-forward "attachment:" nil t)
      (let ((link (org-element-context)))
	(when (and (org-element-type-p link 'link)
		   (string-equal "attachment"
				 (org-element-property :type link)))
	  (let* ((description (and (org-element-contents-begin link)
				   (buffer-substring-no-properties
				    (org-element-contents-begin link)
				    (org-element-contents-end link))))
		 (file (org-element-property :path link))
		 (new-link (org-link-make-string
			    (concat "file:" (org-attach-expand file))
			    description)))
	    (goto-char (org-element-end link))
	    (skip-chars-backward " \t")
	    (delete-region (org-element-begin link) (point))
	    (insert new-link)))))))

(defun org-attach-follow (file arg)
  "Open FILE attachment.
See `org-open-file' for details about ARG."
  (org-link-open-as-file (org-attach-expand file) arg))

(org-link-set-parameters "attachment"
			 :follow #'org-attach-follow
                         :complete #'org-attach-complete-link)

(defun org-attach-complete-link ()
  "Advise the user with the available files in the attachment directory."
  (let ((attach-dir (org-attach-dir)))
    (if attach-dir
	(let* ((attached-dir (expand-file-name attach-dir))
	       (file (read-file-name "File: " attached-dir))
	       (pwd (file-name-as-directory attached-dir))
               (pwd-relative (file-name-as-directory
			      (abbreviate-file-name attached-dir))))
	  (cond
	   ((string-match (concat "^" (regexp-quote pwd-relative) "\\(.+\\)") file)
	    (concat "attachment:" (match-string 1 file)))
	   ((string-match (concat "^" (regexp-quote pwd) "\\(.+\\)")
			  (expand-file-name file))
	    (concat "attachment:" (match-string 1 (expand-file-name file))))
	   (t (concat "attachment:" file))))
      (error "No attachment directory exist"))))

(defun org-attach-archive-delete-maybe ()
  "Maybe delete subtree attachments when archiving.
This function is called by `org-archive-hook'.  The option
`org-attach-archive-delete' controls its behavior."
  (when org-attach-archive-delete
    (org-attach-delete-all (not (eq org-attach-archive-delete 'query)))))


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



(add-hook 'org-archive-hook 'org-attach-archive-delete-maybe)
(add-hook 'org-export-before-parsing-functions 'org-attach-expand-links)

(provide 'org-attach)

;; Local variables:
;; generated-autoload-file: "org-loaddefs.el"
;; End:

;;; org-attach.el ends here

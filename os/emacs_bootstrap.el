;;; emacs_bootstrap.el --- Inspect package bootstrap without changing dotemacs -*- lexical-binding: t; -*-

(require 'cl-lib)

;; --batch has already run startup hooks before explicit --load arguments.
;; Recreate the initialization boundary for asynchronous package managers.
(setq after-init-time nil
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      server-name (format "dotfiles-installer-%d" (emacs-pid)))


;; Keep Elpaca's structured build log, without repeatedly rendering its
;; interactive log window during a headless installation.
(with-eval-after-load 'elpaca
  (setq elpaca-log-functions nil))

(defvar dotfiles-bootstrap-errors nil)

;; use-package can catch an initialization error and return successfully.
;; Preserve its diagnostic, but do not mistake that for a verified startup.
(defun dotfiles-record-startup-warning (type message &optional level &rest _arguments)
  (when (memq level '(:error :emergency))
    (push (list type message) dotfiles-bootstrap-errors)))
(advice-add 'display-warning :before #'dotfiles-record-startup-warning)

(defun dotfiles-bootstrap-progress ()
  "Report unfinished packages in the installer log."
  (when (boundp 'elpaca--queues)
    (let (pending)
      (dolist (queue elpaca--queues)
        (dolist (entry (elpaca-q<-elpacas queue))
          (unless (memq (elpaca<-status (cdr entry)) '(finished failed))
            (push (list (car entry) (elpaca<-status (cdr entry))
                        (elpaca<-current-step (cdr entry))) pending))))
      (when pending
        (message "Emacs bootstrap: %d pending; first entries: %S"
                 (length pending) (cl-subseq pending 0 (min 8 (length pending))))))))

(defvar dotfiles-bootstrap-progress-timer
  (run-at-time 30 30 #'dotfiles-bootstrap-progress))

;; The installer loads this before the published configuration.  A deadline
;; keeps unavailable package sources or stuck build queues from hanging setup.
(defvar dotfiles-bootstrap-deadline
  (run-at-time
   600 nil
   (lambda ()
     (message "Emacs package bootstrap exceeded ten minutes; inspect Elpaca in Emacs.")
     (when (boundp 'elpaca--queues)
       (dolist (queue elpaca--queues)
         (dolist (entry (elpaca-q<-elpacas queue))
           (unless (eq (elpaca<-status (cdr entry)) 'finished)
             (message "Unfinished package: %S (%S)" (car entry) (elpaca<-status (cdr entry)))))))
     (kill-emacs 2))))

(defun dotfiles-verify-bootstrap ()
  "Wait for package builds and report failures that startup may have caught."
  (setq after-init-time (current-time))
  (run-hooks 'after-init-hook 'emacs-startup-hook)
  (when (fboundp 'elpaca-wait)
    (elpaca-wait))
  (when init-file-had-error
    (error "Published Emacs configuration reported an initialization error"))
  (when (boundp 'elpaca--queues)
    (let (failures)
      (dolist (queue elpaca--queues)
        (dolist (entry (elpaca-q<-elpacas queue))
          (when (eq (elpaca<-status (cdr entry)) 'failed)
            (push (car entry) failures))))
      (when failures
        ;; Recent Elpaca versions retain structured build events. Include a
        ;; bounded excerpt so a failed package has a useful diagnostic log.
        (when (and (boundp 'elpaca--event-log)
                   (fboundp 'elpaca-event<-id)
                   (fboundp 'elpaca-event<-payload))
          (let ((remaining 30))
            (dolist (event elpaca--event-log)
              (when (and (> remaining 0)
                         (memq (elpaca-event<-id event) failures))
                (message "Elpaca %S: %S" (elpaca-event<-id event)
                         (elpaca-event<-payload event))
                (setq remaining (1- remaining))))))
        (error "Elpaca packages failed: %S" failures))))
  (when dotfiles-bootstrap-errors
    (error "Configuration reported startup errors: %S" dotfiles-bootstrap-errors))
  (cancel-timer dotfiles-bootstrap-deadline)
  (cancel-timer dotfiles-bootstrap-progress-timer)
  (message "Configuration startup and package bootstrap completed."))

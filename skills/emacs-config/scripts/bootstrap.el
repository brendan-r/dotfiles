;;; bootstrap.el --- Private Emacs test state -*- lexical-binding: t; -*-

;; Both the batch runner and GUI early-init wrapper call this BEFORE user code.
;; HOME is already private in the parent process; changing it after startup is
;; too late for Emacs and libraries which cache the home directory.
(defun emacs-config-isolate ()
  "Establish per-run state without accessing an existing Emacs server."
  (when (< emacs-major-version 27)
    (error "This helper requires Emacs 27 or newer"))
  (let* ((root (file-name-as-directory (or (getenv "EC_RUN")
                                         (error "Missing EC_RUN"))))
         ;; Keep the spelling normal startup uses.  Some configuration code
         ;; passes this string to `normal-top-level-add-to-load-path', which
         ;; compares directory strings literally when deciding where to splice.
         ;; HOME was already isolated before Emacs started.
         (config "~/.emacs.d/")
         (state (expand-file-name "state/" root)))
    (setq user-emacs-directory config
          user-init-file (expand-file-name "init.el" config)
          default-directory (expand-file-name "work/" root)
          package-user-dir (expand-file-name "elpa/" config)
          package-quickstart-file (expand-file-name "package-quickstart.el" state)
          custom-file (expand-file-name "custom.el" config)
          load-prefer-newer t
          create-lockfiles nil
          backup-directory-alist `(("." . ,(expand-file-name "backups/" state)))
          auto-save-file-name-transforms
          `((".*" ,(expand-file-name "autosave/" state) t))
          auto-save-list-file-prefix (expand-file-name "autosave/.saves-" state))
    ;; Setting these before their libraries load preserves their private defaults.
    (setq savehist-file (expand-file-name "history" state)
          recentf-save-file (expand-file-name "recentf" state)
          bookmark-default-file (expand-file-name "bookmarks" state)
          url-configuration-directory (expand-file-name "url/" state)
          desktop-dirname state
          desktop-path (list state))
    (when (fboundp 'startup-redirect-eln-cache)
      (startup-redirect-eln-cache (expand-file-name "eln-cache/" state)))
    (require 'server)
    (setq server-name "test"
          server-use-tcp nil
          server-socket-dir (file-name-as-directory (getenv "EC_SOCKET_DIR"))
          server-auth-dir server-socket-dir)
    (setq debug-on-error t)))

(defun emacs-config-batch ()
  "Load the selected copied config; batch startup does not load it for us."
  (emacs-config-isolate)
  (unless (equal (getenv "EC_MINIMAL") "1")
    (let ((early (expand-file-name "early-init.el" user-emacs-directory)))
      (when (file-exists-p early) (load early nil nil t)))
    ;; Mirror normal package activation after early-init, before init.el.
    ;; Individual configs may also call package-initialize, as normal startup can.
    (require 'package)
    (when package-enable-at-startup (package-initialize))
    (load user-init-file nil nil t)
    ;; These hooks otherwise ran before --load in batch mode, with no user init.
    ;; We intentionally do not fake GUI/window setup hooks or noninteractive=nil.
    (setq after-init-time (current-time))
    (run-hooks 'after-init-hook 'emacs-startup-hook))
  (princ (format "\nPrivate Emacs %s; PID %d; HOME %s\n"
                 emacs-version (emacs-pid) (getenv "HOME"))))

(provide 'emacs-config-bootstrap)

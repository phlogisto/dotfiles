;;; init.el --- emacs configuration -*- lexical-binding: t; -*-

;;; Commentary:

;; Emacs configuration

;;; Code:

;;;; packages

(require 'package)

(setq
 package-archives
 '(("melpa" . "https://melpa.org/packages/")
   ("melpa-stable" . "https://stable.melpa.org/packages/")
   ("gnu" . "https://elpa.gnu.org/packages/"))
 package-enable-at-startup nil)
(package-initialize)

;; (benchmark-init/activate)  ;; fixme

(defun w--use-package-fail-on-missing-package (package ensure _state _context)
  "Trigger an error if PACKAGE was not installed and ENSURE is non-nil."
  (when (and ensure (not (package-installed-p package))
      (error "Package %s is not installed" package))))

(setq disabled-command-function nil)
(fset 'yes-or-no-p 'y-or-n-p)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(setq
 use-package-ensure-function #'w--use-package-fail-on-missing-package
 use-package-always-ensure t)

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(use-package auto-compile
  :config
  (setq auto-compile-update-autoloads t)
  (auto-compile-on-load-mode))


;;;; lisp helpers

(use-package dash)
(use-package dash-functional)
(use-package s)
(use-package fn)


;;;; evil (bootstrap only)

;; bootstrap early in the process so evil functionality
;; such as evil-define-key can be used.
(use-package evil
  :init
  (setq
   evil-want-C-u-scroll t
   evil-want-C-w-in-emacs-state t))


;;;; security

(use-package tls
  :config
  (setq
   tls-checktrust 'ask
   tls-program (--remove (s-contains? "gnutls" it) tls-program)))


;;;; no agitprop

(defun display-startup-echo-area-message ()
  "Do not display progaganda."
  ;; setting 'inhibit-startup-echo-area-message'
  ;; to nil or even (user-login-name) is not enough
  ;; to resist the gnu/extremists, so modify the
  ;; offending propaganda function instead.
  (message ""))

(bind-keys
 ("C-h g" . nil)
 ("C-h g" . nil)
 ("C-h C-c" . nil)
 ("C-h C-m" . nil)
 ("C-h C-o" . nil)
 ("C-h C-w" . nil))


;;;; hydra

(use-package hydra)

(defvar w--hydra-hint-delay 1
  "Delay before showing help.")

;; fixme: maybe use a registry pattern with an alist that maps major
;; modes (and derived modes) to a hydra, instead of buffer-local variables?
(defvar w--major-mode-hydra nil
  "Hydra body for the current major mode.")
(make-variable-buffer-local 'w--major-mode-hydra)

(defun w--set-major-mode-hydra (hydra-body)
  "Set the buffer-local major-mode specific hydra to HYDRA-BODY."
  (setq w--major-mode-hydra hydra-body))

(defun w--major-mode-hydra ()
  "Run major mode hydra, if any."
  (interactive)
  (if w--major-mode-hydra
      (call-interactively w--major-mode-hydra)
    (user-error "No major-mode specific hydra defined for %s" major-mode)))

(defun w--hydra-evil-repeat-record-command ()
  "Record last command from the hydra in evil's repeat system."
  (evil-repeat-start)
  (setq evil-repeat-info `((call-interactively ,real-this-command)))
  (evil-repeat-stop))

(defun w--hydra-make-docstring (&rest args)
  "Make a docstring for a hydra from ARGS."
  (setq args (--map-when (not (string-match-p "_" it))
                         (format "  %s:" it)
                         args))
  (s-concat "\n" (s-trim (s-join "  " args))))

(defun w--hydra-set-defaults (body)
  "Add defaults to a hydra BODY list."
  (unless (plist-member body :exit)
    (setq body (plist-put body :exit t)))
  (unless (plist-member body :hint)
    (setq body (plist-put body :hint nil)))
  (unless (plist-member body :foreign-keys)
    (setq body (plist-put body :foreign-keys 'warn)))
  (setq body (plist-put body :idle w--hydra-hint-delay))
  body)

(defun w--hydra-missing-uppercase-heads (heads)
  "Return missing uppercase hydra heads.

This creates uppercase versions for all lowercase HEADS that are only
defined as lowercase."
  (let* ((case-fold-search nil)
         (uppercase-keys
          (--filter (s-matches-p "^[A-Z]$" it) (-map #'car heads))))
    (--map
     (-replace-at 0 (upcase (car it)) it)
     (--filter
      (and (s-matches? "^[a-z]$" (car it))
           (not (-contains-p uppercase-keys (upcase (car it)))))
      heads))))

(defmacro w--make-hydra (name body &rest args)
  "Make a hydra NAME with BODY, using ARGS for heads and docstrings."
  (declare (indent 2))
  (-let [(docstrings heads) (-separate #'stringp args)]
    `(defhydra
       ,name
       ,(w--hydra-set-defaults body)
       ,(apply #'w--hydra-make-docstring docstrings)
       ,@(w--hydra-missing-uppercase-heads heads)
       ,@heads
       ("<escape>" nil :exit t))))


;;;; environment

(use-package exec-path-from-shell
  :config
  (setq exec-path-from-shell-check-startup-files nil)
  (exec-path-from-shell-initialize))

(use-package direnv
  :config
  (setq
   direnv-always-show-summary t
   direnv-show-paths-in-summary nil)
  (direnv-mode))

(use-package server
  :config
  (unless (server-running-p)
    (server-start)))

(when (eq system-type 'darwin)
  (global-set-key (kbd "s-q") nil)
  (setq
   ns-right-alternate-modifier 'none
   ns-use-native-fullscreen nil))


;;;; buffers, files, directories

(setq
 auto-save-file-name-transforms '((".*" "~/.emacs.d/auto-saves/\\1" t))
 backup-directory-alist '((".*" . "~/.emacs.d/backups/"))
 find-file-visit-truename t
 make-backup-files nil)

(defun w--buffer-worth-saving-p (name)
  "Does the buffer NAME indicate it may be worth saving?"
  (cond
   ((string-equal "*scratch*" name) t)
   ((string-prefix-p "*new*" name) t)  ;; evil-mode template
   ((string-match-p "\*" name) nil) ;; e.g. magit, help
   (t t)))

(defun w--ask-confirmation-for-unsaved-buffers ()
  "Ask for confirmation for modified but unsaved buffers."
  (if (and (buffer-modified-p)
           (not (buffer-file-name))
           (w--buffer-worth-saving-p (buffer-name)))
      (y-or-n-p
       (format
        "Buffer %s modified but not saved; kill anyway? "
        (buffer-name)))
    t))

(add-hook
 'kill-buffer-query-functions
 'w--ask-confirmation-for-unsaved-buffers)

(use-package recentf
  :config
  (setq
   recentf-auto-cleanup 300
   recentf-max-saved-items 200)
  (recentf-mode))

(use-package sync-recentf)

(use-package sudo-edit)

(use-package terminal-here)

(w--make-hydra w--hydra-buffer nil
  "buffer"
  "_b_uffer"
  ("b" ivy-switch-buffer)
  ("B" ivy-switch-buffer-other-window)
  "_h_ide"
  ("h" bury-buffer)
  ("H" unbury-buffer)
  "_k_ill"
  ("k" kill-this-buffer)
  ("K" kill-buffer-and-window)
  "_n_ew"
  ("n" evil-buffer-new)
  "_o_ther-window"
  ("o" ivy-switch-buffer-other-window)
  "_r_evert"
  ("r" revert-buffer))

;; todo: try out https://github.com/fourier/ztree
(use-package ztree)

(w--make-hydra w--hydra-find-file nil
  "open"
  "_d_irectory"
  ("d" dired-jump)
  ("D" dired-jump-other-window)
  "_f_ile"
  ("f" counsel-find-file)
  ("F" find-file-other-window)
  "_n_ew"
  ("n" evil-buffer-new)
  ("N" (progn
         (w--evil-window-next-or-vsplit)
         (call-interactively #'evil-buffer-new)))
  "_o_ther-window"
  ("o" find-file-other-window)
  "_r_ecent"
  ("r" counsel-recentf)
  ;; todo: make recentf for other-window work properly,
  ;; with focus on new window after opening
  ("R" (letf (((symbol-function 'find-file)
               (symbol-function 'find-file-other-window)))
         (counsel-recentf)))
  "_s_udo"
  ("s" sudo-edit)
  ("S" (sudo-edit t))
  "_t_ree"
  ("t" (ztree-dir (file-name-directory (buffer-file-name))))
  "_!_ terminal"
  ("!" terminal-here))


;;;; frames

(setq
 frame-resize-pixelwise t
 frame-title-format "%b")

(add-to-list 'default-frame-alist '(fullscreen . maximized))


;;;; minimal ui

(setq
 echo-keystrokes 0.5
 inhibit-startup-screen t
 initial-scratch-message nil)

(menu-bar-mode -1)
(scroll-bar-mode -1)
(tool-bar-mode -1)
(blink-cursor-mode -1)


;;;; theme

(defvar w--dark-theme 'solarized-dark "The preferred dark theme.")
(defvar w--light-theme 'solarized-light "The preferred light theme.")

(use-package solarized-theme
  :config
  (setq
   solarized-desaturation 25  ;; only in locally patched version for now
   solarized-emphasize-indicators nil
   solarized-scale-org-headlines nil
   solarized-use-less-bold t
   solarized-use-variable-pitch nil
   solarized-height-minus-1 1.0
   solarized-height-plus-1 1.0
   solarized-height-plus-2 1.0
   solarized-height-plus-3 1.0
   solarized-height-plus-4 1.0))

(load-theme w--dark-theme t t)
(load-theme w--light-theme t t)

(defun w--activate-theme (dark)
  "Load configured theme. When DARK is nil, load a light theme."
  (setq frame-background-mode (if dark 'dark 'light))
  (mapc 'frame-set-background-mode (frame-list))
  (let ((theme (if dark w--dark-theme w--light-theme)))
    (enable-theme theme)))

(defun w--toggle-dark-light-theme ()
  "Toggle between a dark and light theme."
  (interactive)
  (w--activate-theme (eq (first custom-enabled-themes) w--light-theme)))

(defun w--disable-themes-advice (theme)
  "Disable all enabled themes."
  (unless (eq theme 'user)
    (--each custom-enabled-themes
      (disable-theme it))))

(advice-add 'enable-theme :before #'w--disable-themes-advice)

(defun w--set-theme-from-environment ()
  "Set the theme based on presence/absence of a configuration file."
  (interactive)
  (w--activate-theme (file-exists-p "~/.config/dark-theme")))

(w--set-theme-from-environment)

;; todo: revise cursor appearance
(setq
 evil-normal-state-cursor   '("#859900" box)     ; green
 evil-visual-state-cursor   '("#cb4b16" box)     ; orange
 evil-insert-state-cursor   '("#268bd2" bar)     ; blue
 evil-replace-state-cursor  '("#dc322f" bar)     ; red
 evil-operator-state-cursor '("#dc322f" hollow)) ; red


;;;; fonts

(use-package default-text-scale)

(defvar w--default-text-scale-height
  (face-attribute 'default :height)  ;; inherit from startup environment
  "The default text scale height.")

(if (<= w--default-text-scale-height 60)
    ;; when started as an emacs daemon process, the default face's
    ;; height attribute is bogus. use a sane default in that case.
    (setq w--default-text-scale-height 100))

(defun w--default-text-scale-reset ()
  "Reset default text scale."
  (interactive)
  (w--default-text-scale-set w--default-text-scale-height))

(defun w--default-text-scale-set (height)
  "Set default text scale to HEIGHT."
  (interactive "nHeight (e.g. 110) ")
  (default-text-scale-increment (- height (face-attribute 'default :height))))

(when (display-graphic-p)
  (w--default-text-scale-reset))

(defvar w--faces-bold '(magit-popup-argument)
  "Faces that may retain their bold appearance.")

(defun w--make-faces-boring ()
  "Remove unwanted attributes from font faces."
  (interactive)
  (--each (face-list)
    (unless (member it w--faces-bold)
      (set-face-attribute it nil :weight 'normal :underline nil))))

(w--make-faces-boring)

(advice-add
 'load-theme
 :after (fn: w--make-faces-boring))

(w--make-hydra w--hydra-zoom nil
  "zoom"
  "_i_n"
  ("i" default-text-scale-increase :exit nil)
  ("+" default-text-scale-increase :exit nil)
  ("=" default-text-scale-increase :exit nil)
  "_o_ut"
  ("o" default-text-scale-decrease :exit nil)
  ("-" default-text-scale-decrease :exit nil)
  "_z_ normal"
  ("z" w--default-text-scale-reset)
  ("0" w--default-text-scale-reset)
  "writeroom"
  "_n_arrower"
  ("n" w--writeroom-narrower :exit nil)
  "_w_ider"
  ("w" w--writeroom-wider :exit nil)
  "_r_eset"
  ("r" w--writeroom-reset))

(evil-define-key*
 'motion global-map
 (kbd "C-0") 'w--default-text-scale-reset
 (kbd "C--") 'default-text-scale-decrease
 (kbd "C-=") 'default-text-scale-increase)


;;;; mode line

(use-package smart-mode-line
  :config
  (setq
   sml/line-number-format "%l"
   sml/name-width '(1 . 40)
   sml/projectile-replacement-format "%s:")
  (sml/setup))

(use-package rich-minority
  :config
  (defun w--hide-from-mode-line (string)
    "Hide STRING from the mode line."
    (add-to-list 'rm-blacklist string)))


;;;; evil

(use-package undo-tree
  :config
  (w--hide-from-mode-line " Undo-Tree"))

;; note: evil is already bootstrapped at this point
(use-package evil
  :config
  (setq evil-insert-state-message nil)
  (setq
   evil-cross-lines t)
  (evil-mode)
  (add-to-list 'evil-overriding-maps '(magit-blame-mode-map . nil))
  ;; use Y to copy to the end of the line; see evil-want-Y-yank-to-eol
  (evil-add-command-properties 'evil-yank-line :motion 'evil-end-of-line)
  (dolist (map (list evil-normal-state-map evil-visual-state-map))
    (define-key map [escape] 'keyboard-quit)))

(use-package evil-snipe
  :defer nil
  :bind
  (:map
   evil-snipe-parent-transient-map
   ("[spc]" . w--evil-easymotion-for-active-snipe))
  :init
  (setq
   evil-snipe-auto-disable-substitute nil)
  :config
  (setq
   evil-snipe-override-evil-repeat-keys nil
   evil-snipe-scope 'line
   evil-snipe-repeat-scope 'line
   evil-snipe-smart-case t
   evil-snipe-tab-increment t)
  (set-face-attribute
   'evil-snipe-matches-face nil
   :inherit 'lazy-highlight)

  (evil-snipe-mode)
  (w--hide-from-mode-line " snipe")

  ;; the t/T/f/F overrides are the most important ones, since
  ;; avy/evil-easymotion already allows for fancy jumps, e.g. via
  ;; avy-goto-char-timer.
  (evil-define-key* 'motion evil-snipe-mode-map
    "s" nil
    "S" nil)

  (defun w--evil-easymotion-for-active-snipe ()
    "Turn an active snipe into an avy/easy-motion overlay."
    (evilem-create
     (list 'evil-snipe-repeat 'evil-snipe-repeat-reverse)
     :bind ((evil-snipe-scope 'visible)
            (evil-snipe-enable-highlight)
            (evil-snipe-enable-incremental-highlight)))))

(use-package evil-colemak-basics
  :init
  (setq evil-colemak-basics-char-jump-commands 'evil-snipe)
  :config
  (global-evil-colemak-basics-mode)
  (w--hide-from-mode-line " hnei"))

(defun w--disable-colemak ()
  "Disable colemak overrides."
  (evil-colemak-basics-mode -1))

(use-package evil-swap-keys
  :config
  (global-evil-swap-keys-mode))

(use-package evil-commentary
  :config
  (evil-commentary-mode)
  (w--hide-from-mode-line " s-/"))

(use-package evil-easymotion
  :config
  (evilem-default-keybindings "SPC")

  (defun w--avy-evil-change-region ()
    "Select two lines and change the lines between them."
    (interactive)
    (avy-with w--avy-evil-change-region
      (let* ((beg (progn (avy-goto-line) (point)))
             (end (save-excursion (goto-char (avy--line)) (forward-line) (point))))
        (evil-change beg end 'line nil nil))))

  (defun w--avy-evil-delete-line ()
    "Select a line and delete it."
    (interactive)
    (avy-with w--avy-evil-delete-line
      (save-excursion
        (let ((line (avy--line)))
          (unless (eq line t)
            (goto-char line)
            (evil-delete-whole-line
             (point)
             (line-beginning-position 2)
             'line nil nil))))))

  (defun w--avy-evil-delete-region ()
    "Select two lines and delete the lines between them."
    (interactive)
    (avy-with w--avy-evil-delete-region
      (let* ((beg (avy--line))
             (end (save-excursion (goto-char (avy--line)) (forward-line) (point))))
        (evil-delete beg end 'line nil nil))))

  (defun w--avy-goto-char-timer-any-window ()
    "Go to character in any visible window."
    (interactive)
    (setq current-prefix-arg t)
    (call-interactively 'avy-goto-char-timer))

  (defun w--avy-goto-line-any-window ()
    "Go to line in any visible window."
    (interactive)
    (setq current-prefix-arg 4)
    (call-interactively 'avy-goto-line))

  (defun w--evil-end-of-next-line ()
    (interactive)
    (evil-next-line)
    (end-of-line))

  (evilem-make-motion-plain
   w--avy-evil-goto-end-of-line
   (list 'evil-end-of-line 'w--evil-end-of-next-line)
   :pre-hook (setq evil-this-type 'line)
   :bind ((scroll-margin 0))
   :initial-point (goto-char (window-start)))

  (evil-define-key* 'motion global-map
    (kbd "SPC SPC") 'avy-goto-char-timer
    (kbd "SPC S-SPC") 'w--avy-goto-char-timer-any-window
    (kbd "S-SPC S-SPC") 'w--avy-goto-char-timer-any-window
    (kbd "SPC l") 'avy-goto-line
    (kbd "SPC L") 'w--avy-goto-line-any-window)

  ;; todo: all of this could use some rethinking and cleaning up
  (evil-define-key* 'normal global-map
    (kbd "SPC a") (lambda () (interactive) (avy-goto-char-timer) (call-interactively 'evil-append))
    (kbd "SPC A") (lambda () (interactive) (w--avy-evil-goto-end-of-line) (call-interactively 'evil-append-line))
    (kbd "SPC c") (lambda () (interactive) (avy-goto-line) (evil-first-non-blank) (call-interactively 'evil-change-line))
    (kbd "SPC C") 'w--avy-evil-change-region
    (kbd "SPC d") 'w--avy-evil-delete-line
    (kbd "SPC D") 'w--avy-evil-delete-region
    (kbd "SPC i") (lambda () (interactive) (avy-goto-char-timer) (call-interactively 'evil-insert))
    (kbd "SPC I") (lambda () (interactive) (avy-goto-line) (call-interactively 'evil-insert-line))
    (kbd "SPC o") (lambda () (interactive) (avy-goto-line) (call-interactively 'evil-open-below))
    (kbd "SPC O") (lambda () (interactive) (avy-goto-line) (call-interactively 'evil-open-above))
    (kbd "SPC p d") (lambda () (interactive) (next-line) (call-interactively 'avy-move-line))
    (kbd "SPC p D") (lambda () (interactive) (next-line) (call-interactively 'avy-move-region))
    (kbd "SPC P d") 'avy-move-line
    (kbd "SPC P D") 'avy-move-region
    (kbd "SPC p y") (lambda () (interactive) (next-line) (call-interactively 'avy-copy-line))
    (kbd "SPC p Y") (lambda () (interactive) (next-line) (call-interactively 'avy-copy-region))
    (kbd "SPC P y") 'avy-copy-line
    (kbd "SPC P Y") 'avy-copy-region
    (kbd "SPC $") 'w--avy-evil-goto-end-of-line)

  (w--make-hydra w--hydra-teleport nil
    "teleport"
    "_w_/_f_/_b_/_gf_ word"
    ("w" evilem--motion-function-evil-forward-word-begin)
    ("W" evilem--motion-function-evil-forward-WORD-begin)
    ("f" evilem--motion-function-evil-forward-word-end)
    ("F" evilem--motion-function-evil-forward-WORD-end)
    ("b" evilem--motion-function-evil-backward-word-begin)
    ("B" evilem--motion-function-evil-backward-WORD-begin)
    ("gf" evilem--motion-function-evil-backward-word-end)
    ("gF" evilem--motion-function-evil-backward-WORD-end)
    "_n_/_e_/_l_ line"
    ("e" evilem--motion-function-previous-line)
    ("E" avy-goto-line-above)
    ("n" evilem--motion-function-next-line)
    ("N" avy-goto-line-below)
    ("l" avy-goto-line)
    ("L" (avy-goto-line 4))
    "_t_/_j_/SPC char"
    ("SPC" avy-goto-char-timer)
    ("t" evilem--motion-evil-find-char)
    ("T" evilem--motion-evil-find-char-to)
    ("j" evilem--motion-evil-find-char-backward)
    ("J" evilem--motion-evil-find-char-to-backward))
  (evil-define-key* 'motion global-map
    (kbd "SPC") 'w--hydra-teleport/body))

(use-package evil-exchange
  :config
  (evil-exchange-install)
  ;; quickly swap two text objects using "gx"; the empty text object is
  ;; a trick to make "gxp" work to move previously marked text without
  ;; moving anything back to the original location.
  (evil-define-key* 'operator global-map "p" 'w--evil-empty-text-object))

(use-package evil-numbers
  :config
  (evil-define-key* 'normal global-map
    "+" 'evil-numbers/inc-at-pt
    "-" 'evil-numbers/dec-at-pt))

(use-package evil-surround
  :config
  (global-evil-surround-mode)
  ;; overwrite defaults to not put spaces inside braces
  (evil-add-to-alist
   'evil-surround-pairs-alist
   ?\( '("(" . ")")
   ?\[ '("[" . "]")
   ?\{ '("{" . "}")))

(use-package evil-visualstar
  :config
  (global-evil-visualstar-mode))


;;;; text objects

(use-package evil-args
  :bind
  (:map evil-inner-text-objects-map
   ("a" . evil-inner-arg)
   :map evil-outer-text-objects-map
   ("a" . evil-outer-arg)))

(use-package evil-indent-plus
  :config
  (evil-indent-plus-default-bindings))

(use-package evil-textobj-anyblock
  :bind
  (:map evil-inner-text-objects-map
   ("b" . evil-textobj-anyblock-inner-block)
   :map evil-outer-text-objects-map
   ("b" . evil-textobj-anyblock-a-block)))

(evil-define-text-object
  w--evil-text-object-whole-buffer (count &optional beg end type)
  "Text object for the whole buffer."
  (evil-range (point-min) (point-max) 'line))

(evil-define-text-object
  w--evil-empty-text-object (count &optional beg end type)
  "Empty text object."
  (evil-range (point) (point)))

(evil-define-text-object w--evil-text-object-symbol-dwim (count &optional beg end type)
  "Intelligently pick evil-inner-symbol or evil-a-symbol."
  (if (eq this-command 'evil-delete)
      (evil-a-symbol count)
    (evil-inner-symbol count)))

(evil-define-key* '(operator visual) global-map
  "o" 'w--evil-text-object-symbol-dwim
  (kbd "C-a") 'w--evil-text-object-whole-buffer)


;;;; scrolling

(setq
 indicate-buffer-boundaries 'left
 scroll-conservatively 101
 scroll-margin 5)

(w--make-hydra w--hydra-recenter (:foreign-keys nil)
  "recenter"
  "_b_ottom"
  ("b" evil-scroll-line-to-bottom)
  "_c_enter"
  ("c" evil-scroll-line-to-center)
  "_t_op"
  ("t" evil-scroll-line-to-top)
  "_z_ cycle"
  ("z" recenter-top-bottom nil :exit nil))

(evil-define-key* 'motion global-map
  (kbd "z z") #'w--hydra-recenter/recenter-top-bottom)


;;;; whitespace

(setq
 require-final-newline 'visit-save
 sentence-end-double-space nil)

(setq-default
 indent-tabs-mode nil
 show-trailing-whitespace t
 tab-width 4)

(use-package whitespace)

(use-package whitespace-cleanup-mode
  :config
  (global-whitespace-cleanup-mode)
  (w--hide-from-mode-line " WSC"))

(defun w--hide-trailing-whitespace ()
  "Helper to hide trailing whitespace, intended for mode hooks."
  (setq show-trailing-whitespace nil))

(add-hook 'buffer-menu-mode-hook 'w--hide-trailing-whitespace)

(defun w--toggle-show-trailing-whitespace ()
  "Toggle `show-trailing-whitespace`."
  (interactive)
  (setq show-trailing-whitespace (not show-trailing-whitespace)))

(use-package indent-guide
  :config
  (setq
   indent-guide-char "·"
   indent-guide-delay 0
   indent-guide-recursive t
   indent-guide-threshold 7)
  (indent-guide-global-mode)
  (set-face-attribute
   'indent-guide-face nil
   :inherit 'font-lock-comment-face)
  (w--hide-from-mode-line " ing"))


;;;; minibuffer

(use-package minibuffer
  :ensure nil
  :config
  (add-hook 'minibuffer-setup-hook #'w--hide-trailing-whitespace)
  (bind-keys
   :map minibuffer-local-map
   ("C-w" . backward-kill-word)
   ("C-u" . kill-whole-line))
  (--each (list minibuffer-local-map
                minibuffer-local-ns-map
                minibuffer-local-completion-map
                minibuffer-local-must-match-map
                minibuffer-local-isearch-map)
    (define-key it [escape] 'minibuffer-keyboard-quit)))


;;;; line navigation

(use-package relative-line-numbers
  :config
  (defun w--relative-line-numbers-format (offset)
    "Format relative line number for OFFSET."
    (number-to-string (abs (if (= offset 0) (line-number-at-pos) offset))))
  (setq relative-line-numbers-format 'w--relative-line-numbers-format))

(evil-define-motion w--evil-next-line (count)
  (if visual-line-mode
      (evil-next-visual-line count)
    (evil-next-line count)))

(evil-define-motion w--evil-previous-line (count)
  (if visual-line-mode
      (evil-previous-visual-line count)
    (evil-previous-line count)))

(evil-define-key* '(normal visual) global-map
  [remap evil-next-line] 'w--evil-next-line
  [remap evil-previous-line] 'w--evil-previous-line)


;;;; search

(use-package isearch
  :ensure nil
  :config
  (setq
   isearch-allow-prefix nil
   isearch-forward t  ;; initial direction; useful after swiper
   lazy-highlight-cleanup nil
   lazy-highlight-initial-delay 0.5
   lazy-highlight-max-at-a-time nil))

(use-package thingatpt
  :config
  (defun w--thing-at-point-dwim (&optional deactivate-selection move-to-beginning)
    "Return the active region or the symbol at point."
    (let ((thing))
      (cond
       ((region-active-p)
        (setq thing (buffer-substring-no-properties (region-beginning) (region-end)))
        (when move-to-beginning
          (goto-char (region-beginning))))
       (t
        (setq thing (thing-at-point 'symbol t))
        (when move-to-beginning
          (goto-char (beginning-of-thing 'symbol)))))
      (when deactivate-selection
        (deactivate-mark))
      thing)))

(use-package replace
  :ensure nil
  :config
  (defun w--query-replace-thing-at-point-dwim ()
    "Return 'query-replace' for the active region or the symbol at point."
    (interactive)
    (let* ((use-boundaries (not (region-active-p)))
           (thing (regexp-quote (w--thing-at-point-dwim t t)))
           (replacement
            (read-from-minibuffer
             (format "Replace ‘%s’ with: " thing)
             thing nil nil
             query-replace-to-history-variable)))
      (when use-boundaries
        (setq thing (format "\\_<%s\\_>" thing)))
      (message "%s" thing)
      (query-replace-regexp thing replacement)))
  (w--make-hydra w--hydra-replace nil
    "replace"
    "_p_roject"
    ("p" projectile-replace)
    ("P" projectile-replace-regexp)
    "_r_ dwim"
    ("r" w--query-replace-thing-at-point-dwim)
    "_s_ymbol"
    ("s" w--query-replace-thing-at-point-dwim)
    "_q_uery"
    ("q" query-replace)
    ("Q" query-replace-regexp)))

(use-package occur
  :ensure nil
  :init
  (provide 'occur)  ; fake feature since it is actually inside replace.el
  :config
  (evil-set-initial-state 'occur-mode 'motion)
  (evil-define-key* '(motion normal) occur-mode-map
    (kbd "RET") 'occur-mode-goto-occurrence
    (kbd "C-e") 'occur-prev
    (kbd "C-n") 'occur-next
    (kbd "C-p") 'occur-prev)

  (defun w--occur-mode-hook ()
    (toggle-truncate-lines t)
    (next-error-follow-minor-mode)
    (w--set-major-mode-hydra #'w--hydra-occur/body))
  (add-hook 'occur-mode-hook #'w--occur-mode-hook)

  (defun w--occur-dwim (&optional nlines)
    "Call `occur' with a sane default."
    (interactive "P")
    (let ((thing (read-string
                  "Open occur for regexp: "
                  (regexp-quote (or (w--thing-at-point-dwim) ""))
                  'regexp-history)))
      (occur thing nlines)
      (evil-force-normal-state)))

  (w--make-hydra w--hydra-occur nil
    "occur"
    "_n__e_ nav"
    ("n" occur-next :exit nil)
    ("e" occur-prev :exit nil)
    "_f_ollow"
    ("f" next-error-follow-minor-mode)))

(use-package swiper
  :config
  (evil-define-key* 'motion global-map
    "/" 'swiper
    "g/" 'evil-search-forward)
  (defun w--swiper-thing-at-point-dwim ()
    "Start `swiper` searching for the thing at point."
    (interactive)
    (let ((query (w--thing-at-point-dwim)))
      (evil-force-normal-state)  ; do not expand region in visual mode
      (swiper query)))
  (evil-define-key* 'visual global-map
    "/" 'w--swiper-thing-at-point-dwim))

(use-package ag
  :config
  (setq
   ag-project-root-function 'w--ag-project-root
   ag-reuse-buffers t)
  (add-hook 'ag-mode-hook (fn: toggle-truncate-lines t))

  (defun w--ag-project-root (directory)
    "Find project root for DIRECTORY; used for ag-project-root-function."
    (let ((default-directory directory))
      (projectile-project-root)))

  (defun w--counsel-ag-project (&optional unrestricted)
    "Run counsel-ag on the current project, defaulting to the symbol at point."
    (interactive)
    (counsel-ag
     (w--thing-at-point-dwim)
     (projectile-project-root)
     (if unrestricted "--unrestricted" "")
     (if unrestricted "search all project files" "search project files")))

  (defun w--counsel-ag-project-all-files ()
    "Run counsel-ag on all files within the project root."
    (interactive)
    (w--counsel-ag-project t))

  (w--make-hydra w--hydra-ag nil
    "ag"
    "_a_ project"
    ("a" ag-project)
    "_f_iles"
    ("f" ag-project-files)
    ("F" ag-files)
    "_g_ project"
    ("g" ag-project)
    ("G" ag)
    "_r_egex"
    ("r" ag-project-regexp)
    ("R" ag-regexp)))

(use-package highlight-symbol
  :config
  (setq
   highlight-symbol-idle-delay 1.0
   highlight-symbol-on-navigation-p t)
  (w--hide-from-mode-line " hl-s")

  (defun w--evil-paste-pop-or-highlight-symbol-prev (count)
    "Either paste-pop (with COUNT) or jump to previous symbol occurence."
    (interactive "p")
    (condition-case nil
        (evil-paste-pop count)
      (user-error
       (highlight-symbol-prev))))

  (defun w--evil-paste-pop-next-or-highlight-symbol-next (count)
    "Either paste-pop-next (with COUNT) or jump to next symbol occurence."
    (interactive "p")
    (condition-case nil
        (evil-paste-pop-next count)
      (user-error
       (highlight-symbol-next))))

  (evil-define-key* 'motion global-map
    (kbd "C-p") 'highlight-symbol-prev
    (kbd "C-n") 'highlight-symbol-next)

  (evil-define-key* 'normal global-map
    (kbd "C-p") 'w--evil-paste-pop-or-highlight-symbol-prev
    (kbd "C-n") 'w--evil-paste-pop-next-or-highlight-symbol-next))


;;;; previous/next navigation

;; previous/next thing (inspired by vim unimpaired)
;; todo: this should become a fancy hydra

(defun w--last-error ()
  "Jump to the last error; similar to 'first-error'."
  (interactive)
  (condition-case err (while t (next-error)) (user-error nil)))

(evil-define-key* 'motion global-map
  (kbd "[ SPC") (lambda () (interactive) (save-excursion (evil-insert-newline-above)))
  (kbd "] SPC") (lambda () (interactive) (save-excursion (evil-insert-newline-below)))
  "[b" 'evil-prev-buffer
  "]b" 'evil-next-buffer
  "[c" 'flycheck-previous-error
  "]c" 'flycheck-next-error
  "[C" 'flycheck-first-error
  "]C" 'w--flycheck-last-error
  "[d" (lambda () (interactive) (diff-hl-mode) (diff-hl-previous-hunk))
  "]d" (lambda () (interactive) (diff-hl-mode) (diff-hl-next-hunk))
  "[e" 'previous-error
  "]e" 'next-error
  "[E" 'first-error
  "]E" 'w--last-error
  "[m" 'smerge-prev
  "]m" 'smerge-next
  "[s" 'highlight-symbol-prev
  "]s" 'highlight-symbol-next
  "[S" 'highlight-symbol-prev-in-defun
  "]S" 'highlight-symbol-next-in-defun
  "[w" 'evil-window-prev
  "]w" 'evil-window-next
  "[z" 'outline-previous-visible-heading
  "]z" 'outline-next-visible-heading)


;;;; parens

(use-package smartparens
  :config
  (require 'smartparens-config)
  (smartparens-global-mode)
  (show-smartparens-global-mode)
  (w--hide-from-mode-line " SP"))

(use-package rainbow-delimiters)

(use-package highlight-parentheses
  :config
  (w--hide-from-mode-line " hl-p"))

(use-package evil-cleverparens
  :config
  (setq
   evil-cleverparens-swap-move-by-word-and-symbol t))

(use-package syntactic-close
  :config
  (evil-define-key* 'insert global-map
    ;; this is a zero, i.e. C-) without shift
    (kbd "C-0") #'syntactic-close))


;;;; filling

(w--hide-from-mode-line " Fill")

(defun w--evil-fill-paragraph-dwim ()
  "Fill the current paragraph."
  (interactive)
  ;; move point after comment marker; useful for multi-line comments.
  (save-excursion
    (end-of-line)
    (fill-paragraph)))

(evil-define-key* 'normal global-map
  "Q" 'w--evil-fill-paragraph-dwim)

(use-package fill-column-indicator
  :config
  (setq fci-rule-width 2))

(use-package multi-line)

(use-package visual-fill-column)


;;;; outline

(use-package outline
  :config
  (w--hide-from-mode-line " Outl"))


;;;; move lines

(use-package drag-stuff
  :config
  (evil-define-key* 'normal global-map
    (kbd "M-n") 'drag-stuff-down
    (kbd "M-e") 'drag-stuff-up
    (kbd "M-h") 'evil-shift-left-line
    (kbd "M-i") 'evil-shift-right-line)
  ;; todo: C-[hnei] in visual mode?
  (evil-define-key* 'visual global-map
    (kbd "M-h") (lambda (beg end)
                  (interactive "r")
                  (evil-shift-left beg end)
                  (evil-force-normal-state)
                  (call-interactively 'evil-visual-restore))
    (kbd "M-i") (lambda (beg end)
                  (interactive "r")
                  (evil-shift-right beg end)
                  (evil-force-normal-state)
                  (call-interactively 'evil-visual-restore))))


;;;; expand-region

(use-package expand-region
  :config
  (setq expand-region-fast-keys-enabled nil)
  (evil-define-key* 'visual global-map
    (kbd "TAB") 'w--hydra-expand-region/er/expand-region)
  (w--make-hydra w--hydra-expand-region nil
    "expand-region"
    "_<tab>_ expand"
    ("<tab>" er/expand-region :exit nil)
    "_u_ndo"
    ("u" (er/expand-region -1) :exit nil)
    "_r_eset"
    ("r" (er/expand-region 0) :exit t)))


;;;; narrowing

(defun w--narrow-dwim ()
  "Narrow (or widen) to defun or region."
  (interactive)
  (cond
   ((region-active-p)
    (narrow-to-region (region-beginning) (region-end))
    (deactivate-mark)
    (message "Showing region only"))
   ((buffer-narrowed-p)
    (widen)
    (message "Showing everything"))
   (t
    (narrow-to-defun)
    (message "Showing defun only"))))


;;;; copy-as-format

;; todo https://github.com/sshaw/copy-as-format/issues/2
(use-package copy-as-format
  :config
  (setq
   copy-as-format-default "slack"
   copy-as-format-format-alist  ;; only retain formats i use
   '(("github" copy-as-format--github)
     ("markdown" copy-as-format--markdown)
     ("rst" copy-as-format--rst)
     ("slack" copy-as-format--slack)))
  (evil-define-operator w--evil-copy-as-format (beg end type)
    "Evilified version of copy-as-format"
    :move-point nil
    :repeat nil
    (interactive "<R>")
    (save-excursion
      (goto-char beg)
      (when (eq type 'line)
        (beginning-of-line))
      (push-mark (point) t t)
      (goto-char end)
      (when (eq type 'line)
        (forward-line -1)
        (end-of-line))
      (let ((current-prefix-arg t))
        (copy-as-format))
      (pop-mark)))
  (evil-define-key* 'visual global-map
    "Y" #'w--evil-copy-as-format))


;;;; insert state

(defun w--evil-transpose-chars ()
  "Invoke 'transpose-chars' on the right chars in insert state."
  (interactive)
  (backward-char)
  (transpose-chars nil)
  (unless (eolp) (forward-char)))

(defun w--kill-line-dwim ()
  "Kill line, or join the next line when at eolp."
  (interactive)
  (let ((was-at-eol (eolp)))
    (kill-line)
    (when was-at-eol
      (fixup-whitespace))))

(evil-define-key* 'insert global-map
  (kbd "C-a") 'evil-first-non-blank
  (kbd "C-d") 'delete-char
  (kbd "C-e") 'end-of-line
  (kbd "C-h") [backspace]
  (kbd "C-k") 'w--kill-line-dwim
  ;; (kbd "C-n") 'next-line  ;; fixme: completion trigger
  (kbd "C-p") 'previous-line
  (kbd "C-t") 'w--evil-transpose-chars)

(evil-define-key* 'insert global-map
  ;; during typing, ctrl-v is "paste", like everywhere else
  (kbd "C-v") 'yank)

(evil-define-key* 'insert global-map
  ;; shift line with < and > (same chars as in normal mode;
  ;; used instead of standard vim bindings C-d and C-t.
  (kbd "C-,") 'evil-shift-left-line
  (kbd "C-<") 'evil-shift-left-line
  (kbd "C-.") 'evil-shift-right-line
  (kbd "C->") 'evil-shift-right-line)

;; indent on enter, keeping comments open (if any)
(evil-define-key* 'insert global-map
  (kbd "RET") 'comment-indent-new-line)

;; type numbers by holding alt using home row keys and by having a
;; "numpad overlay" starting at the home position for my right hand.
(--each (-zip-pair (split-string "arstdhneio'luy7890km" "" t)
                   (split-string "87659012345456789000" "" t))
  (-let [(key . num) it]
    (evil-define-key*
     'insert global-map
     (kbd (concat "M-" key))
     (lambda () (interactive) (insert num)))))


;;;; text case

(use-package string-inflection
  :config
  (w--make-hydra w--hydra-text-case
      (:post w--hydra-evil-repeat-record-command)
    "text case"
    "_c_ycle"
    ("c" string-inflection-all-cycle)
    ("`" string-inflection-all-cycle)
    ("~" string-inflection-all-cycle)
    "_a_ camel"
    ("a" string-inflection-camelcase)
    ("A" string-inflection-lower-camelcase)
    "_l_isp"
    ("l" string-inflection-lisp)
    "_s_nake"
    ("s" string-inflection-underscore)
    ("S" string-inflection-upcase)
    "_u_pper"
    ("u" string-inflection-upcase)))


;;;; projects

(use-package projectile
  :config
  (setq
   projectile-completion-system 'ivy
   projectile-ignored-projects '("/usr/local/")
   projectile-mode-line nil
   projectile-require-project-root nil
   projectile-sort-order 'recently-active)
  (projectile-mode)

  (defun w--projectile-find-file-all (&optional pattern)
    "Find any file in the current project, including ignored files."
    (interactive
     (list
      (read-string
       "file name pattern (empty means all): "
       (if buffer-file-name
           (concat (file-name-extension buffer-file-name) "$")
         "")
       ".")))
    (ivy-read
     "Find file in complete project: "
     (projectile-make-relative-to-root
      (directory-files-recursively (projectile-project-root) pattern))
     :action
     (lambda (filename)
       (find-file (concat
                   (file-name-as-directory (projectile-project-root))
                   filename)))
     :require-match t
     :history 'file-name-history))

  (w--make-hydra w--hydra-project nil
    "project"
    "_a_ny file"
    ("a" w--projectile-find-file-all)
    "_b_uffer"
    ("b" projectile-switch-to-buffer)
    ("B" projectile-switch-to-buffer-other-window)
    "_d_ir"
    ("d" projectile-find-dir)
    ("D" projectile-find-dir-other-window)
    "_f_ile"
    ("f" projectile-find-file)
    ("F" projectile-find-file-other-window)
    "_k_ill"
    ("k" projectile-kill-buffers)
    "_o_ccur"
    ("o" projectile-multi-occur)
    "_p_roject"
    ("p" projectile-switch-open-project)
    ("P" projectile-switch-project)
    "_r_eplace"
    ("r" projectile-replace)
    ("R" projectile-replace-regexp)
    "_s_ave"
    ("s" projectile-save-project-buffers)
    "_t_est/impl"
    ("t" projectile-toggle-between-implementation-and-test)
    ("T" projectile-find-implementation-or-test-other-window)
    "_-_ top dir"
    ("-" projectile-dired)
    "_/__?_ counsel-ag"
    ("/" w--counsel-ag-project)
    ("?" w--counsel-ag-project-all-files)
    "_!_ terminal"
    ("!" terminal-here-project-launch)))


;;;; jumping around

(use-package avy
  :config
  (setq
   avy-all-windows nil
   avy-all-windows-alt t
   avy-background t
   avy-keys (string-to-list "arstneio"))
  (avy-setup-default))

(use-package dired
  :ensure nil
  :config
  (evil-define-key* '(motion normal) dired-mode-map
    "-" 'dired-jump)) ;; inspired by vim vinagre

(defvar w--jump-commands
  '(evil-backward-paragraph
    evil-backward-section-begin
    evil-backward-section-end
    evil-forward-paragraph
    evil-forward-section-begin
    evil-forward-section-end
    evil-goto-first-line
    evil-goto-line
    evil-goto-mark
    evil-goto-mark-line
    evil-scroll-down
    evil-scroll-page-down
    evil-scroll-page-up
    evil-scroll-up
    evil-window-bottom
    evil-window-middle
    evil-window-top
    recenter-top-bottom
    switch-to-buffer))

(defvar w--jump-hooks
  '(evil-jumps-post-jump-hook
    focus-in-hook
    next-error-hook))

(defun w--mark-as-jump-commands (&rest commands)
  "Mark COMMANDS as jump commands."
  (setq w--jump-commands (-union w--jump-commands commands)))

(use-package nav-flash
  :config
  (add-hook 'post-command-hook #'w--maybe-nav-flash)
  (dolist (hook w--jump-hooks)
    (add-hook hook #'w--maybe-nav-flash))

  (defun w--maybe-nav-flash ()
    "Briefly highlight point when run after a jump command."
    (when (member this-command w--jump-commands)
      (nav-flash-show))))

(use-package dumb-jump
  :config
  (setq dumb-jump-selector 'ivy)
  (evil-define-key* 'motion global-map
    "gd" 'dumb-jump-go-current-window
    "gD" 'dumb-jump-go-other-window)

  (defun w--jump-around-advice (fn &rest args)
    ;; TODO: figure out whether the buffer changed. if the jump was in
    ;; the same buffer, check whether the target was already between
    ;; (window-start) and (window-end), and if so, avoid scrolling.
    (let ((original-buffer (current-buffer))
          (original-point (point))
          (original-window-start (window-start))
          (original-window-end (window-end)))
      (evil-set-jump)
      (apply fn args)
      (unless (and (eq (current-buffer) original-buffer)
                   (<= original-window-start (point) original-window-end))
        (recenter-top-bottom 0))
      (unless (and (eq (current-buffer) original-buffer)
                   (eq (point) original-point))
        (nav-flash-show))))
  (advice-add 'dumb-jump-go :around #'w--jump-around-advice))


;;;; window layout

;; my preferred window layout is full-height windows,
;; up to three next to each other in a horizontal fashion,
;; i.e. screen divided into columns.

(setq
 help-window-select t
 split-height-threshold nil
 split-width-threshold 120
 split-window-preferred-function 'visual-fill-column-split-window-sensibly
 evil-split-window-below t
 evil-vsplit-window-right t)

(defvar w--balanced-windows-functions
  '(delete-window quit-window split-window)
  "Commands that need to be adviced to keep windows balanced.")

(defun w--balance-windows-advice (&rest _ignored)
  "Balance windows (intended as ;after advice); ARGS are ignored."
  (balance-windows))

(define-minor-mode w--balanced-windows-mode
  "Global minor mode to keep windows balanced at all times."
  :global t
  (setq evil-auto-balance-windows w--balanced-windows-mode)
  (dolist (fn w--balanced-windows-functions)
    (if w--balanced-windows-mode
        (advice-add fn :after #'w--balance-windows-advice)
      (advice-remove fn #'w--balance-windows-advice)))
  (when w--balanced-windows-mode
    (balance-windows)))

(w--balanced-windows-mode)

(defun w--evil-window-next-or-vsplit ()
  "Focus next window, or vsplit if it is the only window in this frame."
  (interactive)
  (if (> (count-windows) 1)
      (evil-window-next nil)
    (evil-window-vsplit)))

(defun w--evil-goto-window (n)
  "Go to window N."
  (evil-window-top-left)
  (evil-window-next n))

(defun w--evil-goto-window-1 ()
  "Go to the first window."
  (interactive)
  (w--evil-goto-window 1))

(defun w--evil-goto-window-2 ()
  "Go to the second window."
  (interactive)
  (w--evil-goto-window 2))

(defun w--evil-goto-window-3 ()
  "Go to the third window."
  (interactive)
  (w--evil-goto-window 3))

(defun w--evil-goto-window-4 ()
  "Go to the fourth window."
  (interactive)
  (w--evil-goto-window 4))

(w--mark-as-jump-commands
 'w--evil-window-next-or-vsplit
 'w--evil-goto-window-1
 'w--evil-goto-window-2
 'w--evil-goto-window-3
 'w--evil-goto-window-4)

(cond
 ((eq system-type 'darwin)  ;; osx: command key
  (evil-define-key* 'motion global-map
    (kbd "s-1") 'w--evil-goto-window-1
    (kbd "s-2") 'w--evil-goto-window-2
    (kbd "s-3") 'w--evil-goto-window-3
    (kbd "s-4") 'w--evil-goto-window-4)
  (bind-keys
   ("s-1" . w--evil-goto-window-1)
   ("s-2" . w--evil-goto-window-2)
   ("s-3" . w--evil-goto-window-3)
   ("s-4" . w--evil-goto-window-4)))
 (t  ;; others: control key
  (evil-define-key* 'motion global-map
    (kbd "C-1") 'w--evil-goto-window-1
    (kbd "C-2") 'w--evil-goto-window-2
    (kbd "C-3") 'w--evil-goto-window-3
    (kbd "C-4") 'w--evil-goto-window-4)
  (bind-keys
   ("C-1" . w--evil-goto-window-1)
   ("C-2" . w--evil-goto-window-2)
   ("C-3" . w--evil-goto-window-3)
   ("C-4" . w--evil-goto-window-4))))

(use-package buffer-move)

(w--make-hydra w--hydra-window nil
  "window"
  "_h__n__e__i_ _1__2__3__4_ navigate"
  ("h" evil-window-left)
  ("n" evil-window-down)
  ("e" evil-window-up)
  ("i" evil-window-right)
  ("H" buf-move-left)
  ("N" buf-move-down)
  ("E" buf-move-up)
  ("I" buf-move-right)
  ("1" w--evil-goto-window-1)
  ("2" w--evil-goto-window-2)
  ("3" w--evil-goto-window-3)
  ("4" w--evil-goto-window-4)
  "_b_alance"
  ("b" balance-windows)
  ("=" balance-windows)  ;; evil/vim style
  "_c_lose"
  ("c" evil-window-delete)
  "_o_nly"
  ("o" delete-other-windows)
  "_r_otate"
  ("r" evil-window-rotate-downwards nil :exit nil)
  ("R" evil-window-rotate-upwards nil :exit nil)
  "_s_plit"
  ("s" evil-window-split)
  ("S" evil-window-new)
  "_v_split"
  ("v" evil-window-vsplit)
  ("V" evil-window-vnew)
  "_w_ cycle"
  ("w" w--evil-window-next-or-vsplit)
  ("C-w" w--evil-window-next-or-vsplit)
  "_+_/_-_ width"
  ("+" evil-window-increase-width nil :exit nil)
  ("-" evil-window-decrease-width nil :exit nil))

;; replace evil-window-map completely
(evil-define-key* '(emacs motion) global-map
  (kbd "C-w") 'w--hydra-window/body)


;;;; spelling

(use-package ispell
  :defer t
  :config
  (setq ispell-dictionary "english"))

;; todo https://github.com/d12frosted/flyspell-correct
;; (use-package flyspell)
;; (use-package flyspell-correct-ivy)

(use-package guess-language
  :config
  (setq guess-language-languages '(en de fr nl sv)))


;;;; completion

(defvar w--ivy-height-percentage 30
  "Percentage of the screen height that ivy should use.")

(use-package abbrev
  :ensure nil
  :config
  (w--hide-from-mode-line " Abbrev"))

(use-package flx)
(use-package smex)

(use-package ivy
  :demand t
  :bind
  (:map
   ivy-minibuffer-map
   ("C-h" . ivy-backward-delete-char)
   ("C-w" . ivy-backward-kill-word)
   ("C-u" . kill-whole-line)
   ("C-SPC" . ivy-avy)
   ("C-<return>" . ivy-dispatching-done-hydra))
  :config
  (setq
   ivy-count-format "(%d/%d) "
   ivy-height 20
   ivy-initial-inputs-alist nil
   ivy-wrap t)

  (ivy-mode 1)
  (w--hide-from-mode-line " ivy")

  (define-key ivy-minibuffer-map
    [escape] 'minibuffer-keyboard-quit) ;; fixme: use :bind perhaps?

  (add-hook 'window-size-change-functions #'w--adjust-ivy-height)

  (defun w--clamp-number (num low high)
    "Clamp NUM between LOW and HIGH."
    (min high (max num low)))

  (defun w--adjust-ivy-height (frame)
    "Adjust ivy-height based on the current FRAME height."
    (let* ((total-lines (frame-text-lines frame))
           (lines (truncate (* total-lines w--ivy-height-percentage 0.01)))
           (new-height (w--clamp-number lines 10 20)))
      (setq ivy-height new-height))))

(use-package ivy-hydra)

(use-package ivy-rich
  :config
  (dolist (command '(ivy-switch-buffer ivy-switch-buffer-other-window))
    (ivy-set-display-transformer
     command 'ivy-rich-switch-buffer-transformer)))

(use-package counsel
  :config
  (counsel-mode 1)
  (w--hide-from-mode-line " counsel"))

(use-package company
  :demand t
  :bind
  (:map
   company-active-map
   ("C-n" . company-select-next)
   ("C-p" . company-select-previous)
   ("C-<return>" . company-select-next))
  :config
  (setq
   company-auto-complete 'company-explicit-action-p
   company-dabbrev-code-everywhere t
   company-dabbrev-downcase nil
   company-dabbrev-ignore-case t
   company-idle-delay nil
   company-occurrence-weight-function 'company-occurrence-prefer-any-closest
   company-require-match nil
   company-selection-wrap-around t
   company-transformers '(company-sort-by-occurrence))
  (add-to-list 'company-auto-complete-chars ?\( )
  (add-to-list 'company-backends 'company-files)
  (w--hide-from-mode-line " company")
  (global-company-mode)
  (evil-define-key* 'insert global-map
    (kbd "C-<return>") 'company-manual-begin
    (kbd "C-n") 'company-manual-begin))


;;;; version control

(use-package autorevert
  :config
  (setq auto-revert-check-vc-info t)
  (w--hide-from-mode-line " ARev"))

(use-package magit
  :config
  (setq
   magit-branch-prefer-remote-upstream '("master")
   magit-branch-read-upstream-first nil
   magit-completing-read-function 'ivy-completing-read
   magit-popup-show-help-echo nil
   magit-prefer-remote-upstream t
   magit-process-popup-time 10
   magit-fetch-arguments '("--prune")
   magit-log-arguments '("--graph" "--color" "--decorate" "--follow" "-n256")
   magit-rebase-arguments '("--autostash")
   magit-tag-arguments '("--annotate"))
  (add-hook 'magit-popup-mode-hook 'w--hide-trailing-whitespace)

  (evil-define-key* '(normal visual) magit-mode-map
    [escape] nil)

  (defun w--magit-status-other-repository ()
    "Open git status for another repository."
    (interactive)
    (setq current-prefix-arg t)
    (call-interactively 'magit-status)))

(use-package evil-magit
  :config
  (defun w--magit-colemak-tweaks ()
    "Colemak tweaks for magit."
    (dolist (hook '(magit-status-mode-hook
                    magit-log-mode-hook))
      (add-hook hook #'w--disable-colemak))
    (dolist (map (list magit-mode-map
                       ;; fixme: more needed?
                       ;; magit-status-mode-map
                       ;; magit-log-mode-map
                       ;; magit-diff-mode-map
                       ))
      (evil-define-key* '(normal visual) map
        "n" #'evil-next-visual-line
        "e" #'evil-previous-visual-line)))
  (w--magit-colemak-tweaks))

(use-package magithub
  :after magit
  :config
  (setq magithub-pull-request-arguments '("-o"))
  (magithub-feature-autoinject t)
  (defun w--magithub-compare ()
    "Compare repository on the web; invokes hub."
    (interactive)
    (magithub--command-quick "compare")))

(use-package diff-hl
  :config
  (add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh)
  (w--mark-as-jump-commands
    'diff-hl-next-hunk
    'diff-hl-previous-hunk))

(w--make-hydra w--hydra-git nil
  "git"
  "_b_lame"
  ("b" magit-blame)
  ("B" magit-log-buffer-file)
  "_c_ommit"
  ("c" magit-commit)
  "_d_iff"
  ("d" magit-diff)
  "_f_ile"
  ("f" counsel-git)
  "_g_ popup"
  ("g" magit-dispatch-popup)
  "_l_og"
  ("l" magit-log-current)
  ("L" magit-log-all)
  "_r_efs"
  ("r" magit-show-refs-popup)
  "_s_tatus"
  ("s" magit-status)
  ("S" w--magit-status-other-repository)
  "_t_ lock"
  ("t" magit-toggle-buffer-lock)
  "_w_eb"
  ("w" magithub-browse)
  ("W" w--magithub-compare)
  "_!_ command"
  ("!" magit-git-command))

(w--make-hydra w--hydra-merge nil
  "merge"
  "_c_urrent"
  ("c" smerge-keep-current)
  "_m_ine"
  ("m" smerge-keep-mine)
  "_b_ase"
  ("b" smerge-keep-base)
  "_o_ther"
  ("o" smerge-keep-other)
  "_a_ll"
  ("a" smerge-keep-all)
  "go to"
  "_n_ext"
  ("n" 'smerge-next nil :exit nil)
  "_p_revious"
  ("e" 'smerge-prev nil :exit nil)
  ("p" 'smerge-prev nil :exit nil))


;;;; writeroom

(use-package writeroom-mode
  :config
  (setq
   writeroom-global-effects nil
   writeroom-maximize-window nil))

(defun w--writeroom-narrower ()
  "Make the writeroom column narrower."
  (interactive)
  (unless writeroom-mode
    (writeroom-mode))
  (writeroom-decrease-width))

(defun w--writeroom-wider ()
  "Make the writeroom column wider."
  (interactive)
  (unless writeroom-mode
    (writeroom-mode))
  (writeroom-increase-width))

(defun w--writeroom-reset ()
  "Reset the writeroom column width."
  (interactive)
  (unless writeroom-mode
    (writeroom-mode))
  (writeroom-adjust-width nil))


;;;; flycheck

(use-package flycheck
  :config
  (setq
   flycheck-checker-error-threshold 1000
   flycheck-display-errors-delay 1.0
   flycheck-idle-change-delay 3)

  (global-flycheck-mode)
  (w--hide-from-mode-line " FlyC")

  (defun w--flycheck-last-error ()
    "Jump to the last flycheck error."
    (interactive)
    (goto-char (point-max))
    (flycheck-previous-error))

  ;; todo: hydra for flycheck? ,c
  (w--make-hydra w--hydra-flycheck nil
    "flycheck"
    "_c_ errors"
    ("c" flycheck-list-errors)
    ("o" flycheck-list-errors)
    "_n_/_e_/_p_ nav"
    ("n" flycheck-next-error nil :exit nil)
    ("e" flycheck-previous-error nil :exit nil)
    ("p" flycheck-previous-error nil :exit nil)
    "_t_oggle"
    ("t" flycheck-mode)))

(use-package flycheck-cython)
(use-package flycheck-package)


;;;; toggles

(w--make-hydra w--hydra-toggle nil
  "toggle"
  "_b_ackgound"
  ("b" w--toggle-dark-light-theme)
  ("B" w--set-theme-from-environment)
  "_c_olemak"
  ("c" evil-colemak-basics-mode)
  "_d_iff"
  ("d" diff-hl-mode)
  "_f_ill"
  ("f" auto-fill-mode)
  ("F" fci-mode)
  "_l_ine"
  ("l" hl-line-mode)
  "_m_aximize"
  ("m" toggle-frame-maximized)
  ("M" toggle-frame-fullscreen)
  "_n_umber"
  ("n" (progn
         (relative-line-numbers-mode -1)
         (linum-mode 'toggle)))
  ("N" (progn
         (line-number-mode 'toggle)
         (column-number-mode 'toggle)))
  "_o_utline"
  ("o" outline-minor-mode)
  "_r_elative-number"
  ("r" (progn
         (linum-mode -1)
         (relative-line-numbers-mode 'toggle)))
  "_t_runcate"
  ("t" toggle-truncate-lines)
  "_v_isual-line"
  ("V" toggle-word-wrap)
  ("v" visual-line-mode)
  "_w_riteroom"
  ("w" writeroom-mode)
  ("W" (progn
         (delete-other-windows)
         (writeroom-mode 'toggle)))
  "_SPC_ whitespace"
  ("SPC" whitespace-mode)
  ("S-SPC" w--toggle-show-trailing-whitespace)
  "_1_ num/sym"
  ("1" global-evil-swap-keys-mode)
  ("!" global-evil-swap-keys-mode)
  "_=_ balanced-windows"
  ("=" w--balanced-windows-mode))


;;;; leader key

(w--make-hydra w--hydra-leader nil
  "_1__2__3__4_ window"
  ("1" w--evil-goto-window-1)
  ("2" w--evil-goto-window-2)
  ("3" w--evil-goto-window-3)
  ("4" w--evil-goto-window-4)
  "_a_g"
  ("a" w--hydra-ag/body)
  "_b_uffer"
  ("b" w--hydra-buffer/body)
  "_c_heck"
  ("c" w--hydra-flycheck/body)
  "_f_ind"
  ("f" w--hydra-find-file/body)
  "_g_it"
  ("g" w--hydra-git/body)
  "_h_ighlight"
  ("h" (highlight-symbol (w--thing-at-point-dwim)))
  ("H" highlight-symbol-remove-all)
  "_m_erge"
  ("m" w--hydra-merge/body)
  "_n_arrow"
  ("n" w--narrow-dwim)
  "_o_ccur"
  ("o" w--occur-dwim)
  "_p_roject"
  ("p" w--hydra-project/body)
  "_q_ bury buffer"
  ("q" bury-buffer)
  ("Q" unbury-buffer)
  "_r_eplace"
  ("r" w--hydra-replace/body)
  "_s_ave"
  ("s" save-buffer)
  ("S" save-some-buffers)
  "_t_oggle"
  ("t" w--hydra-toggle/body)
  "_u_niversal arg"
  ("u" universal-argument)
  "_w_indow"
  ("w" w--hydra-window/body)
  "M-_x_"
  ("x" counsel-M-x)
  "_y_ copy format"
  ("y" w--evil-copy-as-format)
  "_z_oom"
  ("z" w--hydra-zoom/body)
  "_SPC_ whitespace"
  ("SPC" whitespace-cleanup)
  "_,_ major mode"
  ("," w--major-mode-hydra)
  "_/_ search"
  ("/" w--swiper-thing-at-point-dwim)
  "_~_ case"
  ("~" w--hydra-text-case/body)
  ("`" w--hydra-text-case/body))

(evil-define-key* 'motion global-map
  "," #'w--hydra-leader/body
  "\\" #'w--hydra-leader/body)


;;;; custom

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror)


;;;; major modes

(setq-default major-mode 'text-mode)


;;;; major mode: text (generic)

(use-package typo
  :config
  (setq-default typo-language "prefer-single")
  (add-to-list 'typo-quotation-marks '("prefer-single" "‘" "’" "“" "”")))

(use-package text-mode
  :ensure nil
  :defer t
  :config
  (defun w--text-mode-hook ()
    (auto-fill-mode)
    (guess-language-mode)
    (visual-line-mode))
  (add-hook 'text-mode-hook 'w--text-mode-hook))


;;;; major mode: programming (generic)

(modify-syntax-entry ?_ "w")

(use-package fic-mode
  :config
  (setq
   fic-highlighted-words
   '("FIXME" "fixme"
     "TODO" "todo"
     "BUG" "bug"
     "XXX" "xxx")))

(use-package prog-mode
  :ensure nil
  :defer t
  :config
  (defun w--prog-mode-hook ()
    (abbrev-mode)
    (evil-swap-keys-swap-number-row)
    (auto-fill-mode)
    (column-number-mode)
    (fic-mode)
    ;; (show-paren-mode)  ; fixme: needed?
    (highlight-parentheses-mode)
    (highlight-symbol-mode))
  (add-hook 'prog-mode-hook 'w--prog-mode-hook))

;;;; major-mode: compilation and comint

(use-package compile
  :defer t
  :config
  (setq compilation-always-kill t)

  (defun w--compilation-mode-hook ()
    (w--hide-trailing-whitespace)
    (w--set-major-mode-hydra #'w--hydra-compilation/body))
  (add-hook 'compilation-mode-hook #'w--compilation-mode-hook)

  (defun w--compilation-finished (buffer status)
    (with-current-buffer buffer
      (evil-normal-state)))
  (add-hook 'compilation-finish-functions #'w--compilation-finished)

  (w--make-hydra w--hydra-compilation nil
    "compilation"
    "_r_ecompile"
    ("r" recompile)))

(use-package comint
  :defer t
  :ensure nil
  :config
  (setq comint-move-point-for-output 'all)
  (add-hook 'comint-mode-hook #'w--compilation-mode-hook)
  (evil-set-initial-state 'comint-mode 'insert)
  ;; fixme use :bind
  (define-key comint-mode-map
    (kbd "ESC") #'evil-normal-state)
  (evil-define-key*
   'normal comint-mode-map
   (kbd "C-e") 'comint-previous-prompt
   (kbd "C-n") 'comint-next-prompt
   (kbd "C-p") 'comint-previous-prompt)
  (evil-define-key*
   'insert comint-mode-map
   (kbd "RET") 'comint-send-input
   (kbd "C-n") 'comint-next-input
   (kbd "C-p") 'comint-previous-input))


;;;; major mode: emacs lisp

(use-package elisp-mode
  :defer t
  :ensure nil
  :config
  (defun w--emacs-lisp-mode-hook ()
    (setq evil-shift-width 2)
    (w--set-major-mode-hydra #'w--hydra-emacs-lisp/body)
    ;; (evil-cleverparens-mode)  ;; fixme: useless with colemak
    (rainbow-delimiters-mode))
  (add-hook 'emacs-lisp-mode-hook 'w--emacs-lisp-mode-hook)
  (w--make-hydra w--hydra-emacs-lisp nil
    "elisp"
    "_b_ eval-buffer"
    ("b" eval-buffer)
    "_d_ eval-defun"
    ("d" eval-defun)
    "_e_val-last-sexp"
    ("e" eval-last-sexp)
    "_r_ eval-region"
    ("r" eval-region)))


;;;; major mode: jinja

(use-package jinja2-mode
  :defer t
  :mode "\\.j2\\'")


;;;; major mode: json

(use-package json-mode
  :defer t
  :config
  (defun w--json-mode-hook ()
    (setq
     tab-width 2
     json-reformat:indent-width tab-width
     evil-shift-width tab-width)
    (evil-swap-keys-swap-colon-semicolon)
    (evil-swap-keys-swap-double-single-quotes)
    (evil-swap-keys-swap-square-curly-brackets))
  (add-hook 'json-mode-hook #'w--json-mode-hook))


;;;; major mode: markdown

(use-package markdown-mode
  :defer t
  :config
  (setq markdown-asymmetric-header t)
  (defun w--markdown-mode-hook ()
    (setq evil-shift-width 2)
    (evil-swap-keys-swap-double-single-quotes)
    (evil-swap-keys-swap-question-mark-slash)
    (typo-mode)
    (make-variable-buffer-local 'typo-mode-map)
    (define-key typo-mode-map "`" nil))
  (add-hook 'markdown-mode-hook 'w--markdown-mode-hook))


;;;; major mode: latex

;; fixme: optional auctex?
(setq TeX-engine 'xetex)


;;;; major mode: python

(use-package python
  :defer t
  :interpreter ("python" . python-mode)
  :config

  (dolist (open '("(" "{" "["))
    (sp-local-pair
     'python-mode open nil
     :unless '(sp-point-before-word-p)))

  (defun w--python-mode-hook ()
    (setq fill-column 72)
    (w--set-major-mode-hydra #'w--hydra-python/body)
    (evil-swap-keys-swap-colon-semicolon)
    (evil-swap-keys-swap-underscore-dash)
    (outline-minor-mode)
    (python-docstring-mode))

  (add-hook 'python-mode-hook 'w--python-mode-hook)

  (evilem-make-motion
   w--easymotion-python
   (list
    ;; Collect interesting positions around point, and all visible
    ;; blocks in the window. Results are ordered: forward after point,
    ;; then backward from point.
    'python-nav-end-of-statement 'python-nav-end-of-block 'python-nav-forward-block
    'python-nav-beginning-of-statement 'python-nav-beginning-of-block 'python-nav-backward-block)
   :pre-hook (setq evil-this-type 'line))

  (evil-define-key* 'motion python-mode-map
    (kbd "SPC TAB") 'w--easymotion-python)

  (defun w--swiper-python-definitions ()
    (interactive)
    (swiper "^\\s-*\\(def\\|class\\)\\s- "))

  (evil-define-key* 'motion python-mode-map
    (kbd "SPC /") 'w--swiper-python-definitions)

  (evil-define-operator w--evil-join-python (beg end)
    "Like 'evil-join', but handles comments and some continuation styles sensibly."
    :motion evil-line
    (evil-join beg end)
    (let ((first-line-is-comment (save-excursion
                                   (evil-first-non-blank)
                                   (looking-at-p "#")))
          (joined-line-is-comment (looking-at " #")))
      (if joined-line-is-comment
          (if first-line-is-comment
              ;; remove # when joining two comment lines
              (delete-region (point) (match-end 0))
            ;; pep8 mandates two spaces before inline comments
            (insert " ")
            (forward-char))
        (when (looking-at " \\\.")
          ;; remove space when the joined line starts with period, which
          ;; is a sensible style for long chained api calls, such as
          ;; sqlalchemy queries:
          ;;   query = (
          ;;       query
          ;;       .where(...)
          ;;       .limit(...)
          ;;       .offset(...))
          (delete-region (point) (1+ (point)))))))

  (evil-define-key* 'normal python-mode-map
    [remap evil-join] 'w--evil-join-python)

  (use-package evil-text-object-python
    :config
    (defun w--evil-forward-char-or-python-statement (count)
      "Intelligently pick a statement or a character."
      (interactive "p")
      (cond
       ((eq this-command 'evil-change)
        (evil-text-object-python-inner-statement count))
       ((memq this-command '(evil-delete evil-shift-left evil-shift-right))
        (evil-text-object-python-outer-statement count))
       (t (evil-forward-char count))))
    (evil-define-key* '(operator visual) python-mode-map
      "ul" 'evil-text-object-python-inner-statement
      "al" 'evil-text-object-python-outer-statement)
    (evil-define-key* 'operator python-mode-map
      [remap evil-forward-char] 'w--evil-forward-char-or-python-statement))

  (defun w--python-insert-statement-above (statement)
    "Insert a new STATEMENT above the statement at point"
    (python-nav-beginning-of-statement)
    (insert-before-markers
     (format
      "%s\n%s"
      statement
      (buffer-substring-no-properties  ;; copy indentation
       (line-beginning-position) (point))))
    (forward-line -1)
    (beginning-of-line-text))

  (defun w--python-insert-pdb-trace (pdb-module)
    "Insert a pdb trace statement using PDB-MODULE right before the current statement."
    (w--python-insert-statement-above
     (format "import %s; %s.set_trace()  # FIXME" pdb-module pdb-module)))

  (defun w--python-refactor-make-variable (beg end)
    "Refactor the current region into a named variable."
    (interactive "r")
    (let ((name (read-string "Variable name: "))
          (code (delete-and-extract-region beg end)))
      (insert name)
      (w--python-insert-statement-above
       (format "%s = %s" name code))))

  (defun w--python-insert-import-statement ()
    "Add an import statement for the thing at point."
    (interactive)
    (let ((thing (w--thing-at-point-dwim)))
      (w--python-insert-statement-above
       (format "import %s" thing))))

  (require 'w--pytest)
  (evil-set-initial-state 'w--pytest-mode 'insert)
  (add-hook 'w--pytest-finished-hooks #'evil-force-normal-state)

  (w--make-hydra w--hydra-python nil
    "python"
    "_b_reakpoint"
    ("b" (w--python-insert-pdb-trace "pdb") nil)
    ("B" (w--python-insert-pdb-trace "ipdb") nil)
    "_i_mport"
    ("i" w--python-insert-import-statement nil)
    "_l_ multi-line"
    ("l" multi-line nil)
    ("L" multi-line-single-line nil)
    "_t_ pytest"
    ("t" w--pytest nil)
    ("T" (w--pytest t) nil)
    "_v_ariable"
    ("v" w--python-refactor-make-variable nil))

  (evil-define-key* 'insert python-mode-map
    (kbd "C-l") 'multi-line)

  (evil-define-key* '(operator visual) python-mode-map
    "H" 'python-nav-backward-sexp-safe
    ;; "L" 'python-nav-forward-sexp-safe  ;; qwerty
    "I" 'python-nav-forward-sexp-safe))

(use-package python-docstring
  :defer t
  :config
  (w--hide-from-mode-line " DS")
  (setq python-fill-docstring-style 'symmetric))

(use-package pip-requirements
  :defer t
  :config
  ;; avoid network traffic when opening a requirements.txt file
  (setq pip-packages '(this is a fake package listing)))

(use-package cython-mode
  :defer t)


;;;; major-mode: restructuredtext

(use-package rst
  :defer t
  :config
  (setq
   rst-default-indent 0
   rst-indent-comment 2
   rst-indent-field 2
   rst-indent-literal-normal 2
   rst-preferred-adornments '((?= over-and-under 0)
                              (?= simple 0)
                              (?- simple 0)
                              (?~ simple 0)
                              (?+ simple 0)
                              (?` simple 0)
                              (?# simple 0)
                              (?@ simple 0))
   rst-preferred-bullets '(?- ?*))

  (defun w--rst-mode-hook ()
    (setq evil-shift-width 2)
    (w--set-major-mode-hydra #'w--hydra-rst/body)
    (modify-syntax-entry ?_ "w")
    (evil-swap-keys-swap-double-single-quotes)
    (evil-swap-keys-swap-question-mark-slash)
    (typo-mode)
    (make-variable-buffer-local 'typo-mode-map)
    (define-key typo-mode-map "`" nil))
  (add-hook 'rst-mode-hook 'w--rst-mode-hook)

  (evilem-make-motion
   w--easymotion-rst
   (list 'rst-forward-section 'rst-backward-section)
   :pre-hook (setq evil-this-type 'line))
  (evil-define-key* 'motion rst-mode-map
    (kbd "SPC TAB") 'w--easymotion-rst)

  (w--make-hydra w--hydra-rst nil
    "restructuredtext"
    "_a_djust"
    ("a" rst-adjust)))


;;;; major-mode: shell

(use-package sh-script
  :defer t
  :mode
  ("bashrc\\'" . sh-mode)
  ("\\.bashrc-.*\\'" . sh-mode)
  :config
  (defun w--sh-mode-hook ()
    (evil-swap-keys-swap-pipe-backslash))
  (add-hook 'sh-mode-hook 'w--sh-mode-hook))


;;;; major-mode: yaml

(use-package yaml-mode
  :defer t
  :config
  (message "yaml-mode config")
  (defun w--yaml-mode-hook ()
    (message "yaml-mode-hoom")
    (setq evil-shift-width yaml-indent-offset))
  (add-hook 'yaml-mode-hook 'w--yaml-mode-hook))


;;;; local configuration (not in version control)

(load "~/.emacs.d/init-local" t)


(provide 'init)
;;; init.el ends here

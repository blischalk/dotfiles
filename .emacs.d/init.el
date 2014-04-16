;;; init -- Emacs Initialization Settings

;;; Commentary:

;;; Code:


(when window-system
  (setq ns-pop-up-frames nil)
  (tool-bar-mode -1)                      ; No tool-bar
  (scroll-bar-mode -1))


(defun filter (pred lst)
  "Filter a list LST of elements with a given predicate PRED"
  (delq nil (mapcar (lambda (x) (and (funcall pred x) x)) lst)))


(require 'package)
(add-to-list 'package-archives '("MELPA" . "http://melpa.milkbox.net/packages/" ) t)
(add-to-list 'package-archives '("marmalade" . "http://marmalade-repo.org/packages/") t)
(package-initialize)

(defvar my-packages)
(setq my-packages
      '(auto-complete autopair cider color-theme zenburn-theme
		      goto-last-change haskell-mode
		      hy-mode main-line maxframe nrepl 
		      clojure-mode epl popup rainbow-delimiters 
		      smex undo-tree flycheck flycheck-hdevtools 
		      kibit-mode paredit auto-indent-mode))

;;;; Install my-packages as necessary
(let ((uninstalled-packages (filter (lambda (x) (not (package-installed-p x))) my-packages)))
  (when (and (not (equal uninstalled-packages '()))
	     (y-or-n-p (format "Install packages %s?"  uninstalled-packages)))
    (package-refresh-contents)
    (mapc 'package-install uninstalled-packages)))


(setq inhibit-splash-screen t          ; No splash screen
      initial-scratch-message nil)     ; No scratch message


(define-key emacs-lisp-mode-map (kbd "<s-return>") 'eval-last-sexp)  
(add-hook 'emacs-lisp-mode-hook 'flycheck-mode)                      ; flycheck-mode 
(add-hook 'emacs-lisp-mode-hook 'auto-indent-mode)                   ; auto-indent-mode 
(add-hook 'emacs-lisp-mode-hook
	  (lambda ()
	    (paredit-mode 1) 
	    (autopair-mode 0)))                                      ; incompatible with smartparens-mode


;; Autocomplete mode
(require 'auto-complete)
;;;; TODO: Does this work in Haskell??
(add-hook 'prog-mode-hook 'auto-complete-mode)


;;;; Clever hack so lambda shows up as λ
(font-lock-add-keywords
 'emacs-lisp-mode
 '(("(\\(lambda\\)\\>"
    (0 (prog1 ()
	 (compose-region (match-beginning 1)
			 (match-end 1)
			 ?λ))))))


;;;; Clojure goodness

;; Rainbow delimiters
(require 'rainbow-delimiters)
(add-hook 'prog-mode-hook 'rainbow-delimiters-mode)

;; show-paren-mode
(require 'paren)
(set-face-background 'show-paren-match "white")
(add-hook 'prog-mode-hook 'show-paren-mode)

;; Remember our place
(require 'saveplace)
(setq-default save-place t)
(setq save-place-file "~/.emacs.d/saved-places")

(add-hook 'clojure-mode-hook
          '(lambda ()
	     (paredit-mode 1)
             (define-key clojure-mode-map (kbd "C-c e") 'shell-eval-last-expression)
             (define-key clojure-mode-map (kbd "C-o j") 'cider-jack-in)
             (define-key clojure-mode-map (kbd "s-i") 'cider-eval-last-expression)
             (define-key clojure-mode-map (kbd "C-c x") 'shell-eval-defun)))


;; Keybindings

(global-set-key [S-deletechar]  'kill-ring-save)
;; Set up the keyboard so the delete key on both the regular keyboard
;; and the keypad delete the character under the cursor and to the right
;; under X, instead of the default, backspace behavior.
(global-set-key [delete] 'delete-char)
(global-set-key [kp-delete] 'delete-char)

(define-key function-key-map "\e[1~" [find])
(define-key function-key-map "\e[2~" [insertchar])
(define-key function-key-map "\e[3~" [deletechar])
(define-key function-key-map "\e[4~" [select])
(define-key function-key-map "\e[5~" [prior])
(define-key function-key-map "\e[6~" [next])
(define-key global-map [select] 'set-mark-command)
(define-key global-map [insertchar] 'yank)
(define-key global-map [deletechar] 'kill-region)

(global-unset-key "\C-o")  ; make this available as a personal prefix
(global-unset-key "\C- ")
(global-set-key "\C-@" 'other-window)
(global-set-key [?\C- ] 'other-window)
(global-set-key "\C-A" 'split-window-horizontally)
(global-set-key "\C-oa" 'split-window-vertically)
(global-set-key "\C-K" 'kill-line)
(global-set-key "\C-os" 'isearch-forward-regexp)
(global-set-key "\C-xS" 'sort-lines)
(global-set-key "\C-w" 'backward-kill-word)
(global-set-key "\C-x\C-k" 'kill-region)
(global-set-key "\C-c\C-k" 'kill-region)
(global-set-key "\C-ok" 'comment-region)
(global-set-key "\C-ou" 'uncomment-region)
(global-set-key "\C-oe" 'eval-current-buffer)
(global-set-key "\C-od" 'delete-horizontal-space)
(global-set-key "\C-of" 'forward-word)
(global-set-key "\C-ob" 'backward-word)
(global-set-key "\C-oq" 'query-replace-regexp)
(global-set-key "\C-on" 'flymake-goto-next-error)
(global-set-key "\C-]"  'fill-region)
(global-set-key "\C-ot" 'beginning-of-buffer)
(global-set-key "\C-N" 'enlarge-window)
(global-set-key "\C-o\C-n" 'enlarge-window-horizontally)
(global-set-key "\C-ol" 'goto-line)
(global-set-key "\C-ob" 'end-of-buffer)
(global-set-key "\C-op" 'fill-region)
(global-set-key "\C-og" 'save-buffers-kill-emacs)
(global-set-key "\C-od" 'downcase-region)
(global-set-key "\C-or" 'rgrep)
(global-set-key "\C-oo" 'overwrite-mode)
(global-set-key "\C-L" 'delete-other-windows)
(global-set-key "\C-B" 'scroll-down)
(global-set-key "\C-F" 'scroll-up)
(global-set-key "\C-V" 'save-buffer)
(global-set-key "\C-R" 'isearch-forward)
(global-set-key "\C-^" 'wnt-alog-add-entry)
(global-set-key "\C-T" 'set-mark-command)
(global-set-key "\C-Y" 'yank)
(global-set-key "\C-D" 'backward-delete-char-untabify)


                                        ;(global-set-key "\C-\\" 'term)
(global-set-key "\C-\\" 'shell)
                                        ;(global-set-key "\C-or" 'rename-buffer)
                                        ;(global-set-key "\C-Q" 'save-buffers-kill-emacs)
(global-set-key "\C-oi" 'quoted-insert)
(global-set-key "\e[1~" 'isearch-forward)
(global-set-key [select] 'set-mark-command)
(global-set-key [insertchar] 'yank)
(global-set-key [deletechar] 'kill-region)



                                        ;(global-set-key "\C-\\" 'term)
(global-set-key "\C-\\" 'shell)
                                        ;(global-set-key "\C-or" 'rename-buffer)
                                        ;(global-set-key "\C-Q" 'save-buffers-kill-emacs)
(global-set-key "\C-oi" 'quoted-insert)
(global-set-key "\e[1~" 'isearch-forward)
(global-set-key [select] 'set-mark-command)
(global-set-key [insertchar] 'yank)
(global-set-key [deletechar] 'kill-region)

(defun set-exec-path-from-shell-PATH ()
  "Set up Emacs' `exec-path' and PATH environment variable to match that used by the user's shell.
     This is particularly useful under Mac OSX, where GUI apps are not started from a shell."
  (interactive)
  (let ((path-from-shell (replace-regexp-in-string "[ \t\n]*$" "" (shell-command-to-string "$SHELL --login -i -c 'echo $PATH'"))))
    (setenv "PATH" path-from-shell)
    (setq exec-path (split-string path-from-shell path-separator))))

(when window-system
  (set-exec-path-from-shell-PATH)
  (global-set-key (kbd "s-=") 'text-scale-increase)
  (global-set-key (kbd "s--") 'text-scale-decrease))





(when window-system 
  (load-theme 'zenburn t))

(load-theme 'monokai t)

(evil-mode 1)
(provide 'init)
;;; init.el ends here

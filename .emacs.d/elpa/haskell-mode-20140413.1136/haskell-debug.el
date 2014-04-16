;;; haskell-debug.el --- Debugging mode via GHCi

;; Copyright (c) 2014 Chris Done. All rights reserved.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'cl)

(defmacro haskell-debug-with-breakpoints (&rest body)
  "Breakpoints need to exist to start stepping."
  `(if (haskell-debug-get-breakpoints)
       ,@body
     (error "No breakpoints to step into!")))

(defmacro haskell-debug-with-modules (&rest body)
  "Modules need to exist to do debugging stuff."
  `(if (haskell-debug-get-modules)
       ,@body
     (error "No modules loaded!")))

(define-derived-mode haskell-debug-mode
  text-mode "Debug"
  "Major mode for debugging Haskell via GHCi.")

(define-key haskell-debug-mode-map (kbd "g") 'haskell-debug/refresh)
(define-key haskell-debug-mode-map (kbd "s") 'haskell-debug/step)
(define-key haskell-debug-mode-map (kbd "d") 'haskell-debug/delete)
(define-key haskell-debug-mode-map (kbd "b") 'haskell-debug/break-on-function)
(define-key haskell-debug-mode-map (kbd "a") 'haskell-debug/abandon)
(define-key haskell-debug-mode-map (kbd "c") 'haskell-debug/continue)
(define-key haskell-debug-mode-map (kbd "p") 'haskell-debug/previous)
(define-key haskell-debug-mode-map (kbd "n") 'haskell-debug/next)
(define-key haskell-debug-mode-map (kbd "RET") 'haskell-debug/select)

(defvar haskell-debug-history-cache nil
  "Cache of the tracing history.")

(defvar haskell-debug-bindings-cache nil
  "Cache of the current step's bindings.")

(defun haskell-debug-session-debugging-p (session)
  "Does the session have a debugging buffer open?"
  (not (not (get-buffer (haskell-debug-buffer-name session)))))

(defun haskell-debug ()
  "Start the debugger for the current Haskell (GHCi) session."
  (interactive)
  (let ((session (haskell-session)))
    (switch-to-buffer-other-window (haskell-debug-buffer-name session))
    (unless (eq major-mode 'haskell-debug-mode)
      (haskell-debug-mode)
      (haskell-debug-start session))))

(defun haskell-debug/delete ()
  "Delete whatever's at the point."
  (interactive)
  (cond
   ((get-text-property (point) 'break)
    (let ((break (get-text-property (point) 'break)))
      (when (y-or-n-p (format "Delete breakpoint #%d?"
                              (plist-get break :number)))
        (haskell-process-queue-sync-request
         (haskell-process)
         (format ":delete %d"
                 (plist-get break :number)))
        (haskell-debug/refresh))))))

(defun haskell-debug/step (&optional expr)
  "Step into the next function."
  (interactive)
  (haskell-debug-with-breakpoints
   (let* ((breakpoints (haskell-debug-get-breakpoints))
          (context (haskell-debug-get-context))
          (string
           (haskell-process-queue-sync-request
            (haskell-process)
            (if expr
                (concat ":step " expr)
              ":step"))))
     (cond
      ((string= string "not stopped at a breakpoint\n")
       (if haskell-debug-bindings-cache
           (progn (setq haskell-debug-bindings-cache nil)
                  (haskell-debug/refresh))
         (call-interactively 'haskell-debug/start-step)))
      (t (let ((maybe-stopped-at (haskell-debug-parse-stopped-at string)))
           (cond
            (maybe-stopped-at
             (set (make-local-variable 'haskell-debug-bindings-cache)
                  maybe-stopped-at)
             (message "Computation paused.")
             (haskell-debug/refresh))
            (t
             (if context
                 (message "Computation finished.")
               (when (y-or-n-p "Computation completed without breaking. Reload the module and retry?")
                 (message "Reloading and resetting breakpoints...")
                 (haskell-interactive-mode-reset-error (haskell-session))
                 (loop for break in breakpoints
                       do (haskell-process-file-loadish
                           (concat "load " (plist-get break :path))
                           nil
                           nil))
                 (loop for break in breakpoints
                       do (haskell-debug-break break))
                 (haskell-debug/step expr)))))))))
   (haskell-debug/refresh)))

(defun haskell-debug/start-step (expr)
  "Start stepping EXPR."
  (interactive (list (read-from-minibuffer "Expression to step through: ")))
  (haskell-debug/step expr))

(defun haskell-debug/refresh ()
  "Refresh the debugger buffer."
  (interactive)
  (with-current-buffer (haskell-debug-buffer-name (haskell-session))
    (let ((inhibit-read-only t)
          (p (point)))
      (erase-buffer)
      (insert (propertize (concat "Debugging "
                                  (haskell-session-name (haskell-session))
                                  "\n\n")
                          'face `((:weight bold))))
      (let ((modules (haskell-debug-get-modules))
            (breakpoints (haskell-debug-get-breakpoints))
            (context (haskell-debug-get-context))
            (history (haskell-debug-get-history)))
        (unless modules
          (insert (propertize "You have to load a module to start debugging.\n\n"
                              'face
                              `((:foreground ,sunburn-red)))))
        (haskell-debug-insert-bindings modules breakpoints context)
        (when modules
          (haskell-debug-insert-current-context context history)
          (haskell-debug-insert-breakpoints breakpoints))
        (haskell-debug-insert-modules modules))
      (insert "\n")
      (goto-char (min (point-max) p)))))

(defun haskell-debug-break (break)
  "Set BREAK breakpoint in module at line/col."
  (haskell-process-queue-without-filters
   (haskell-process)
   (format ":break %s %s %d"
           (plist-get break :module)
           (plist-get (plist-get break :span) :start-line)
           (plist-get (plist-get break :span) :start-col))))

(defun haskell-debug-insert-current-context (context history)
  "Insert the current context."
  (haskell-debug-insert-header "Context")
  (if context
      (haskell-debug-insert-context context history)
    (haskell-debug-insert-debug-finished))
  (insert "\n"))

(defun haskell-debug-insert-debug-finished ()
  "Insert message that no debugging is happening, but if there is
some old history, then display that."
  (if haskell-debug-history-cache
      (progn (haskell-debug-insert-muted "Finished debugging.")
             (insert "\n")
             (haskell-debug-insert-history haskell-debug-history-cache))
    (haskell-debug-insert-muted "Not debugging right now.")))

(defun haskell-debug-insert-context (context history)
  "Insert the context and history."
  (when context
    (insert (propertize (plist-get context :name) 'face `((:weight bold)))
            (haskell-debug-muted " - ")
            (file-name-nondirectory (plist-get context :path))
            (haskell-debug-muted " (stopped)")
            "\n"))
  (when haskell-debug-bindings-cache
    (insert "\n")
    (let ((bindings haskell-debug-bindings-cache))
      (insert
       (haskell-debug-get-span-string
        (plist-get bindings :path)
        (plist-get bindings :span)))
      (insert "\n\n")
      (loop for binding in (plist-get bindings :types)
            do (insert (haskell-fontify-as-mode binding 'haskell-mode)
                       "\n"))))
  (let ((history (or history
                     (list (haskell-debug-make-fake-history context)))))
    (when history
      (insert "\n")
      (haskell-debug-insert-history history))))

(defun haskell-debug-insert-history (history)
  "Insert tracing HISTORY."
  (let ((i (length history)))
    (loop for span in history
          do (let ((string (haskell-debug-get-span-string
                            (plist-get span :path)
                            (plist-get span :span)))
                   (index (plist-get span :index)))
               (insert (propertize (format "%4d" i)
                                   'face `((:weight bold :background ,sunburn-bg+1)))
                       " "
                       (haskell-debug-preview-span
                        (plist-get span :span)
                        string
                        t)
                       "\n")
               (setq i (1- i))))))

(defun haskell-debug-make-fake-history (context)
  "Make a fake history item."
  (list :index -1
        :path (plist-get context :path)
        :span (plist-get context :span)))

(defun haskell-debug-preview-span (span string &optional collapsed)
  "Make a one-line preview of the given expression."
  (with-temp-buffer
    (haskell-mode)
    (insert string)
    (when (/= 0 (plist-get span :start-col))
      (indent-rigidly (point-min)
                      (point-max)
                      1))
    (font-lock-fontify-buffer)
    (when (/= 0 (plist-get span :start-col))
      (indent-rigidly (point-min)
                      (point-max)
                      -1))
    (goto-char (point-min))
    (if collapsed
        (replace-regexp-in-string
         "\n[ ]*"
         (propertize " " 'face `((:background ,sunburn-bg+1)))
         (buffer-substring (point-min)
                           (point-max)))
      (buffer-string))))

(defun haskell-debug-get-span-string (path span)
  "Get the string from the PATH and the SPAN."
  (save-window-excursion
    (find-file path)
    (buffer-substring
     (save-excursion
       (goto-char (point-min))
       (forward-line (1- (plist-get span :start-line)))
       (forward-char (1- (plist-get span :start-col)))
       (point))
     (save-excursion
       (goto-char (point-min))
       (forward-line (1- (plist-get span :end-line)))
       (forward-char (plist-get span :end-col))
       (point)))))

(defun haskell-debug-insert-bindings (modules breakpoints context)
  "Insert a list of bindings."
  (if breakpoints
      (progn (haskell-debug-insert-binding "s" "step into an expression")
             (haskell-debug-insert-binding "b" "breakpoint" t))
    (progn
      (when modules
        (haskell-debug-insert-binding "b" "breakpoint"))
      (when breakpoints
        (haskell-debug-insert-binding "s" "step into an expression" t))))
  (when breakpoints
    (haskell-debug-insert-binding "d" "delete breakpoint"))
  (when context
    (haskell-debug-insert-binding "a" "abandon context")
    (haskell-debug-insert-binding "c" "continue" t))
  (when context
    (haskell-debug-insert-binding "p" "previous step")
    (haskell-debug-insert-binding "n" "next step" t))
  (haskell-debug-insert-binding "g" "refresh" t)
  (insert "\n"))

(defun haskell-debug-insert-binding (binding desc &optional end)
  "Insert a helpful keybinding."
  (insert (propertize binding 'face `((:foreground ,sunburn-blue :weight bold)))
          (haskell-debug-muted " - ")
          desc
          (if end
              "\n"
            (haskell-debug-muted ", "))))

(defun haskell-debug/breakpoint-numbers ()
  "List breakpoint numbers."
  (interactive)
  (let ((breakpoints (mapcar (lambda (breakpoint)
                               (number-to-string (plist-get breakpoint :number)))
                             (haskell-debug-get-breakpoints))))
    (if (null breakpoints)
        (message "No breakpoints.")
      (message "Breakpoint(s): %s"
               (mapconcat #'identity
                          breakpoints
                          ", ")))))

(defun haskell-debug/abandon ()
  "Abandon the current computation."
  (interactive)
  (haskell-debug-with-breakpoints
   (haskell-process-queue-sync-request (haskell-process) ":abandon")
   (message "Computation abandoned.")
   (setq haskell-debug-history-cache nil)
   (setq haskell-debug-bindings-cache nil)
   (haskell-debug/refresh)))

(defun haskell-debug/continue ()
  "Continue the current computation."
  (interactive)
  (haskell-debug-with-breakpoints
   (haskell-process-queue-sync-request (haskell-process) ":continue")
   (message "Computation continued.")
   (setq haskell-debug-history-cache nil)
   (setq haskell-debug-bindings-cache nil)
   (haskell-debug/refresh)))

(defun haskell-debug/break-on-function ()
  "Break on function IDENT."
  (interactive)
  (haskell-debug-with-modules
   (let ((ident (read-from-minibuffer "Function: "
                                      (haskell-ident-at-point))))
     (haskell-process-queue-sync-request
      (haskell-process)
      (concat ":break "
              ident))
     (message "Breaking on function: %s" ident)
     (haskell-debug/refresh))))

(defun haskell-debug/select ()
  "Select whatever is at point."
  (interactive)
  (cond
   ((get-text-property (point) 'break)
    (let ((break (get-text-property (point) 'break)))
      (haskell-debug-highlight (plist-get break :path)
                               (plist-get break :span))))
   ((get-text-property (point) 'module)
    (let ((break (get-text-property (point) 'module)))
      (haskell-debug-highlight (plist-get break :path))))))

(defun haskell-debug/next ()
  "Go to next step to inspect bindings."
  (interactive)
  (haskell-debug-with-breakpoints
   (haskell-debug-navigate "forward")))

(defun haskell-debug/previous ()
  "Go to previous step to inspect the bindings."
  (interactive)
  (haskell-debug-with-breakpoints
   (haskell-debug-navigate "back")))

(defun haskell-debug-highlight (path &optional span)
  "Highlight the file at span."
  (let ((p (make-overlay
            (line-beginning-position)
            (line-end-position))))
    (overlay-put p 'face `((:background ,sunburn-bg+1)))
    (with-current-buffer
        (if span
            (save-window-excursion
              (find-file path)
              (current-buffer))
          (find-file path)
          (current-buffer))
      (let ((o (when span
                 (make-overlay
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line (1- (plist-get span :start-line)))
                    (forward-char (1- (plist-get span :start-col)))
                    (point))
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line (1- (plist-get span :end-line)))
                    (forward-char (plist-get span :end-col))
                    (point))))))
        (when o
          (overlay-put o 'face `((:background ,sunburn-bg+1))))
        (sit-for 0.5)
        (when o
          (delete-overlay o))
        (delete-overlay p)))))

(defun haskell-debug-insert-modules (modules)
  "Insert the list of modules."
  (haskell-debug-insert-header "Modules")
  (if (null modules)
      (haskell-debug-insert-muted "No loaded modules.")
    (progn (loop for module in modules
                 do (insert (propertize (plist-get module :module)
                                        'module module
                                        'face `((:weight bold)))
                            (haskell-debug-muted " - ")
                            (propertize (file-name-nondirectory (plist-get module :path))
                                        'module module)))
           (insert "\n"))))

(defun haskell-debug-insert-header (title)
  "Insert a header title."
  (insert (propertize title
                      'face `((:foreground ,sunburn-green)))
          "\n\n"))

(defun haskell-debug-insert-breakpoints (breakpoints)
  "Insert the list of breakpoints."
  (haskell-debug-insert-header "Breakpoints")
  (if (null breakpoints)
      (haskell-debug-insert-muted "No active breakpoints.")
    (loop for break in breakpoints
          do (insert (propertize (format "%d"
                                         (plist-get break :number))
                                 'face `((:weight bold))
                                 'break break)
                     (haskell-debug-muted " - ")
                     (propertize (plist-get break :module)
                                 'break break
                                 'break break)
                     (haskell-debug-muted
                      (format " (%d:%d)"
                              (plist-get (plist-get break :span) :start-line)
                              (plist-get (plist-get break :span) :start-col)))
                     "\n")))
  (insert "\n"))

(defun haskell-debug-insert-muted (text)
  "Insert some muted text."
  (insert (haskell-debug-muted text)
          "\n"))

(defun haskell-debug-muted (text)
  "Make some muted text."
  (propertize text 'face `((:foreground ,sunburn-grey+1))))

(defun haskell-debug-buffer-name (session)
  "The debug buffer name for the current session."
  (format "*debug:%s*"
          (haskell-session-name session)))

(defun haskell-debug-start (session)
  "Start the debug mode."
  (setq buffer-read-only t)
  (haskell-session-assign session)
  (haskell-debug/refresh))

(defun haskell-debug-split-string (string)
  "Split GHCi's line-based output, stripping the trailing newline."
  (split-string string "\n" t))

(defun haskell-debug-get-modules ()
  "Get the list of modules currently set."
  (let ((string (haskell-process-queue-sync-request
                 (haskell-process)
                 ":show modules")))
    (if (string= string "")
        (list)
      (mapcar #'haskell-debug-parse-module
              (haskell-debug-split-string string)))))

(defun haskell-debug-get-context ()
  "Get the current context."
  (let ((string (haskell-process-queue-sync-request
                 (haskell-process)
                 ":show context")))
    (if (string= string "")
        nil
      (haskell-debug-parse-context string))))

(defun haskell-debug-navigate (direction)
  "Navigate in DIRECTION \"back\" or \"forward\"."
  (let ((string (haskell-process-queue-sync-request
                 (haskell-process)
                 (concat ":" direction))))
    (let ((bindings (haskell-debug-parse-logged string)))
      (set (make-local-variable 'haskell-debug-bindings-cache)
           bindings)
      (when (not bindings)
        (message "No more %s results!" direction)))
    (haskell-debug/refresh)))

(defun haskell-debug-parse-logged (string)
  "Parse the logged breakpoint."
  (cond
   ((string= "no more logged breakpoints\n" string)
    nil)
   ((string= "already at the beginning of the history\n" string)
    nil)
   (t
    (with-temp-buffer
      (insert string)
      (goto-char (point-min))
      (list :path (progn (search-forward " at ")
                         (buffer-substring-no-properties
                          (point)
                          (1- (search-forward ":"))))
            :span (haskell-debug-parse-span
                   (buffer-substring-no-properties
                    (point)
                    (line-end-position)))
            :types (progn (forward-line)
                          (haskell-debug-split-string
                           (buffer-substring-no-properties
                            (point)
                            (point-max)))))))))

(defun haskell-debug-get-history ()
  "Get the step history."
  (let ((string (haskell-process-queue-sync-request
                 (haskell-process)
                 ":history")))
    (if (or (string= string "")
            (string= string "Not stopped at a breakpoint\n"))
        nil
      (if (string= string "Empty history. Perhaps you forgot to use :trace?\n")
          nil
        (let ((entries (mapcar #'haskell-debug-parse-history-entry
                               (remove-if (lambda (line) (or (string= "<end of history>" line)
                                                             (string= "..." line)))
                                          (haskell-debug-split-string string)))))
          (set (make-local-variable 'haskell-debug-history-cache)
               entries)
          entries)))))

(defun haskell-debug-parse-history-entry (string)
  "Parse a history entry."
  (if (string-match "^\\([-0-9]+\\)[ ]+:[ ]+\\([A-Za-z0-9_':]+\\)[ ]+(\\([^:]+\\):\\(.+?\\))$"
                    string)
      (list :index (string-to-number (match-string 1 string))
            :name (match-string 2 string)
            :path (match-string 3 string)
            :span (haskell-debug-parse-span (match-string 4 string)))
    (error "Unable to parse history entry: %s" string)))

(defun haskell-debug-parse-context (string)
  "Parse the context."
  (cond
   ((string-match "^--> \\(.+\\)\n  \\(.+\\)" string)
    (let ((name (match-string 1 string))
          (stopped (haskell-debug-parse-stopped-at (match-string 2 string))))
      (list :name name
            :path (plist-get stopped :path)
            :span (plist-get stopped :span))))))

(defun haskell-debug-get-breakpoints ()
  "Get the list of breakpoints currently set."
  (let ((string (haskell-process-queue-sync-request
                 (haskell-process)
                 ":show breaks")))
    (if (string= string "No active breakpoints.\n")
        (list)
      (mapcar #'haskell-debug-parse-break-point
              (haskell-debug-split-string string)))))

(defun haskell-debug-parse-stopped-at (string)
  "Parse the location stopped at from the given string.

For example:

Stopped at /home/foo/project/src/x.hs:6:25-36

"
  (let ((index (string-match "Stopped at \\([^:]+\\):\\(.+\\)\n?"
                             string)))
    (when index
      (list :path (match-string 1 string)
            :span (haskell-debug-parse-span (match-string 2 string))
            :types (cdr (haskell-debug-split-string (substring string index)))))))

(defun haskell-debug-parse-module (string)
  "Parse a module and path.

For example:

X                ( /home/foo/X.hs, interpreted )

"
  (if (string-match "^\\([^ ]+\\)[ ]+( \\([^ ]+?\\), [a-z]+ )$"
                    string)
      (list :module (match-string 1 string)
            :path (match-string 2 string))
    (error "Unable to parse module from string: %s"
           string)))

(defun haskell-debug-parse-break-point (string)
  "Parse a breakpoint number, module and location from a string.

For example:

[13] Main /home/foo/src/x.hs:(5,1)-(6,37)

"
  (if (string-match "^\\[\\([0-9]+\\)\\] \\([^ ]+\\) \\([^:]+\\):\\(.+\\)$"
                    string)
      (list :number (string-to-number (match-string 1 string))
            :module (match-string 2 string)
            :path (match-string 3 string)
            :span (haskell-debug-parse-span (match-string 4 string)))
    (error "Unable to parse breakpoint from string: %s"
           string)))

(defun haskell-debug-parse-span (string)
  "Parse a source span from a string.

Examples:

  (5,1)-(6,37)
  6:25-36
  5:20

People like to make other people's lives interesting by making
variances in source span notation."
  (cond
   ((string-match "\\([0-9]+\\):\\([0-9]+\\)-\\([0-9]+\\)"
                  string)
    (list :start-line (string-to-number (match-string 1 string))
          :start-col (string-to-number (match-string 2 string))
          :end-line (string-to-number (match-string 1 string))
          :end-col (string-to-number (match-string 3 string))))
   ((string-match "\\([0-9]+\\):\\([0-9]+\\)"
                  string)
    (list :start-line (string-to-number (match-string 1 string))
          :start-col (string-to-number (match-string 2 string))
          :end-line (string-to-number (match-string 1 string))
          :end-col (string-to-number (match-string 2 string))))
   ((string-match "(\\([0-9]+\\),\\([0-9]+\\))-(\\([0-9]+\\),\\([0-9]+\\))"
                  string)
    (list :start-line (string-to-number (match-string 1 string))
          :start-col (string-to-number (match-string 2 string))
          :end-line (string-to-number (match-string 3 string))
          :end-col (string-to-number (match-string 4 string))))
   (t (error "Unable to parse source span from string: %s"
             string))))

(provide 'haskell-debug)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions)
;; End:

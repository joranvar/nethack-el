;;; nethack.el -- run Nethack as an inferior process in Emacs
;;; Author: Ryan Yeske (rcyeske@sfu.ca)
;;; Date: Sat Mar 18 11:31:52 2000

;;; Requires: a copy of Nethack 3.3.x with the lisp window port


(require 'gamegrid)
(require 'nethack-api)
(require 'nethack-apix)
;;(require 'nethack-cmd)
;;(require 'nethack-keys)


(defvar nethack-status-line-number 0
  "The line that will be updated in the status window next time
nethack-api-putstr")

(defvar nethack-status-lines '("" . "")
  "The 2 lines of the status window")


(defun nethack ()
  "Start a game of Nethack.

The variable `nethack-program' is the name of the executable to run."
  (interactive)
  (if (and (processp nethack-process)
	   (eq (process-status nethack-process) 'run))
      (message "Nethack process already running...")

    (setq nethack-waiting-for-key-p nil) ;move these to nethack-mode
    (setq nethack-key-queue nil)

    (setq nethack-process (nethack-start-program))))


(defun nethack-quit ()
  "Quit nethack."
  (interactive)
  (kill-process nethack-process))

;;; Process code to communicate with the Nethack executable
(defvar nethack-process nil)

(defvar nethack-program "nethack"
  "* Program to run to start a game of Nethack.")

(defvar nethack-program-args nil
  "* Arguments to pass to `nethack-program'.")

(defvar nethack-process-buffer-name "*nethack-process*"
  "Name of the buffer used to communicate with `nethack-program'.")

(defvar nethack-process-name "nethack")

(defvar nethack-end-of-command-string "\n"
  "String used to terminate a command sent to a running Nethack
process.")

(defun nethack-start-program ()
  "Start `nethack-program' with `nethack-program-args' as an
asynchronous subprocess.  Returns a process object."
  (let ((proc (apply 'start-process nethack-process-name
		     nethack-process-buffer-name
		     nethack-program nethack-program-args)))
    (set-process-filter proc 'nethack-process-filter)
    proc))


(defun nethack-send-command (command)
  "Send a COMMAND to `nethack-process'."
  (nethack-process-send-string 
   (concat "(" command ")" nethack-end-of-command-string)))
				       

(defun nethack-process-send-string (string)
  "Send a STRING to the running `nethack-process'.  Appends a newline
char to the STRING."
  (let ((string-to-send (concat string "\n")))
    (if (and (processp nethack-process)
	     (eq (process-status nethack-process) 'run))
	(progn
	  ;; log the command in the process buffer
	  (nethack-log-string (concat "SEND: " string-to-send))

	  ;; send it...
	  (process-send-string nethack-process string-to-send))
      (error "Nethack process not running"))))


(defun nethack-process-filter (proc command)
  "Handle command output from `nethack-process' and copy the text to
the `nethack-process-buffer' for debugging."

  ;; log received command in the process-buffer
  (nethack-log-string (concat "RECV: " command))
	      
  ;; handle command
  (let ((retval (nethack-parse-command command)))
    (cond ((eq retval 'unimplemented)
	   (error "nethack: unimplemented function"))
	  ((eq retval 'no-retval)
	   nil)
	   ;;(message "nethack: no-retval: waiting for a key"))
	  (t 
	   (nethack-process-send-string (prin1-to-string retval))))))


(defun nethack-log-string (string)
  "Write STRING into `nethack-process-buffer'."
  (with-current-buffer (process-buffer nethack-process)
    (let ((moving (= (point) (process-mark nethack-process))))
      (save-excursion		       
	(goto-char (process-mark nethack-process))
	(insert string)
	(set-marker (process-mark nethack-process) (point)))
      (if moving (goto-char (process-mark nethack-process)))))())


(defun nethack-parse-command (command)
  "Parse and COMMAND and do it."
  ;;(message (concat "Parsing: " command))
  (eval (car (read-from-string command))))


;;; Buffer code (aka windows in Nethack)
(defvar nethack-buffer-name-alist
  '((nhw-message . "*nhw-message*")
    (nhw-status  . "*nhw-status*")
    (nhw-map     . "*nhw-map*")
    (nhw-menu    . "*nhw-menu*")
    (nhw-text    . "*nhw-text*"))
  "Buffer names for each window type.")

;; digit ids to send back and forth to nethack process to refer to
;; windows
(defvar nethack-buffer-id-alist
  '((0 . nhw-message)
    (1 . nhw-status)
    (2 . nhw-map)
    (3 . nhw-menu)
    (4 . nhw-text)))

(defun nethack-get-buffer (window)
  "Returns the buffer that corresponds to the Nethack WINDOW."
  (cdr (assq (cdr (assq window nethack-buffer-id-alist))
	     nethack-buffer-name-alist)))

;;; Main Map Buffer code
(defvar nethack-key-queue nil
  "List of strings to be sent to the running `nethack-process' in
response to the next call to `nethack-api-getch'.")

(defvar nethack-waiting-for-key-p nil
  "True if the nethack process is waiting for a key.")

(defun nethack-handle-key ()
  "If the nethack process is waiting for a key, send the key that
invoked this command, otherwise add the key to `nethack-key-queue' for
eventual delivery to the running nethack process."
  (interactive)
  (let ((key (this-command-keys)))
    (if nethack-waiting-for-key-p
	(progn
	  (nethack-process-send-string key)
	  (setq nethack-waiting-for-key-p nil))
      (setq nethack-key-queue
	    (append nethack-key-queue
		    (list key))))))

(defvar nethack-map-mode-map
  (let ((map (make-sparse-keymap)))
    (mapcar (lambda (x) 
	      (define-key map (char-to-string x) 'nethack-handle-key))
	    "1234567890-=!@#$%^&*()_+qwertyuiop[]QWERTYUIOP{}asdfghjkl;'ASDFGHJKL:\"zxcvbnm,./ZXCVBNM<>?`~|\\")
;;     (define-key map "h" 'nethack-handle-key)
;;     (define-key map "j" 'nethack-handle-key)
;;     (define-key map "k" 'nethack-handle-key)
;;     (define-key map "l" 'nethack-handle-key)
    map)
  "Keymap for nethack-map mode")

(defvar nethack-map-mode-hook nil
  "Functions to run after setting up the nethack-map mode.")

(defun nethack-map-mode ()
  "Major mode for the main Nethack map window."
  (kill-all-local-variables)
  (use-local-map nethack-map-mode-map)
  (setq mode-name "NETHACK MAP")
  (setq major-mode 'nethack-map-mode)
  (run-hooks nethack-map-mode-hook))
 

(defvar nethack-map-width 79 "Max width of the map")
(defvar nethack-map-height 22 "Max height of the map")

(defun nethack-create-buffer (type)
  "Create a buffer for a Nethack window of TYPE."
  (let ((buffer-name (cdr (assq type nethack-buffer-name-alist))))
    (get-buffer-create buffer-name)
    (save-excursion
      (set-buffer buffer-name)
      (setq buffer-read-only nil)
      (erase-buffer)
      (if (eq type 'nhw-map)
	  (nethack-setup-map-buffer buffer-name)))))


(defun nethack-setup-map-buffer (buffer-name)
  "Initialize the gamegrid and setup Nethack mode and keymap."
  (save-excursion
    (set-buffer buffer-name)
    (nethack-map-mode)
    (gamegrid-init (make-vector 256 nil))
    (gamegrid-init-buffer nethack-map-width 
			  nethack-map-height
			  ? )))

;;; Functions to manipulate, update and display the status window

(defun nethack-set-status-line (str)
  "Set the current status line (stored in nethack-status-line-number)
to str."
  (if (= nethack-status-line-number 0)
      (setcar nethack-status-lines str)
    (setcdr nethack-status-lines str)))

(defun nethack-print-status-lines ()
  "Updates the nhw-status window"
  (save-excursion
    (set-buffer (cdr (assq 'nhw-status nethack-buffer-name-alist)))
    (erase-buffer)
    (insert (car nethack-status-lines) "\n" (cdr nethack-status-lines))))
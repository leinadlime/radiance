#|
 This file is a part of Radiance
 (c) 2014 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:modularize-user)
(define-module simple-auth
  (:use #:cl #:radiance)
  (:implements #:auth))
(in-package #:simple-auth)

;; Out to config at some point
(defvar *salt* "dajke20090")

(defun auth:current (&optional (session *session*))
  (session:field session 'user))

(defun auth:associate (user &optional (session *session*))
  (setf (session:field session 'user) user)
  (trigger 'auth:associate session))

(defun auth:login! (&optional (landing-page (referer *request*)) (session *session*))
  (setf (session:field session 'landing-page)
        (etypecase landing-page
          (uri (uri-to-string landing-page :print-port T :print-request-domain T))
          (string landing-page)))
  (redirect #@"auth/login"))

(defun auth::set-password (user password)
  (setf (user:field user "simple-auth-hash")
        (cryptos:pbkdf2-hash password *salt*))
  (user:save user))

(defun auth::check-password (user password)
  (and (user:field user "simple-auth-hash")
       (string= (user:field user "simple-auth-hash")
                (cryptos:pbkdf2-hash password *salt*))
       T))

(define-page login #@"auth/^login" (:lquery (template "login.ctml"))
  (r-clip:process (lquery:$ (node)))
  (when (get-var "msg")
    (lquery:$ "#msg" (text (get-var "msg"))))
  (when (auth:current)
    (lquery:$ "body" (html "<h1>You are already logged in!</h1>"))
    (let ((landing (session:field *session* 'landing-page)))
      (when landing
        (redirect landing)))))

(define-page logout #@"auth/^logout" ()
  (session:end *session*)
  (redirect (or (session:field *session* 'landing-page) "/")))

(define-api simple-auth/login (username password &optional redirect) ()
  (flet ((err (message)
           (l:info :auth "Failed login for ~a." username)
           (cond
             (redirect
              (redirect (format NIL "~a?msg=~a" (referer *request*) message))
              (return-from simple-auth/login))
             (T (error message)))))
    (when (auth:current)
      (err "Already logged in."))
    (let ((user (user:get username)))
      (unless user
         (err "Invalid username or password."))
      (let ((hash (user:field user "simple-auth-hash")))
        (unless hash
          (err "Invalid username or password."))
        (cond
          ((string= hash (cryptos:pbkdf2-hash password *salt*))
           (auth:associate user)
           (if redirect
               (redirect (or (session:field *session* 'landing-page) "/"))
               (list :login "Successful")))
          (T
           (err "Invalid username or password.")))))))

(define-implement-hook admin
  (admin:define-panel password settings (:lquery (template "settings.ctml") :icon "fa-key" :tooltip "Change your login password.")
    (let ((info) (error)
          (user (auth:current)))
      (handler-case
          (when (string= (post-var "action") "Save")
            (unless (<= 8 (length (or (post-var "new") "")))
              (error "Password must be 8 characters or more."))
            (unless (auth::check-password user (or (post-var "old") ""))
              (error "Old password is invalid."))
            (unless (string= (or (post-var "new") "") (or (post-var "repeat") ""))
              (error "New password fields do not match."))
            (auth::set-password user (post-var "repeat"))
            (setf info "Password updated!"))
        (error (err)
          (setf error (princ-to-string err))))
      (r-clip:process T :info info :error error))))
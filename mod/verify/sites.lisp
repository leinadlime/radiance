#|
  This file is a part of TyNETv5/Radiance
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :radiance-mod-verify)

(define-condition auth-login-error (auth-error) ())
(define-condition auth-register-error (auth-error) ())

(core:define-page main-login #u"auth./login" (:lquery (template "verify/login.html"))
  (ignore-errors (auth:authenticate))
  (if (server:get "errortext") ($ "#error" (html (concatenate 'string "<i class=\"icon-remove-sign\"></i> " (server:get "errortext")))))
  (when (and *radiance-session* (not (auth:authenticated-p)))
    (session:end *radiance-session*)
    (setf *radiance-session* NIL))
  (if (or (not *radiance-session*) (session:temp-p *radiance-session*))
      (loop with target = ($ "#content")
            with panel = ($ "#panel ul")
            for mechanism being the hash-values of *verify-mechanisms*
            for name being the hash-keys of *verify-mechanisms*
            do ($ target (append (show-login mechanism)))
               ($ panel (append (lquery:parse-html (format NIL "<li class=\"~a\"><a>~:*~a</a></li>" name)))))
      ($ "#error" (html "<i class=\"icon-remove-sign\"></i> You are already logged in."))))
        
(core:define-page main-logout #u"auth./logout" ()
  (ignore-errors (auth:authenticate))
  (when *radiance-session*
    (user:action "Logout")
    (session:end *radiance-session*))
  (server:redirect (server:referer)))

(core:define-page main-register #u"auth./register" (:lquery (template "verify/register.html"))
  (ignore-errors (auth:authenticate))
  (if (server:get "errortext") ($ "#error" (html (concatenate 'string "<i class=\"icon-remove-sign\"></i> " (server:get "errortext")))))
  (loop with target = ($ "#content")
        with panel = ($ "#panel .logins ul")
        for name being the hash-keys of *verify-mechanisms*
        for mechanism being the hash-values of *verify-mechanisms*
        do ($ target (append (show-register mechanism)))
           ($ panel (append (lquery:parse-html (format NIL "<li class=\"~a\"><a>~:*~a</a></li>" name)))))
  (trigger :user :register-page))

(defgeneric page-login (module))
(defmethod page-login :around (module)
  (handler-case
      (call-next-method)
    (radiance-error (c)
      (server:redirect (format NIL "/login?errortext=~a&errorcode=~a" (slot-value c 'radiance::text) (slot-value c 'radiance::code)))))
  (server:redirect "/login"))

(defgeneric page-register (module))
(defmethod page-register :around (module)
  (handler-case
      (call-next-method)
    (radiance-error (c)
      (server:redirect (format NIL "/register?errortext=~a&errorcode=~a&panel=logins" (slot-value c 'radiance::text) (slot-value c 'radiance::code)))))
  (server:redirect "/register"))

(core:define-page register/finish #u"auth./register/finish"  ()
  (ignore-errors (auth:authenticate))
  (if (not *radiance-session*) (setf *radiance-session* (session:start-temp)))
  (if (server:posts)
      (session:field *radiance-session* "post-data" :value (server:posts)))
  (handler-case
      (server:with-posts (action username displayname email
                          hidden firstname address)
        (if (string= action "Register")
            (if (and username (> (length username) 0)
                     email (> (length email) 0) (email-p email))
                (let ((user (user:get username)))
                  (if (not (user:saved-p :user user))
                      (if (and (string= hidden "hidden")
                               (string= address "fixed")
                               (string= firstname ""))
                          (progn
                            (if (or (not displayname) (= (length displayname) 0))
                                (setf displayname username))
                            (user:field user "displayname" :value displayname)
                            (user:field user "register-date" :value (get-unix-time))
                            (user:field user "email" :value email)
                            (user:field user "secret" :value (make-random-string))
                            (user:field user "perms" :value (concatenate-strings (config-tree :verify :register :defaultperms) #\Newline))
                            (unless (loop for mechanism being the hash-values of *verify-mechanisms*
                                       if (handle-register mechanism user)
                                       collect it)
                              (error 'auth-register-error :text "At least one login required!" :code 19))
                            (v:debug :verify.user "Creating new user ~a" username)
                            (dm:insert (model user))
                            (user:action "Register" :public T :user user)
                            (session:end *radiance-session*)
                            (session:start username)
                            (server:redirect (make-uri (config-tree :verify :register :endpoint))))
                          (error 'auth-register-error :text "Hidden fields modified!" :code 18))
                      (error 'auth-register-error :text "Username already taken!" :code 17)))
                (error 'auth-register-error :text "Username and email required!" :code 16)))
        (error 'auth-register-error :text "Nothing to do!" :code 15))
    (radiance-error (err)
      (server:redirect (format nil "/register?errorcode=~a&errortext=~a&panel=profile" (slot-value err 'radiance::code) (slot-value err 'radiance::text))))))

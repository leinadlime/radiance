#|
  This file is a part of TyNETv5/Radiance
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :radiance-mod-trivial-profile)

(uibox:define-fill-function profile-link (model &optional (user model))
  (with-interface "user"
    (if (not (eq model user)) (setf user (uibox:parse-data user model)))
    (unless (stringp user) (setf user (user:field user "username")))
    (uri->context-url (make-uri (format NIL "user./~a" user)))))

(core:define-page profile #u"user./" (:lquery T)
  (ignore-errors (auth:authenticate))
  (let* ((username (if (= (length (path *radiance-request*)) 0)
                       (user:field (user:current :default (user:get "temp")) "username")
                       (path *radiance-request*)))
         (user (user:get username)))
    (if (user:saved-p :user user)
        (progn
          ($ (initialize (template "trivial-profile/profile.html")))
          (if (user:check "user.comment")
              ($ "#profile-comments-submit *[data-uibox]" (each #'(lambda (node) (uibox:fill-node node (user:current)))))
              ($ "#profile-comments-submit" (remove)))

          (let* ((parent ($ "#profile-details ul"))
                 (template ($ parent "li" (last) (remove) (node)))
                 (fields (db:select "trivial-profile" (db:query (:= "user" username)) :limit -1))
                 (color "null")
                 (background "null"))
            (db:iterate "trivial-profile-fields" (db:query (:= "public" "T"))
                        #'(lambda (row)
                            (loop with key = (cdr (assoc "field" row :test #'string=))
                                  for vrow in fields
                                  for field = (cdr (assoc "field" vrow :test #'string=))
                                  for value = (cdr (assoc "value" vrow :test #'string=))
                                  if (string-equal field "color")
                                    do (setf color value)
                                  else if (string-equal field "background")
                                         do (setf background value)
                                  else if (and (string= field key)
                                               (> (length value) 0))
                                         do (let ((clone ($ template (clone) (node))))
                                              ($ clone ".key" (text field))
                                              ($ clone ".value" (text value))
                                              ($ parent (append clone))))))
            ($ "body" (append (lquery:parse-html (format NIL "<script type=\"text/javascript\">customizeProfile(\"~a\", \"~a\");</script>" color (ppcre:regex-replace-all "\"" background "\\"))))))
          
          (uibox:fill-foreach (user:actions 10 :public T :user user) "#profile-actions ul li")
          (uibox:fill-foreach (dm:get "trivial-profile-comments" (db:query (:= "user" username)) :limit -1 :sort '(("time" . :DESC))) "#profile-comments ul li")
          ($ "*[data-uibox]" (each #'(lambda (node) (uibox:fill-node node user)))))
        (error-page 404))))
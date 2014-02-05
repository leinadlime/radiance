#|
  This file is a part of TyNETv5/Radiance
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :radiance-mod-verify)

(core:define-api user () (:access-branch "*")
  (when *radiance-session*
    (let ((user (session:user *radiance-session*)))
      (core:api-return 200 "Current user information"
                       :data (plist->hash-table
                              :username (user:field user "username")
                              :displayname (user:field user "displayname")
                              :email (user:field user "email")
                              :register-date (user:field user "register-date"))))))

(core:define-api user/search (query) ()
  (if (= (length query) 0)
      (error 'api-args-error :apicall "verify/user/search" :module :verify :text "Search query required." :code 1))
  (core:api-return 200 "Matching usernames"
                   :data (db:iterate "verify-users" (db:query (:matches "username" query))
                           #'(lambda (data) (plist->hash-table
                                             :username (cdr (assoc "username" data :test #'string-equal))
                                             :displayname (cdr (assoc "displayname" data :test #'string-equal)))))))

(core:define-api user/action (action) (:access-branch "*")
  (user:action action :public T)
  (core:api-return 200 "Action published"))

(core:define-api user/check (permission) (:access-branch "*")
  (core:api-return 200 "Permission check"
                   :data (plist->hash-table
                          :permission-branch permission
                          :check (not (null (user:check permission))))))

(core:define-api auth/login () ()
  )

(core:define-api auth/register () ()
  )

(core:define-api auth/logout () ()
  )

#|
 This file is a part of Radiance
 (c) 2014 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:modularize-user)
(define-module simple-users
  (:use #:cl #:radiance)
  (:implements #:user))
(in-package #:simple-users)

(defvar *user-cache* (make-hash-table :test 'equalp))
(defvar *default-permissions* ())

(define-trigger db:connected ()
  (db:create 'simple-users '((username (:varchar 32)) (permissions :text)) :indices '(username))
  (db:create 'simple-users-fields '((uid :integer) (field (:varchar 64)) (value :text)) :indices '(uid))
  (db:create 'simple-users-actions '((uid :integer) (time :integer) (public (:integer 1)) (action :text)) :indices '(uid))
  (user::sync))

(defclass user (user:user)
  ((username :initarg :username :initform (error "USERNAME required.") :accessor username)
   (id :initarg :id :initform (error "ID required.") :accessor id)
   (fields :initarg :fields :initform (make-hash-table :test 'equalp) :accessor fields)
   (permissions :initarg :permissions :initform () :accessor permissions)
   (modified :initarg :modified :initform () :accessor modified)))

(defmethod print-object ((user user) stream)
  (print-unreadable-object (user stream)
    (format stream "USER ~a~:[~; *~]" (username user) (modified user))))

(defmethod initialize-instance :after ((user user) &key)
  (dolist (branch *default-permissions*)
    (push branch (permissions user)))
  (save-perms user)
  (setf (gethash (username user) *user-cache*) user))

(defun ensure-user (thing)
  (etypecase thing
    (user:user thing)
    (string (user:get thing))))

(defun user:list ()
  (loop for user being the hash-values of *user-cache*
        collect user))

(defun user:get (username &key (if-does-not-exist NIL))
  (let ((username (string-downcase username)))
    (or (gethash username *user-cache*)
        (ecase if-does-not-exist
          (:create (user::create username))
          (:error (error 'user-not-found :user username))
          (:anonymous (user:get "anonymous"))
          ((NIL :NIL))))))

(defun user::create (username)
  (l:info :users "Creating new user ~s" username)
  (make-instance 'user
                 :username username
                 :id (db:insert 'simple-users `((username . ,username) (permissions . "")))))

(defun user:username (user)
  (username (ensure-user user)))

(defun user:fields (user)
  (loop for field being the hash-keys of (fields (ensure-user user))
        collect field))

(defun user:field (user field)
  (gethash (string field) (fields (ensure-user user))))

(defun (setf user:field) (value user field)
  (let ((user (ensure-user user)))
    (push (cons field (null (gethash field (fields user)))) (modified user))
    (setf (gethash field (fields user)) value)))

(defun user:save (user)
  (let ((user (ensure-user user)))
    (loop for (name . insert) = (pop (modified user))
          while name
          do (if insert
                 (db:insert 'simple-users-fields `((uid . ,(id user)) (field . ,name) (value . ,(gethash name (fields user)))))
                 (db:update 'simple-users-fields (db:query (:and (:= 'uid (id user)) (:= 'field name))) `((value . ,(gethash name (fields user)))))))
    user))

(defun user:saved-p (user)
  (not (modified (ensure-user user))))

(defun user:discard (user)
  (user::sync-user (user:username user)))

(defun user:remove (user)
  (let ((user (ensure-user user)))
    (trigger 'user:remove user)
    (db:remove 'simple-users-actions (db:query (:= 'uid (id user))))
    (db:remove 'simple-users-fields (db:query (:= 'uid (id user))))
    (db:remove 'simple-users (db:query (:= '_id (id user))))
    (setf (fields user) NIL
          (id user) NIL
          (permissions user) NIL
          (modified user) NIL)
    user))

(defun save-perms (user)
  (db:update 'simple-users (db:query (:= '_id (id user)))
             `((permissions . ,(format NIL "~{~{~a~^.~}~^~%~}" (permissions user))))))

(defun ensure-branch (branch)
  (etypecase branch
    (string (cl-ppcre:split "\\." branch))
    (list branch)))

(defun branch-matches (permission branch)
  (when (<= (length permission) (length branch))
    (loop for leaf-a in permission
          for leaf-b in branch
          always (string-equal leaf-a leaf-b))))

(defun branch-equal (a b)
  (loop for i in a for j in b
        always (string-equal (string i) (string j))))

(defun user:check (user branch)
  (let ((user (ensure-user user))
        (branch (ensure-branch branch)))
    (or (not branch)
        (loop for perm in (permissions user)
                thereis (branch-matches perm branch)))))

(defun user:grant (user branch)
  (let ((user (ensure-user user))
        (branch (ensure-branch branch)))
    (l:debug :users "Granting ~s to ~a." branch user)
    (pushnew branch (permissions user) :test #'branch-equal)
    (save-perms user)
    user))

(defun user:prohibit (user branch)
  (let ((user (ensure-user user))
        (branch (ensure-branch branch)))
    (l:debug :users "Prohibiting ~s from ~a." branch user)
    (setf (permissions user)
          (remove-if #'(lambda (perm) (branch-matches perm branch)) (permissions user)))
    (save-perms user)
    user))

(defun user:add-default-permission (branch)
  (pushnew (ensure-branch branch) *default-permissions*
           :test #'branch-equal))

(defun user:action (user action public)
  (let ((user (ensure-user user)))
    (db:insert 'simple-users-actions `((uid . ,(id user)) (time . ,(get-universal-time)) (public . ,(if public 1 0)) (action . ,action)))
    (trigger 'user:action user action public)
    user))

(defun user:actions (user n &key (public T) oldest-first)
  (let ((user (ensure-user user)))
    (db:iterate 'simple-users-actions (if public
                                          (db:query (:and (:= 'uid (id user)) (:= 'public 1)))
                                          (db:query (:and (:= 'uid (id user)))))
      #'(lambda (ta) (gethash "action" ta))
      :fields '(action) :amount n :sort `((time ,(if oldest-first :ASC :DESC))) :accumulate T)))

(defun user::sync-user (username)
  (with-model model ('simple-users (db:query (:= 'username username)))
    (let ((user (make-instance 'user
                               :id (dm:id model) :username (dm:field model "username")
                               :permissions (mapcar #'(lambda (b) (cl-ppcre:split "\\." b))
                                                    (cl-ppcre:split "\\n" (dm:field model "permissions"))))))
      (dolist (entry (dm:get 'simple-users-fields (db:query (:= 'uid (dm:id model)))))
        (let ((field (dm:field entry "field"))
              (value (dm:field entry "value")))
          (l:debug :users "Set field ~a of ~a to ~s" field user value)
          (setf (gethash field (fields user)) value)))
      user)))

(defun user::sync ()
  (setf *user-cache* (make-hash-table :test 'equalp))
  (let ((idtable (make-hash-table :test 'eql)))
    (dolist (model (dm:get 'simple-users (db:query :all)))
      (l:debug :users "Loading ~a" (dm:field model "username"))
      (setf (gethash (dm:id model) idtable)
            (make-instance 'user
                           :id (dm:id model) :username (dm:field model "username")
                           :permissions (mapcar #'(lambda (b) (cl-ppcre:split "\\." b))
                                                (cl-ppcre:split "\\n" (dm:field model "permissions"))))))
    ;; sync fields
    (dolist (entry (dm:get 'simple-users-fields (db:query :all)))
      (let ((field (dm:field entry "field"))
            (value (dm:field entry "value"))
            (uid (dm:field entry "uid")))
        (l:debug :users "Set field ~a of ~a to ~s" field (gethash uid idtable) value)
        (setf (gethash field (fields (gethash uid idtable))) value)))
    ;; ensure anonymous user
    (user:get :anonymous :if-does-not-exist :create)
    (l:info :users "Synchronized ~d users from database." (hash-table-count idtable))))

(defmethod field ((user user) field)
  (user:field user field))

(defmethod (setf field) (value (user user) field)
  (setf (user:field user field) value))

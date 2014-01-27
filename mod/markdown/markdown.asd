#|
  This file is a part of TyNETv5/Radiance
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :radiance)
(defpackage :org.tymoonnext.radiance.mod.markdown
  (:use :cl :radiance)
  (:nicknames :radiance-mod-markdown))
(in-package :radiance-mod-markdown)

(asdf:defsystem markdown
  :class :radiance-module
  :defsystem-depends-on (:radiance)
  :name "Markdown" 
  :author "Nicolas Hafner" 
  :version "0.0.1"
  :license "Artistic" 
  :homepage "http://tymoon.eu"
  :depends-on (:3bmd)
  :implement ((:parser :markdown))
  :components ((:file "parser")))

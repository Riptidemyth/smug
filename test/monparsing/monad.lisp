
(defpackage :drewc.org/smug/test/monparsing/monad
 (:use :cl)
 (:shadow #:satisfies
          #:char
          #:string))

(in-package :drewc.org/smug/test/monparsing/monad)

(eval-when (:compile-toplevel :load-toplevel :execute)

(defgeneric expand-interface-option (<interface> option-name &rest option-args)
  (:method (<interface> option-name &rest option-args)
    (declare (ignore option-args)) nil)
  (:method (interface-name (option-name (eql :singleton)) &rest option-args)
  (declare (ignore option-args))
  `(defvar ,interface-name
     (make-instance ',interface-name)))
  (:method (<interface> (option-name (eql :generic)) &rest option-args)
    (destructuring-bind (n args . rest) option-args
      `(defgeneric ,n ,args ,@rest))))

(defgeneric check-interface-option (<interface> 
                                    option-name &rest option-args)
  (:method (<interface> option-name &rest option-args)
    (declare (ignore <interface> option-name option-args)) 
    t)
  (:method (<interface> 
            (option-name (eql :generic)) &rest option-args)
     (c2mop:compute-applicable-methods-using-classes 
             (fdefinition (first option-args))
             (list (class-of <interface>)))))

(defmacro define-interface (name direct-superinterfaces direct-slots
                            &rest options)
  `(progn  
     (defclass ,name ,direct-superinterfaces ,direct-slots)
     ,@(loop :for (oname . args)  :in options
          :collect (apply #'expand-interface-option name oname args))
     (defmethod interface-options append ((<i> ,name))
                '(,@options))))

(defun check-interface-type (<interface>)
  (loop :for option :in (interface-options <interface>)
     :unless (apply #'check-interface-option <interface> option)
     :do (return nil)
     :finally (return t)))

(deftype interface ()
  `(satisfies check-interface-type))

(define-interface <interface> ()
  ()
  (:generic interface-options (<interface>)
            (:method-combination append)))

;; (macroexpand-1 '(define-interface <interface> ()
;;               ()
;;               (:generic interface-options (<interface>)
;;                (:method-combination append))))
;; =>
;; (PROGN
;;  (DEFCLASS <INTERFACE> NIL NIL)
;;  (DEFGENERIC INTERFACE-OPTIONS
;;      (<INTERFACE>)
;;    (:METHOD-COMBINATION APPEND))
;;  (DEFMETHOD INTERFACE-OPTIONS APPEND ((<I> <INTERFACE>))
;;    '((:GENERIC INTERFACE-OPTIONS (<INTERFACE>) 
;;        (:METHOD-COMBINATION APPEND)))))
  



(define-interface <monad> (<interface>)
  ()
  (:generic result (<interface> value))
  (:generic bind (<interface> monadic-value monadic-function)))

 
(define-interface <zero-plus> (<interface>)
  ()
  (:generic zero (<interface>))
  (:generic plus (<interface> 
                  interface-value-1
                  interface-value-2)))

(define-interface <monad-zero-plus> (<monad> <zero-plus>)
    ()
    (:generic guard (<interface> 
                     predicate value
                     &rest predicate-args)))

(defmethod guard ((<m> <monad-zero-plus>) 
                    predicate value
                    &rest predicate-args)
    (if (apply predicate value predicate-args)
        (result <m> value)
        (zero <m>)))


(define-interface <parser> (<monad-zero-plus>) 
  ()
  (:singleton)
  (:generic item (<parser>)))

(defmethod item ((<p> <parser>))
  (lambda (input)
    (etypecase input 
      (cl:null nil)
      (cl:string 
       (unless (string= input "")
         (list 
          (cons 
           (aref input 0)
           (subseq input 1))))))))

(defmethod result ((<p> <parser>) value)
  (lambda (input) (list (cons value input))))

(defmethod bind ((<p> <parser>) parser function)
  (lambda (input)
    (loop :for (value . input) 
       :in (funcall parser input)
       :append (funcall (funcall function value) input))))

(defmethod zero ((<p> <parser>))
   (constantly NIL))

(defmethod plus ((<p> <parser>) parser qarser)
  (lambda (input) 
    (append (funcall parser input)
            (funcall qarser input))))


(defmacro mlet* (monad bindings &body body)
  (if monad     
      (let ((m (gensym)))
        `(let ((,m ,monad))
           (flet ,(loop :for (name . args) 
                     :in (interface-options (symbol-value monad))
                     :when (and (eq name :generic)
                                (not (eq (first args) 
                                         'interface-options)))
                     :collect `(,(first args) (&rest args)
                                 (apply ',(first args) ,m args)))
             (mlet* nil ,bindings ,@body))))
      (if bindings 
          (destructuring-bind ((var form) &rest bindings)
              bindings
            `(bind ,form (lambda (,var) 
                           ,@(when (string= var "_")
                                  `((declare (ignorable ,var))))
    
                           (mlet* nil ,bindings
                                  ,@body))))
          `(progn ,@body))))  

(defun satisfies (predicate)
  (mlet* <parser> ((x (item)))
    (guard predicate x)))       

(mlet* <parser> ()
  
  (assert (equal '((1 . "asd"))
                 (funcall (result 1) "asd")))
  
  (assert (eq NIL (funcall (zero) "asd")))
  
  (assert (equal '((#\a . "sd"))
                 (funcall (item) "asd")))
  
  (assert (equal '((#\a . ""))
                 (funcall (item) "a")))
  
  (assert (null
           (funcall (item) "")))
  
  (defun char (x)
   (satisfies (lambda (y) (char= x y))))
  
  (defun digit ()
    (satisfies (lambda (x) 
                 (and (char<= #\0 x)
                      (char>= #\9 x)))))
  
  (defun lower ()
    (satisfies (lambda (x) 
                 (and (char<= #\a x)
                      (char>= #\z x)))))
  
  (defun upper ()
    (satisfies (lambda (x) 
                 (and (char<= #\A x)
                      (char>= #\Z x)))))
  

  (defun letter () (plus (lower) (upper)))
  (defun alphanum () (plus (letter) (digit)))
))

(defun string (string)
   (if (string= string "")
       (result <parser> nil)
       (mlet* <parser> 
         ((_ (char (aref string 0)))
          (_ (string (subseq string 1))))
        (result string))))
(assert (equal '(("hello" . " there"))
               (funcall (string "hello") 
                        "hello there")))

(assert (cl:null (funcall (string "hello") 
                          "helicopter")))

(defun many (parser)
    (mlet* <parser> ()
      (plus (mlet* <parser> 
                ((x parser)
                 (xs (many parser)))
              (result (cons x xs)))
            (result nil))))

(defun many1 (parser)
  (mlet* <parser>
      ((x parser)
       (xs (many parser)))
    (result (cons x xs))))

(defun word ()
  (many (letter)))


(assert (equal (funcall (word) "Yes!")
                  '(((#\Y #\e #\s) . "!") 
                    ((#\Y #\e) . "s!") 
                    ((#\Y) . "es!")
                    (NIL . "Yes!"))))


(assert (equal '(((#\a #\a #\a) . "b") 
                 ((#\a #\a) . "ab")
                 ((#\a) . "aab")
                 (NIL . "aaab"))
               (funcall (many (char #\a)) "aaab")))

(assert (equal '(((#\a #\a #\a) . "b") 
                 ((#\a #\a) . "ab") 
                 ((#\a) . "aab"))
               (funcall (many1 (char #\a)) "aaab")))  


(defun nat () 
  (mlet* <parser>
   ((xs (many1 (digit))))
  (result (read-from-string (coerce xs 'cl:string)))))


(assert (equal '((124 . "") (12 . "4") (1 . "24")) 
               (funcall (nat) "124")))  

(defun int ()
 (mlet* <parser> ()
   (plus (mlet* <parser>
             ((_ (char #\-))
              (n (nat)))
           (result (- n)))
         (nat))))  

(assert (and (equal (funcall (int) "12345")
                    '((12345 . "") (1234 . "5") (123 . "45") 
                      (12 . "345") (1 . "2345")))
             (equal (funcall (int) "-12345")
                    '((-12345 . "") (-1234 . "5") (-123 . "45") 
                      (-12 . "345") (-1 . "2345")))
             (cl:null (funcall (int) "#-12345"))))


(defun int ()
  (mlet* <parser> 
      ((op (plus (mlet* <parser> ((_ (char #\-)))
                   (result #'-))
                 (result #'identity)))           
       (n (nat)))
    (result (funcall op n))))

(assert (and (equal (funcall (int) "12345")
                    '((12345 . "") (1234 . "5") (123 . "45") 
                      (12 . "345") (1 . "2345")))
             (equal (funcall (int) "-12345")
                    '((-12345 . "") (-1234 . "5") (-123 . "45") 
                      (-12 . "345") (-1 . "2345")))
             (cl:null (funcall (int) "#-12345"))))


(defun ints () 
  (mlet* <parser> 
      ((_ (char #\[))
       (n (int))
       (ns (many (mlet* <parser>
                     ((_ (char #\,))
                      (x (int)))
                   (result x))))
       (_ (char #\])))
    (result (cons n ns))))    
 
(assert (equal (funcall (ints) "[1,234,567]")
               '(((1 234 567) . ""))))

(defun sepby1 (parser sep)
  (mlet* <parser>
     ((x parser)
      (xs (many (mlet* <parser> 
                 ((_ sep) 
                  (y parser))
                 (result y)))))
     (result (cons x xs))))
 
(defun ints ()
  (mlet* <parser> 
      ((_ (char #\[))
       (ns (sepby1 (int) (char #\,)))
       (_ (char #\])))
    (result ns)))


(assert (equal (funcall (ints) "[1,234,567]")
               '(((1 234 567) . ""))))

(defun)

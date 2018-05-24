#lang web-server
(require db)
(provide serve-login)

;; db connection for postgres
(define db-conn
  (virtual-connection
   (connection-pool
    (lambda ()
      (postgresql-connect
       #:user "postgres"
       #:password "postgres"
       #:database "postgres")))))

(define session-cache (make-hash))

(define (get-cookie uname pwd)
  (define uid (uname->uid uname))
  ;; TODO actually validate the pwd!
  (define new-cookie (symbol->string (gensym 'session)))
  (hash-set! session-cache new-cookie uid)
  new-cookie)

(define (check-cookie cookie)
  (hash-ref session-cache cookie))

(define (uname->uid uname)
  (query-value db-conn "SELECT id FROM users WHERE username = $1" uname))

(define (serve-login req)
  (define next-url
    (extract-binding/single
     'next
     (request-bindings req)))
  (define uname
    (extract-binding/single
     'uname (request-bindings req)))
  (define pwd
    (extract-binding/single
     'pwd (request-bindings req)))
  (define cookie (get-cookie uname pwd))
  (response/full
   302 #"Found"
   (current-seconds) TEXT/HTML-MIME-TYPE
   (list (make-header #"Location"
                      (string->bytes/utf-8 (string-append next-url
                                                          "?cookie="
                                                          cookie))))
   (list #"")))

;(define (serve-dashboard req)
;  (define bindings (request-bindings req))
;  (define cookie (extract-binding/single 'req))
;  (define uid (check-cookie cookie))
;  (
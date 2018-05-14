#lang racket
(require db)

;; db connection for postgres
(define db-conn
  (virtual-connection
   (connection-pool
    (lambda ()
      (postgresql-connect
       #:user "postgres"
       #:password "postgres"
       #:database "postgres")))))


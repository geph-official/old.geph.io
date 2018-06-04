#lang web-server
(require db
         "l10n.rkt"
         "paymentwall.rkt"
         web-server/templates
         racket/random
         file/sha1)
(provide serve-login
         serve-dashboard
         serve-buyplus
         serve-pingback)

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
  (define new-cookie (format "sess~a"
                              (bytes->hex-string (crypto-random-bytes 20))))
  (hash-set! session-cache new-cookie uid)
  new-cookie)

(define (check-cookie cookie)
  (hash-ref session-cache cookie))

(define (uname->uid uname)
  (query-value db-conn "SELECT id FROM users WHERE username = $1" uname))

(define (uid->uname uid)
  (query-value db-conn "SELECT username FROM users WHERE id = $1" uid))

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

(define PRICE-IN-EUROS 4)

(define (seconds->sql-timestamp secs)
  (let ([current-date (seconds->date secs #f)])
    (sql-timestamp (date-year current-date)
                   (date-month current-date)
                   (date-day current-date)
                   (date-hour current-date)
                   (date-minute current-date)
                   (date-second current-date)
                   0
                   #f)))

(define (make-invoice uid months)
  (query-value
   db-conn
   "INSERT INTO invoices (CreateTime, Paid, Amount, Currency, ID, Plan, PlanExpiry)
VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING InvoiceID"
   (seconds->sql-timestamp (current-seconds))
   #f
   (* PRICE-IN-EUROS months)
   "EUR"
   uid
   "plus"
   (seconds->sql-timestamp (+ (* months 2592000) (current-seconds)))))

(define (pay-invoice invoice-id)
  (query-exec
   db-conn
   "UPDATE invoices SET paid = true WHERE invoiceid = $1" invoice-id)
  (match (query-row db-conn
                    "SELECT id,plan,planexpiry FROM invoices WHERE invoiceid = $1"
                    invoice-id)
    [(vector user-id plan-id expires)
     (query-exec
      db-conn
      "INSERT INTO subscriptions (id, plan, expires) VALUES
 ($1, $2, $3) ON CONFLICT (id) DO UPDATE SET
plan = excluded.plan, expires = excluded.expires"
      user-id plan-id expires)]))

(define (serve-dashboard req)
  (define bindings (request-bindings req))
  (define cookie (extract-binding/single 'cookie bindings))
  (define uid (check-cookie cookie))
  (define uname (uid->uname uid))
  (parameterize ([current-website-language (request-language req)])
    (response/full 200
                   #"Okay"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   `()
                   (list (string->bytes/utf-8
                          (include-template "fragments/billing/dashboard.html"))))))

(define (in-transaction tx)
  (query-exec db-conn "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE")
  (with-handlers ([exn? (λ (e)
                          (query-exec db-conn "ROLLBACK")
                          (raise e))])
    (tx)
    (query-exec db-conn "COMMIT")))

(define (serve-pingback req)
  (let ([bindings (request-bindings req)]
        [type (extract-binding/single 'type req)]
        [invoice-id (extract-binding/single 'uid req)])
    (printf "Pingback for invoice ~a\n" invoice-id)
    (pay-invoice (string->number invoice-id))))

(define (serve-buyplus req)
  (define bindings (request-bindings req))
  (define cookie (extract-binding/single 'cookie bindings))
  (define uid (check-cookie cookie))
  (define months (string->number (extract-binding/single 'months bindings)))
  (define invoice-id (make-invoice uid months))
  (define payment-url
    (widget-url #:currency-code "USD"
                #:amount (* months 500)
                #:order-name (format "~a Plus" (l10n 'main.geph))
                #:order-id invoice-id
                #:payment-type "all"))
  
  (response/full 302
                 #"Found"
                 (current-seconds)
                 TEXT/HTML-MIME-TYPE
                 (list (make-header #"Location"
                                    (string->bytes/utf-8 payment-url)))
                 '()))
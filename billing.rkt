#lang web-server
(require db
         db/util/datetime
         "l10n.rkt"
         "paymentwall.rkt"
         "paymentwall-secrets.rkt"
         web-server/templates
         racket/random
         racket/date
         file/sha1)
(provide serve-login
         serve-dashboard
         serve-buyplus
         serve-pingback
         serve-plans
         serve-user-login)

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
                                                          cookie)))
         (make-header #"Cache-Control" #"no-store"))
   (list #"")))

(define PRICE-IN-USD 4.98)

(define (base-price)
  PRICE-IN-USD)

(define (currency-ticker)
  (cond
    [(equal? "zhs" (current-website-language)) "$"]
    [else "$"]))

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

(define (make-invoice uid months price code)
  (define base-seconds
    (match (query-rows db-conn
                       "SELECT expires FROM subscriptions WHERE id = $1" uid)
      [(list (vector expires)) (date->seconds (sql-datetime->srfi-date expires))]
      [else (current-seconds)]))
  (query-value
   db-conn
   "INSERT INTO invoices (CreateTime, Paid, Amount, Currency, ID, Plan, PlanExpiry)
VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING InvoiceID"
   (seconds->sql-timestamp (current-seconds))
   #f
   price
   code
   uid
   "plus"
   (seconds->sql-timestamp (+ (* months 2629800) base-seconds))))

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

(define (serve-user-login req)
  (parameterize ([current-website-language (request-language req)])
    (response/full 200
                   #"Okay"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   `()
                   (list (string->bytes/utf-8
                          (include-template "fragments/billing/login.html"))))))

(define (serve-plans req)
  (define bindings (request-bindings req))
  (parameterize ([current-website-language (request-language req)])
    (response/full 200
                   #"Okay"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   `(,(make-header #"Cache-Control" #"no-store"))
                   (list (string->bytes/utf-8
                          (include-template "fragments/billing/plans.html"))))))

(define (serve-dashboard req)
  (define bindings (request-bindings req))
  (define cookie (extract-binding/single 'cookie bindings))
  (define uid (check-cookie cookie))
  (define user-subscription
    (let ([rows (query-rows db-conn
                            "SELECT plan,expires FROM subscriptions WHERE id = $1" uid)])
      (match rows
        [(list (vector plan-name expiry)) (cons plan-name expiry)]
        [_ "free"])))

  (in-transaction
   (lambda ()
     (parameterize ([current-website-language (request-language req)])
       (date-display-format (if (equal? (current-website-language) "en")
                                'american
                                'chinese))
       (response/full 200
                      #"Okay"
                      (current-seconds)
                      TEXT/HTML-MIME-TYPE
                      (list (make-header #"Cache-Control" #"no-store"))
                      (list (string->bytes/utf-8
                             (include-template "fragments/billing/dashboard.html"))))))))

(define (in-transaction tx)
  (query-exec db-conn "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE")
  (with-handlers ([exn? (λ (e)
                          (query-exec db-conn "ROLLBACK")
                          (raise e))])
    (define res (tx))
    (query-exec db-conn "COMMIT")
    res))


(define (serve-pingback req secret)
  (unless (equal? secret pw-skey)
    (error "unauthorized"))
  (with-handlers ([exn:fail? void])
    (let* ([bindings (request-bindings req)]
           [type (extract-binding/single 'type bindings)]
           [invoice-id (extract-binding/single 'uid bindings)])
      (pay-invoice (string->number invoice-id))))
  (response/full 200
                 #"OK"
                 (current-seconds)
                 TEXT/HTML-MIME-TYPE
                 (list (make-header #"Cache-Control" #"no-store"))
                 '(#"OK")))

(define (serve-buyplus req)
  (parameterize ([current-website-language (request-language req)])
    (define bindings (request-bindings req))
    (define cookie (extract-binding/single 'cookie bindings))
    (define uid (check-cookie cookie))
    (define months (string->number (extract-binding/single 'months bindings)))
    (define price-multiplier
      (cond
        [(< months 6) 2]
        [(< months 12) 1.5]
        [else 1]))
    (define-values (price code)
      (values (* months PRICE-IN-USD price-multiplier) "USD"))
    (define invoice-id (make-invoice uid months (exact-round (* price 100)) code))
    (define payment-url
      (widget-url #:currency-code code
                  #:amount (* price 100)
                  #:order-name (format "~a Plus" (l10n 'main.geph))
                  #:order-id invoice-id
                  #:payment-type "all"
                  #:language (lang->standard-lang (current-website-language))
                  #:success-url (format "https://geph.io/billing/dashboard?cookie=~a"
                                        cookie)))

    (response/full 302
                   #"Found"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   (list (make-header #"Location"
                                      (string->bytes/utf-8 payment-url))
                         (make-header #"Cache-Control" #"no-store"))
                   '())))

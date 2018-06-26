#lang racket
(require web-server/templates
         web-server/dispatch
         web-server/servlet
         web-server/servlet-env
         "billing.rkt"
         "l10n.rkt")
(require (for-syntax racket))

(define (auto-jump req)
  (parameterize ([current-website-language (request-language req)])
    (response/full 302
                   #"Found"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   (list (make-header #"Location"
                                      (match (current-website-language)
                                        ["zhs" #"/zhs"]
                                        [(regexp #rx"^zh") #"/zht"]
                                        [_ #"/en"]))
                         (make-header #"Vary" #"Accept-Language"))
                   '())))

(define exit-global (exit-handler))

(define (description language)
  (define is-mirror? #f)
  (lambda _
    (parameterize ([current-website-language language])
      (displayln (current-website-language))
      (define lang (current-website-language))
      (response/full 200
                     #"Okay"
                     (current-seconds)
                     TEXT/HTML-MIME-TYPE
                     `()
                     (list (string->bytes/utf-8
                            (include-template "fragments/main/description.html")))))))

(define-values (page-dispatch url)
  (dispatch-rules
   (("billing") serve-user-login)
   [("billing" "login") serve-login]
   [("billing" "dashboard") serve-dashboard]
   [("billing" "plans") serve-plans]
   [("billing" "buyplus") serve-buyplus]
   [("billing" "pingback" (string-arg)) serve-pingback]
   [("en") (description "en")]
   [("zht") (description "zht")]
   [("zhs") (description "zhs")]
   [("") auto-jump]))

(serve/servlet page-dispatch
               #:launch-browser? #f
               #:servlet-regexp #rx""
               #:extra-files-paths (list "./static/"))
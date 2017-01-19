#lang racket
(require web-server/templates
         web-server/dispatch
         web-server/servlet
         web-server/servlet-env)

(define (auto-jump req)
  (define best-lang
    (with-handlers ([exn:fail? (λ e #'(displayln e) #f)])
      (string-trim
       (first (string-split
              (extract-binding/single 'accept-language
                                      (request-headers req)) ",")))))
  #;(printf "best lang is ~a\n" best-lang)
  (response/full 302
                 #"Found"
                 (current-seconds)
                 TEXT/HTML-MIME-TYPE
                 (list (make-header #"Location"
                                    (match best-lang
                                      ["zh-CN" #"/zhs"]
                                      [(regexp #rx"^zh") #"/zht"]
                                      [_ #"/en"]))
                       (make-header #"Vary" #"Accept-Language"))
                 '()))

(define exit-global (exit-handler))

(define (description lang)
  (define is-mirror? #f)
  (lambda _
    (response/full 200
                   #"Okay"
                   (current-seconds)
                   TEXT/HTML-MIME-TYPE
                   `()
                   (list (string->bytes/utf-8
                          (include-template "description.html"))))))

(define-values (page-dispatch url)
  (dispatch-rules
   [("restart-servlet") (λ _ (thread (lambda() (sleep 1)
                                       (exit-global 0)))
                          (response/full 200 #"Okay" (current-seconds)
                                         TEXT/HTML-MIME-TYPE
                                         '()))]
   [("en") (description "en")]
   [("zht") (description "zht")]
   [("zhs") (description "zhs")]
   [("") auto-jump]))

(serve/servlet page-dispatch
               #:launch-browser? #f
               #:servlet-regexp #rx""
               #:extra-files-paths (list "./static/"))
#lang racket
(require web-server/templates)

(define (generate-mirror)
  (define is-mirror? #t)
  (define source-code
    (let ([lang "zhs"])
      (include-template "fragments/main/description.html")))
  ;; replace download URLs
  (regexp-replace* #rx"dl.geph.io"
                   source-code
                   "s3-ap-southeast-1.amazonaws.com/geph-mirror-sgp/dl"))

(with-output-to-file #:exists 'replace "ZHS-STATIC.html"
  (lambda() (display (generate-mirror))))

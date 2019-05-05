#lang racket
(require web-server/templates
         "l10n.rkt")

(define (generate-mirror)
  (define is-mirror? #t)
  (define source-code
    (let ([lang "zhs"])
      (include-template "fragments/main/description.html")))
  ;; replace download URLs
  (regexp-replace* #rx"dl.geph.io"
                   source-code
                   "f001.backblazeb2.com/file/geph-dl"))

(with-output-to-file #:exists 'replace "ZHS-STATIC.html"
  (lambda() (display (generate-mirror))))

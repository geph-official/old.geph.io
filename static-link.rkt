#lang racket
(require racket/system)
(provide static-link)

;; generates a static link to a file, or a data URI if it's a mirror
(define (static-link path is-mirror?)
  (cond
    [is-mirror? (string-replace
                 (string-replace
                  (string-trim
                   (with-output-to-string
                       (thunk
                        (with-input-from-string ""
                          (thunk
                           (system (format "./cssify.sh ./static/~v"
                                           path)))))))
                  "text/plain"
                  "text/css")
                 "image/svg"
                 "image/svg+xml")]
    [else path]))
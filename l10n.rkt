#lang racket
(require web-server/servlet)
(provide current-website-language
         request-language
         l10n
         lang->standard-lang)

(define current-website-language (make-parameter "en"))

(define (request-language req)
  (define best-lang
    (with-handlers ([exn:fail? (λ e #'(displayln e) #f)])
      (string-trim
       (first (string-split
               (extract-binding/single 'accept-language
                                       (request-headers req)) ",")))))
  (match best-lang
    ["zh-CN" "zhs"]
    [(regexp #rx"^zh") "zht"]
    [_ "en"]))

(define (lang->standard-lang lang)
  (match lang
    ["zhs" "zh_CN"]
    ["zht" "zh_TW"]
    ["en" "en"]))

(define (read-lang-csv csv)
  (with-input-from-file csv
    (lambda()
      (define langs (string-split (read-line) ","))
      (for/hash ([line (in-lines)])
        (define exploded (string-split line ","))
        (define key (string->symbol (car exploded)))
        (values key
                (for/hash ([lang (cdr langs)]
                           [trans (cdr exploded)])
                  (values lang trans)))))))

(define lang-mapping (read-lang-csv "translations.csv"))

(define (l10n key)
  (hash-ref (hash-ref lang-mapping key) (current-website-language)))
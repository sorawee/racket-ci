#lang racket

(define files '("scanbuild.rkt"))

(for ([file files])
  (define out (path-replace-extension file ".yml"))
  (printf "Generating ~a\n" out)
  (with-output-to-file out #:exists 'replace
    (λ ()
      (dynamic-require file #f))))

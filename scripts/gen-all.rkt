#lang racket

(define files '("scanbuild.rkt"
                "chez-build.rkt"))

(for ([file files])
  (define out (build-path "out" (path-replace-extension file ".yml")))
  (printf "Processing ~a..." out)
  (flush-output)
  (define s (with-output-to-string (λ () (dynamic-require file #f))))
  (define s* (and (file-exists? out) (file->string out)))
  (cond
    [(equal? s s*)
     (printf " Skipped.\n")]
    [else
     (with-output-to-file out #:exists 'replace
       (λ () (display s)))
     (printf " Done.\n")]))

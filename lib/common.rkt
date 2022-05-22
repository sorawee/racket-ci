#lang at-exp racket

(provide RUNS-ON
         IF-RACKET-REPO)

(require "lib.rkt")

(def RUNS-ON
  [runs-on: "ubuntu-20.04"])

(def IF-RACKET-REPO
  [if: "github.repository == 'racket/racket'"])

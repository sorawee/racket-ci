#lang at-exp racket

(provide CLAUSE:RUNS-ON:DEFAULT
         CLAUSE:IF-RACKET-REPO
         STEP:CLEAN-REPO)

(require "lib.rkt")

(def CLAUSE:RUNS-ON:DEFAULT
  [runs-on: "ubuntu-20.04"])

(def CLAUSE:IF-RACKET-REPO
  [if: "github.repository == 'racket/racket'"])

(def STEP:CLEAN-REPO
  ($map [name: "Clean repo"]
        ($run "git clean -xdf")))

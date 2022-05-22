#lang at-exp racket

(require "lib.rkt"
         "common.rkt")

(def RELEVANT-PATHS
  ($map [paths: ($list "racket/src/ChezScheme/**"
                       ".github/scripts/**"
                       ".github/workflows/chez-build.yml"
                       "Makefile")]))

(def BUILD-AND-TEST
  {~@ ($map [name: "Build Chez with PB boot files"]
            [working-directory: "racket/src/ChezScheme"]
            ($run "./configure --pb"
                  "make -j$(($(nproc) + 1)) -l$(nproc) ${MACH}.bootquick"))

      ($map [name: "Build Chez with native boot files"]
            [working-directory: "racket/src/ChezScheme"]
            ($run "./configure -m=${MACH}"
                  "make -j$(($(nproc) + 1)) -l$(nproc)"))

      ($map [name: "Test Chez"]
            [working-directory: "racket/src/ChezScheme"]
            ($run "../../../.github/scripts/test.sh"))})

(process
 ($map
  [name: "Solo Chez Build"]
  [on: ($map [push: RELEVANT-PATHS]
             [pull_request: RELEVANT-PATHS])]
  [jobs:
   ($map
    [build-linux:
     ($map
      RUNS-ON
      [strategy:
       ($map [fail-fast: #f]
             [matrix: ($map [mach: ($list "i3le" "ti3le" "a6le" "ta6le")])])]
      [env: ($map [MACH: "${{ matrix.mach }}"])]
      [steps:
       ($list
        ($map [name: "Download base dependencies"]
              ($run "sudo apt-get update"
                    "sudo apt-get install -y make git gcc"))

        ($actions/checkout)

        ($map [name: "Download pb boot files"]
              ($run "make fetch-pb"))

        ($map
         [name: "Install libs for 32-bit"]
         [if: "matrix.mach == 'i3le' || matrix.mach == 'ti3le'"]
         ($run "sudo dpkg --add-architecture i386"
               "sudo apt-get update"
               "sudo apt-get install -y gcc-multilib lib32ncurses-dev libssl-dev:i386"))

        ($map
         [name: "Install libs for 64-bit"]
         [if: "matrix.mach == 'i3le' || matrix.mach == 'ti3le'"]
         ($run "sudo apt-get update"
               "sudo apt-get install -y libncurses5-dev libssl-dev libx11-dev"))

        BUILD-AND-TEST)])]

    [build-arm64:
     ($map IF-RACKET-REPO
           [runs-on: ($list "self-hosted" "ARM64" "Linux")]
           [container:
            ($map [image: "racket/racket-ci:latest"]
                  [options: "--init"])]
           [env: ($map [MACH: "tarm64le"])]
           [steps:
            ($list ($actions/checkout)

                   ($map [name: "Download pb boot files"]
                         ($run "make fetch-pb"))

                   BUILD-AND-TEST)])])]))

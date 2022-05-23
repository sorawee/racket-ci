#lang at-exp racket

(require "lib/lib.rkt"
         "lib/common.rkt")

(def INSTALLS
  (s "libffi-dev"
     "unzip"
     "python"
     "libxml2-dev"
     "libfindbin-libs-perl"
     "make"
     "gcc"
     "g++"
     "git"
     "tree"
     "jq"
     "moreutils"))

(def BC-CONFIGURE-OPTIONS
  {~@ "--disable-strip"
      "--enable-werror"
      "--enable-cify"
      "--enable-jit"
      "--enable-foreign"
      "--enable-places"
      "--enable-futures"
      "--enable-float"})

(def STEP:SPEED-BUILD-CGC
  ($map [name: "Speed build and install racketcgc"]
        [working-directory: "./racket/src"]
        ($run "./configure --enable-cgcdefault --prefix=/usr"
              "make -j$(($((nproc)) + 1))"
              "make -j$(($((nproc)) + 1)) install")))

(def ($configure-invocation xs ...)
  (s "./configure"
     "CFLAGS='-O0 -g'"
     "CPPFLAGS='-DMZ_PRECISE_RETURN_SPEC'"
     "--disable-docs"
     "--enable-pthread"
     xs ...))

(def ($make-scanbuild {~args #:variant variant #:instructions xs})
  [($make-key @t{scanbuild-racket@|variant|})
   ($map
    CLAUSE:RUNS-ON:DEFAULT
    [container: "pmatos/scan-build:12.0.1"]
    [steps:
     ($list ($map [name: "Install dependencies"]
                  ($run "apt-get update"
                        @t{apt-get install -y @|INSTALLS|}))

            ($actions/checkout)

            {~@ . xs}

            ($map [name: "Scan Build"]
                  [working-directory: "./racket/src"]
                  ($run (s "scan-build"
                           "-sarif"
                           @t{-o ../../racket@|variant|-report}
                           "-analyzer-config 'crosscheck-with-z3=true'"
                           "make -j$(($(nproc) + 1))"
                           variant)))

            ($map [name: "Move SARIF results"]
                  ($run "mkdir sarif-files"

                        (s "find"
                           @t{racket@|variant|-report}
                           "-type f"
                           "-name '*.sarif'"
                           @t{-exec cp \{\}}
                           "sarif-files/"
                           @t{\;})))

            ($map [name: "Adjust tool name"]
                  [working-directory: "sarif-files"]
                  ($run @t{../.github/scripts/adjust-sarif-tool.sh @variant}))

            ($map [name: "Create file list"]
                  [working-directory: "sarif-files"]
                  ($run "find . -type f -name '*.sarif' > list.txt"
                        "split -d -l15 list.txt list."))

            ($actions/upload-artifact
             #:name @t{scanbuild-cgc-${{ github.sha }}}
             #:path "sarif-files"))])])

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(process
 ($map
  [name: "LLVM Static Analysis"]
  [on: "push"]
  [permissions: ($map [security-events: "write"])]
  [jobs:
   ($map
    ($make-scanbuild
     #:variant "cgc"
     #:instructions
     [($map [name: "Configure Racket CGC"]
            [working-directory: "./racket/src"]
            ($run ($configure-invocation
                   "--enable-cgcdefault"
                   "--prefix=${{ runner.temp }}/racketcgc"
                   BC-CONFIGURE-OPTIONS)))])

    ($make-scanbuild
     #:variant "3m"
     #:instructions
     [STEP:SPEED-BUILD-CGC
      STEP:CLEAN-REPO
      ($map [name: "Configure Racket 3m"]
            [working-directory: "./racket/src"]
            ($run ($configure-invocation
                   "--enable-bcdefault"
                   "--enable-racket=/usr/bin/racket"
                   BC-CONFIGURE-OPTIONS)))])

    ($make-scanbuild
     #:variant "cs"
     #:instructions
     [STEP:SPEED-BUILD-CGC
      STEP:CLEAN-REPO
      ($map [name: "Configure Racket 3m"]
            [working-directory: "./racket/src"]
            ($run ($configure-invocation
                   "--enable-csdefault"
                   "--enable-csonly"
                   "--enable-racket=/usr/bin/racket"
                   "--enable-compress")))])

    [upload:
     ($map
      CLAUSE:RUNS-ON:DEFAULT
      [needs:
       ($list "scanbuild-racketcgc" "scanbuild-racket3m" "scanbuild-racketcs")]
      [strategy:
       ($map [matrix:
              ($map
               [variants: ($list "cgc" "3m" "cs")]
               ;; process up to 15 * 5 = 75 files
               [chunks: ($list "00" "01" "02" "03" "04")])])]
      [steps:
       ($list
        ($actions/checkout)

        ($actions/download-artifact
         #:name "scanbuild-${{ matrix.variants }}-${{ github.sha }}")

        ($map [name: "Test for presence of the chunk"]
              [id: "chunk_presence"]
              ($run @t{if [[ -e "list.${{ matrix.chunks }}"]]}
                    "then"
                    ($set-output "presence" "1")
                    "else"
                    ($set-output "presence" "0")
                    "fi"))

        {~@
         .
         ($when @t{@($get-output "chunk_presence" "presence") == '1'}

                ($map [name: "Partition the chunk"]
                      ($run "mkdir workspace"

                            "for file in $(cat list.${{ matrix.chunks }})"
                            "do"
                            @t{mv "$file" workspace}
                            "done"))

                ($github/codeql-action/upload-sarif
                 #:name "Upload SARIF"
                 #:sarif-file "workspace"
                 #:category
                 "scanbuild-${{ matrix.variants }}-${{ matrix.chunks }}-${{ github.sha }}"))})])])]))

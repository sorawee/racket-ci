#lang at-exp racket

(require "lib.rkt")

(def RUNS-ON "ubuntu-20.04")

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

(def CLEAN-REPO
  ($map
   [name: "Clean repo"]
   ($run "git clean -xdf")))


(def SPEED-BUILD-CGC
  ($map
   [name: "Speed build and install racketcgc"]
   [working-directory: "./racket/src"]
   ($run "./configure --enable-cgcdefault --prefix=/usr"
         "export cpus=$(grep -c ^processor /proc/cpuinfo)"
         "make -j$((cpus+1))"
         "make -j$((cpus+1)) install")))

(def ($configure-invocation . xs)
  (s "./configure"
     "CFLAGS='-O0 -g'"
     "CPPFLAGS='-DMZ_PRECISE_RETURN_SPEC'"
     "--disable-docs"
     "--enable-pthread"
     .
     xs))

(def ($make-scanbuild #:variant variant #:instructions xs)
  [($make-key @t{scanbuild-racket@|variant|})
   ($map
    [runs-on: RUNS-ON]
    [container: "pmatos/scan-build:12.0.1"]
    [steps:
     ($list
      ($map
       [name: "Install dependencies"]
       ($run "apt-get update"
             @t{apt-get install -y @|INSTALLS|}))

      ($actions/checkout)

      {~@ . xs}

      ($map
       [name: "Scan Build"]
       [working-directory: "./racket/src"]
       ($run (s "scan-build"
                "-sarif"
                @t{-o ../../racket@|variant|-report}
                "-analyzer-config 'crosscheck-with-z3=true'"
                "make -j$(($(nproc) + 1))"
                variant)))

      ($map
       [name: "Move SARIF results"]
       ($run "mkdir sarif-files"

             (s "find"
                @t{racket@|variant|-report}
                "-type f"
                "-name '*.sarif'"
                @t{-exec cp \{\}}
                "sarif-files/"
                @t{\;})))

      ($map
       [name: "Adjust tool name"]
       [working-directory: "sarif-files"]
       ($run @t{../.github/scripts/adjust-sarif-tool.sh @variant}))

      ($map
       [name: "Create file list"]
       [working-directory: "sarif-files"]

       ($run "find . -type f -name '*.sarif' > list.txt"
             "split -d -l15 list.txt list."))

      ($actions/upload-artifact
       #:name @t{scanbuild-cgc-${{ github.sha }}}
       #:path "sarif-files"))])])


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
     [($map
       [name: "Configure Racket CGC"]
       [working-directory: "./racket/src"]
       ($run ($configure-invocation
              "--enable-cgcdefault"
              "--prefix=${{ runner.temp }}/racketcgc"

              "--disable-strip"
              "--enable-werror"
              "--enable-cify"
              "--enable-jit"
              "--enable-foreign"
              "--enable-places"
              "--enable-futures"
              "--enable-float")))])

    ($make-scanbuild
     #:variant "3m"
     #:instructions
     [SPEED-BUILD-CGC
      CLEAN-REPO

      ($map
       [name: "Configure Racket 3m"]
       [working-directory: "./racket/src"]
       ($run ($configure-invocation
              "--enable-bcdefault"
              "--enable-racket=/usr/bin/racket"

              "--disable-strip"
              "--enable-werror"
              "--enable-cify"
              "--enable-jit"
              "--enable-foreign"
              "--enable-places"
              "--enable-futures"
              "--enable-float")))])

    ($make-scanbuild
     #:variant "cs"
     #:instructions
     [SPEED-BUILD-CGC
      CLEAN-REPO
      ($map
       [name: "Configure Racket 3m"]
       [working-directory: "./racket/src"]
       ($run ($configure-invocation
              "--enable-csdefault"
              "--enable-csonly"
              "--enable-racket=/usr/bin/racket"
              "--enable-compress")))])

    [upload:
     ($map
      [runs-on: RUNS-ON]
      [needs:
       ($list "scanbuild-racketcgc" "scanbuild-racket3m" "scanbuild-racketcs")]
      [strategy:
       ($map
        [matrix:
         ($map
          [variants: ($list "cgc" "3m" "cs")]
          [chunks: ($list "00" "01" "02" "03" "04")])])]
      [steps:
       ($list
        ($actions/checkout)

        ($actions/download-artifact
         #:name "scanbuild-${{ matrix.variants }}-${{ github.sha }}")

        ($map
         [name: "Test for presence of the chunk"]
         [id: "chunk_presence"]
         ($run @t{if [[ -e "list.${{ matrix.chunks }}" ]]}
               "then"
               ($set-output "presence" "1")
               "else"
               ($set-output "presence" "0")
               "fi"))

        {~@
         .
         ($when "steps.chunk_presence.outputs.presence == '1'"

                ($map
                 [name: "Partition the chunk"]
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

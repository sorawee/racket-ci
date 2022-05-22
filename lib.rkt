#lang at-exp racket

(provide def
         s
         t
         adjust-loc

         $list
         $map

         $make-key

         process

         $when
         $set-output
         $run
         $actions/checkout
         $actions/upload-artifact
         $actions/download-artifact
         $github/codeql-action/upload-sarif)

(require racket/syntax
         racket/splicing
         racket/date
         syntax/parse/define
         syntax/parse/experimental/template
         syntax/parse
         (only-in syntax/parse/private/sc syntax-parser/template))


(define-syntax-parser def
  [(_ (name . pattern) . body)
   #'(define-template-metafunction name
       (syntax-parser/template
        #,((make-syntax-introducer) stx)
        [((~var macro id) . pattern) . body]))]
  [(_ name:id body)
   #'(define-template-metafunction name
       (syntax-parser
         [(_ . xs) #'(body . xs)]))])

(define-syntax ~args
  (pattern-expander
   (syntax-parser
     [(_ {~seq k:keyword a:id} ...)
      #:with ooo (quote-syntax ...)
      #'{~seq {~alt {~once {~seq k a}} ...} ooo}]
     [(_ {~seq k:keyword a:id} ... {~datum ::} {~seq k2:keyword a2:id} ...)
      #:with ooo (quote-syntax ...)
      #'{~seq {~alt {~once {~seq k a}} ...
                    {~optional {~seq k2 a2}} ...}
              ooo}])))

(define-syntax-parse-rule (adjust-loc s:expr)
  (let ([x s])
    (datum->syntax #f x this-syntax)))

(def (s t:string ...)
  #:with result (adjust-loc (string-join (map syntax-e (attribute t)) " "))
  result)

(def (t t:string ...)
  #:with result (adjust-loc (string-join (map syntax-e (attribute t)) ""))
  result)

(def ($make-key t:string)
  #:with result (format-id #f "~a:" (syntax-e #'t) #:source #'t)
  result)


(define-syntax-parse-rule (define-placeholder-syntax x:id ...)
  #:with core-forms (syntax-local-introduce #'core-forms)
  (begin
    (define-syntax (x stx)
      (raise-syntax-error #f "a use out of context" stx))
    ...
    (define-literal-set core-forms
      (x ...))))

(define-placeholder-syntax $block* $list* $map*)

(def ($list . xs)
  ($list* . xs))

(def ($map [k:key-cls v] ...)
  ($map* [k v] ...))

(def ($block s:string ...)
  ($block* s ...))

(define-syntax-class key-cls
  #:description "key"
  (pattern x:id
           #:when (string-suffix? (symbol->string (syntax-e #'x)) ":")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (print-spaces x)
  (for ([i x])
    (printf " ")))

(define (pretty d indent block?)
  (syntax-parse d
    #:literal-sets (core-forms)
    [($map* [k v] ...)
     (define len (length (attribute k)))
     (for ([k (attribute k)]
           [v (attribute v)]
           [i (in-naturals)])
       (printf "~a" (syntax-e k))
       (newline)
       (print-spaces (+ indent 2))
       (pretty v (+ indent 2) #f)
       (when (< i (sub1 len))
         (newline)
         (print-spaces indent)))]
    [($block* x ...)
     (printf "|-")
     (newline)
     (print-spaces (+ indent 2))
     (define len (length (attribute x)))
     (for ([x (attribute x)]
           [i (in-naturals)])
       (pretty x (+ indent 2) #t)
       (when (< i (sub1 len))
         (newline)
         (print-spaces (+ indent 2))))]
    [($list* x ...)
     (define len (length (attribute x)))
     (for ([x (attribute x)]
           [i (in-naturals)])
       (printf "- ")
       (pretty x (+ indent 2) #f)
       (when (< i (sub1 len))
         (newline)
         (print-spaces indent)))]
    [(_ ...)
     (raise-syntax-error #f "bad syntax" this-syntax)]
    [x:number
     (display (syntax-e #'x))]
    [x:string
     #:when block?
     (display (syntax-e #'x))]
    [x:string (printf "~s" (syntax-e #'x))]
    [x:boolean (display (if (syntax-e #'x) "true" "false"))]))

(define (pp d)
  (pretty d 0 #f))

(define-syntax-parse-rule (process x)
  #:with path
  (let-values ([(base name dir?) (split-path (syntax-source this-syntax))])
    (path->string name))

  (begin (displayln "# THIS FILE IS AUTO-GENERATED. PLEASE DO NOT EDIT IT.")
         (printf "# GENERATED FROM: ~a\n" 'path)
         (printf "# GENERATED TIME: ~a\n" (date->string (current-date) #t))
         (pp #'x)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(def ($set-output key:string val:string)
  #:with result (adjust-loc (format "echo '::set-output name=~a::~a'"
                                    (syntax-e #'key)
                                    (syntax-e #'val)))
  result)

(def ($run t:string ...)
  [run: ($block t ...)])

(def ($actions/checkout {~args :: #:fetch-depth fetch-depth:number})
  ($map
   [uses: "actions/checkout@v3"]
   [with: ($map [fetch-depth: {~? fetch-depth 100}])]))

;; name :: string?
;; path :: string?
(def ($actions/upload-artifact {~args #:name name:string #:path path:string})
  ($map
   [uses: "actions/upload-artifact@v3"]
   [name: name]
   [path: path]))

;; name :: string?
(def ($actions/download-artifact {~args #:name name:string})
  ($map
   [uses: "actions/download-artifact@v3"]
   [with: ($map
           [name: name])]))

(def ($github/codeql-action/upload-sarif {~args #:name name:string
                                                #:sarif-file sarif-file:string
                                                #:category category:string ::
                                                #:if ife:string})
  ($map
   [uses: "github/codeql-action/upload-sarif@v2"]
   [name: name]
   {~? [if: ife]}
   [sarif-file: sarif-file]
   [category: category]))

(splicing-local
    [(define-syntax-class (when-trans c)
       #:literal-sets (core-forms)
       #:attributes (expanded)
       (pattern ($map* [k v] ... [{~datum if:} v*] [k2 v2] ...)
                #:with v** (format "(~a) && (~a)" (syntax-e #'c) (syntax-e #'v*))
                #:with expanded #'($map* [k v] ... [if: v**] [k2 v2] ...))
       (pattern ($map* [k v] ...)
                #:with expanded #`($map* [k v] ... [if: #,c])))]
  (def ($when c body ...)
    #:with ({~var body* (when-trans #'c)} ...) #'(body ...)
    (body*.expanded ...)))

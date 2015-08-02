#lang sugar/debug racket/base
(require racket/file racket/path racket/match racket/list)
(require sugar/coerce sugar/test sugar/define sugar/container sugar/file sugar/len)
(require "file.rkt" "cache.rkt" "world.rkt" "debug.rkt" "pagetree.rkt" "project.rkt" "template.rkt" "rerequire.rkt")

;; used to track renders according to modification dates of component files
(define mod-date-hash (make-hash))

;; when you want to generate everything fresh, 
;; but without having to #:force everything.
;; render functions will always go when no mod-date is found.
(define (reset-mod-date-hash)
  (set! mod-date-hash (make-hash)))

(module-test-internal
 (check-pred hash? mod-date-hash))

;; using internal contracts to provide some extra safety (negligible performance hit)

(define/contract (valid-path-arg? x)
  (any/c . -> . boolean?)
  (or (equal? #f x) (complete-path? x)))

(define/contract (valid-path-args? x)
  (any/c . -> . boolean?)
  (and (list? x) (andmap valid-path-arg? x)))



(module-test-internal
 (require racket/runtime-path)
 (define-runtime-path sample-dir "test/data/samples")
 (define samples (parameterize ([current-directory sample-dir])
                   (map path->complete-path (directory-list "."))))
 (define-values (sample-01 sample-02 sample-03) (apply values samples)))


(define/contract (path->mod-date-value path)
  ((or/c #f complete-path?) . -> . (or/c #f integer?))
  (and path (file-exists? path) (file-or-directory-modify-seconds path)))

(module-test-internal
 (check-false (path->mod-date-value (path->complete-path "garbage-path.zzz")))
 (check-equal? (path->mod-date-value sample-01) (file-or-directory-modify-seconds sample-01)))


;; each key for mod-date-hash is a list of file / mod-date pairs (using pollen/cache keymaking function)
;; when a file is rendered, a new key is stored in the hash (with trivial value #t)
;; after that, the hash-key-comparision routine intrinsic to hash lookup
;; can be used to test whether a render is obsolete.
;; create a new key with current files. If the key is in the hash, the render has happened.
;; if not, a new render is needed.
(define (update-mod-date-hash source-path template-path)
  (hash-set! mod-date-hash (paths->key source-path template-path) #t))

(define (mod-date-missing-or-changed? source-path template-path)
  (not (hash-has-key? mod-date-hash (paths->key source-path template-path))))


(define (list-of-pathish? x) (and (list? x) (andmap pathish? x)))

(define/contract+provide (render-batch . xs)
  (() #:rest list-of-pathish? . ->* . void?)
  ;; Why not just (map render ...)?
  ;; Because certain files will pass through multiple times (e.g., templates)
  ;; And with render, they would be rendered repeatedly.
  ;; Using reset-modification-dates is sort of like session control.
  (reset-mod-date-hash) 
  (for-each (λ(x) ((if (pagetree-source? x)
                       render-pagetree
                       render-from-source-or-output-path) x)) xs))


(define/contract+provide (render-pagetree pagetree-or-path)
  ((or/c pagetree? pathish?) . -> . void?)
  (define pagetree (if (pagetree? pagetree-or-path)
                       pagetree-or-path
                       (cached-require pagetree-or-path (world:current-main-export))))
  (parameterize ([current-directory (world:current-project-root)])
    (for-each render-from-source-or-output-path (map ->complete-path (pagetree->list pagetree)))))


(define/contract+provide (render-from-source-or-output-path so-pathish #:force [force #f])
  ((pathish?) (#:force boolean?) . ->* . void?)
  (let ([so-path (->complete-path so-pathish)])  ; so-path = source or output path (could be either) 
    (cond
      [(ormap (λ(test) (test so-path)) (list has/is-null-source? has/is-preproc-source? has/is-markup-source? has/is-scribble-source? has/is-markdown-source? has/is-template-source?)) 
       (let-values ([(source-path output-path) (->source+output-paths so-path)])
         (render-to-file-if-needed source-path output-path #:force force))]
      [(pagetree-source? so-path) (render-pagetree so-path)]))
  (void))


(define/contract (->source+output-paths source-or-output-path)
  (complete-path? . -> . (values complete-path? complete-path?))
  ;; file-proc returns two values, but ormap only wants one
  (define file-proc (ormap (λ(test file-proc) (and (test source-or-output-path) file-proc))
                           (list has/is-null-source? has/is-preproc-source? has/is-markup-source? has/is-scribble-source? has/is-markdown-source? has/is-template-source?)
                           (list ->null-source+output-paths ->preproc-source+output-paths ->markup-source+output-paths ->scribble-source+output-paths ->markdown-source+output-paths ->template-source+output-paths)))
  (file-proc source-or-output-path))


(define/contract (render-needed? source-path template-path output-path)
  (complete-path? (or/c #f complete-path?) complete-path? . -> . (or/c #f symbol?))
  ;; return an explanatory symbol rather than #t (handy for logging / debugging)
  (cond
      [(not (file-exists? output-path)) 'file-missing]
      [(mod-date-missing-or-changed? source-path template-path) 'mod-key-missing-or-changed]
      [(file-needed-rerequire? source-path) 'file-needed-rerequire]
      [else #f]))


(define/contract+provide (render-to-file-if-needed source-path [template-path #f] [maybe-output-path #f] #:force [force #f])
  ((complete-path?) ((or/c #f complete-path?) (or/c #f complete-path?) #:force boolean?) . ->* . void?)  
  (define output-path (or maybe-output-path (->output-path source-path)))
  (define template-path (get-template-for source-path))
  (when (or force (render-needed? source-path template-path output-path))
    (render-to-file source-path template-path output-path)))


(define/contract+provide (render-to-file source-path [template-path #f] [maybe-output-path #f])
  ((complete-path?) ((or/c #f complete-path?) (or/c #f complete-path?)) . ->* . void?)
  (define output-path (or maybe-output-path (->output-path source-path)))
  (define render-result (render source-path template-path)) ; will either be string or bytes
  (display-to-file render-result output-path #:exists 'replace
                   #:mode (if (string? render-result) 'text 'binary)))


(define/contract+provide (render source-path [template-path #f])
  ((complete-path?) ((or/c #f complete-path?)) . ->* . (or/c string? bytes?))
  (define render-proc 
    (cond
      [(ormap (λ(test render-proc) (and (test source-path) render-proc))
              (list has/is-null-source? has/is-preproc-source? has/is-markup-source? has/is-scribble-source? has/is-markdown-source? has/is-template-source?)
              (list render-null-source render-preproc-source render-markup-or-markdown-source render-scribble-source render-markup-or-markdown-source render-preproc-source))] 
      [else (error (format "render: no rendering function found for ~a" source-path))]))
  
  (message (format "render: ~a" (file-name-from-path source-path)))
  (define render-result (apply render-proc (cons source-path (if template-path (list template-path) null))))
  ;; wait till last possible moment to store mod dates, because render-proc may also trigger its own subrenders
  ;; e.g., of a template.
  (update-mod-date-hash source-path template-path) 
  render-result)


(define/contract (render-null-source source-path)
  (complete-path? . -> . bytes?)
  ;; All this does is copy the source. Hence, "null".
  ;; todo: add test to avoid copying if unnecessary (good idea in case the file is large)
  (file->bytes source-path))


(define/contract (render-scribble-source source-path)
  (complete-path? . -> . string?)
  (match-define-values (source-dir _ _) (split-path source-path))
  (file-needed-rerequire? source-path) ; called for its reqrequire side effect only, so dynamic-require below isn't cached
  (time (parameterize ([current-directory (->complete-path source-dir)])
          ;; BTW this next action has side effects: scribble will copy in its core files if they don't exist.
          ((dynamic-require 'scribble/render 'render) (list (dynamic-require source-path (world:current-main-export))) (list source-path))))
  (define result (file->string (->output-path source-path)))
  (delete-file (->output-path source-path)) ; because render promises the data, not the side effect
  result)


(define/contract (render-preproc-source source-path)
  (complete-path? . -> . (or/c string? bytes?))
  (match-define-values (source-dir _ _) (split-path source-path))
  (time (parameterize ([current-directory (->complete-path source-dir)])
          (render-through-eval `(begin (require pollen/cache)(cached-require ,source-path ',(world:current-main-export)))))))


(define/contract (render-markup-or-markdown-source source-path [maybe-template-path #f]) 
  ((complete-path?) ((or/c #f complete-path?)) . ->* . (or/c string? bytes?))
  (match-define-values (source-dir _ _) (split-path source-path))
  (define template-path (or maybe-template-path (get-template-for source-path)))
  (render-from-source-or-output-path template-path) ; because template might have its own preprocessor source
  (define expr-to-eval 
    `(begin 
       (require (for-syntax racket/base))
       (require pollen/include-template pollen/cache pollen/debug)
       ,(require-directory-require-files source-path) 
       (let ([,(world:current-main-export) (cached-require ,(path->string source-path) ',(world:current-main-export))]
             [,(world:current-meta-export) (cached-require ,(path->string source-path) ',(world:current-meta-export))])
         (local-require pollen/pagetree pollen/template pollen/top)
         (define here (metas->here ,(world:current-meta-export)))
         (cond 
           [(bytes? ,(world:current-main-export)) ,(world:current-main-export)] ; if main export is binary, just pass it through
           [else
            (include-template #:command-char ,(world:current-command-char) (file ,(->string (find-relative-path source-dir template-path))))]))))
  (time (parameterize ([current-directory (->complete-path source-dir)]) ; because include-template wants to work relative to source location
          (render-through-eval expr-to-eval))))


(define/contract (templated-source? path)
  (complete-path? . -> . boolean?)
  (or (markup-source? path) (markdown-source? path)))

(define not-false? (λ(x) x))
(define/contract+provide (get-template-for source-path)
  (complete-path? . -> . (or/c #f complete-path?))
  (match-define-values (source-dir _ _) (split-path source-path))
  (and (templated-source? source-path) ; doesn't make sense if it's not a templated source format
       (let ([output-path (->output-path source-path)])
         (or ; Build the possible paths and use the first one that either exists, or has existing source (template, preproc, or null)
          (ormap (λ(p) (if (ormap file-exists? (list p (->template-source-path p) (->preproc-source-path p) (->null-source-path p))) p #f)) 
                 (filter not-false? ; if any of the possibilities below are invalid, they return #f 
                         (list
                          ;; Q: why does next line have to be dynamic-require rather than cached-require?
                          (let ([source-metas (cached-require (->complete-path source-path) (world:current-meta-export) 'get-template)])
                              (and ((->symbol (world:current-template-meta-key)) . in? . source-metas)
                                   (build-path source-dir (select-from-metas (->string (world:current-template-meta-key)) source-metas)))) ; path based on metas
                          (and (filename-extension output-path) (build-path (world:current-project-root) 
                                                                            (add-ext (world:current-default-template-prefix) (get-ext output-path))))))) ; path to default template
          (and (filename-extension output-path) (build-path (world:current-server-extras-path) (add-ext (world:current-fallback-template-prefix) (get-ext output-path)))))))) ; fallback template


(define/contract (file-needed-rerequire? source-path)
  (complete-path? . -> . boolean?)
  (and (not (null-source? source-path)) ; null sources can't be rerequired
       (let-values ([(source-dir source-name _) (split-path source-path)])
         (define reloaded-paths (dynamic-rerequire source-path))
         (not (empty? reloaded-paths)))))


;; set up namespace for module caching
(module caching-module racket/base
  (define-namespace-anchor caching-module-nsa)
  (provide caching-module-nsa))
(require 'caching-module)

;; (car (current-eval-namespace-cache)) = namespace containing cached modules
;; (cdr (current-eval-namespace-cache)) = list of cached modules
(define current-eval-namespace-cache (make-parameter (cons (namespace-anchor->namespace caching-module-nsa) '())))

(define/contract+provide (add-module-to-current-eval-cache module-name)
  (symbol? . -> . void?)
  (define cache-ns (car (current-eval-namespace-cache)))
  (define cached-modules (cdr (current-eval-namespace-cache)))
  (when (not (member module-name cached-modules))
    (eval `(require ,module-name) cache-ns)
    (current-eval-namespace-cache (cons cache-ns (cons module-name cached-modules)))))

(define initial-modules-to-cache '(xml
                                   racket/bool
                                   racket/class
                                   racket/contract 
                                   racket/draw
                                   racket/file
                                   racket/format
                                   racket/function
                                   racket/port 
                                   racket/list
                                   racket/match
                                   racket/string
                                   racket/syntax
                                   pollen/cache
                                   pollen/debug
                                   pollen/decode
                                   pollen/file
                                   pollen/include-template
                                   pollen/main
                                   pollen/pagetree
                                   pollen/reader-base
                                   pollen/rerequire
                                   pollen/tag
                                   pollen/template
                                   pollen/world
                                   pollen/project
                                   sugar
                                   txexpr))


(for-each add-module-to-current-eval-cache initial-modules-to-cache)


(define/contract (render-through-eval expr-to-eval)
  (list? . -> . (or/c string? bytes?))
  (define cache-ns (car (current-eval-namespace-cache)))
  (define cached-modules (cdr (current-eval-namespace-cache)))
  (parameterize ([current-namespace (make-base-namespace)]
                 [current-pagetree (make-project-pagetree (world:current-project-root))])
    (for-each (λ(mod-name) (namespace-attach-module cache-ns mod-name)) cached-modules)   
    (eval expr-to-eval (current-namespace))))
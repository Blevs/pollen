#lang racket/base
(require racket/file racket/rerequire racket/path racket/match)
(require sugar/coerce sugar/test sugar/define sugar/container sugar/file sugar/len)
(require "file.rkt" "cache.rkt" "world.rkt" "debug.rkt" "pagetree.rkt" "project.rkt" "template.rkt")


;; when you want to generate everything fresh, 
;; but without having to #:force everything.
;; render functions will always go when no mod-date is found.
(define (reset-modification-dates)
  (set! modification-date-hash (make-hash)))

;; mod-dates is a hash that takes lists of paths as keys,
;; and lists of modification times as values.
(define modification-date-hash #f)
(reset-modification-dates)
(module-test-internal
 (check-pred hash? modification-date-hash))

;; using internal contracts to provide some extra safety (negligible performance hit)

(define/contract (valid-path-arg? x)
  (any/c . -> . boolean?)
  (or (equal? #f x) (complete-path? x)))

(define/contract (valid-path-args? x)
  (any/c . -> . boolean?)
  (and (list? x) (andmap valid-path-arg? x)))


(define/contract (make-mod-dates-key paths)
  (valid-path-args? . -> . valid-path-args?)
  paths) ; for now, this does nothing; maybe later, it will do more

(module-test-internal
 (require racket/runtime-path)
 (define-runtime-path sample-dir "test/data/samples")
 (define samples (parameterize ([current-directory sample-dir])
                   (map path->complete-path (directory-list "."))))
 (define-values (sample-01 sample-02 sample-03) (apply values samples))
 (check-equal? (make-mod-dates-key samples) samples))


(define/contract (path->mod-date-value path)
  ((or/c #f complete-path?) . -> . (or/c #f integer?))
  (and path (file-exists? path) (file-or-directory-modify-seconds path)))

(module-test-internal
 (check-false (path->mod-date-value (path->complete-path "garbage-path.zzz")))
 (check-equal? (path->mod-date-value sample-01) (file-or-directory-modify-seconds sample-01)))


(define/contract (store-render-in-modification-dates . rest-paths)
  (() #:rest valid-path-args? . ->* . void?)
  (define key (make-mod-dates-key rest-paths))
  (hash-set! modification-date-hash key (map path->mod-date-value key)))

(module-test-internal
 (check-equal? (store-render-in-modification-dates sample-01 sample-02 sample-03) (void))
 (check-true (hash-has-key? modification-date-hash (list sample-01 sample-02 sample-03))))


(define/contract (modification-date-expired? . rest-paths)
  (() #:rest valid-path-args? . ->* . boolean?)
  (define key (make-mod-dates-key rest-paths))
  (or (not (key . in? . modification-date-hash))  ; no stored mod date
      (not (equal? (map path->mod-date-value key) (get modification-date-hash key))))) ; data has changed

(module-test-internal
 (check-true (modification-date-expired? sample-01)) ; because key hasn't been stored
 (check-false (apply modification-date-expired? samples))) ; because files weren't changed


(define (list-of-pathish? x) (and (list? x) (andmap pathish? x)))

(define/contract+provide (render-batch . xs)
  (() #:rest list-of-pathish? . ->* . void?)
  ;; Why not just (map render ...)?
  ;; Because certain files will pass through multiple times (e.g., templates)
  ;; And with render, they would be rendered repeatedly.
  ;; Using reset-modification-dates is sort of like session control.
  (reset-modification-dates) 
  (for-each (λ(x) ((if (pagetree-source? x)
                       render-pagetree
                       render-from-source-or-output-path) x)) xs))


(define/contract+provide (render-pagetree pagetree-or-path)
  ((or/c pagetree? pathish?) . -> . void?)
  (define pagetree (if (pagetree? pagetree-or-path)
                       pagetree-or-path
                       (cached-require pagetree-or-path (world:get-main-export))))
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


(define (directory-requires-changed? source-path)
  (define directory-require-files (get-directory-require-files source-path))
  (define rerequire-results (and directory-require-files (map file-needed-rerequire? directory-require-files)))
  (define requires-changed? (and rerequire-results (ormap (λ(x) x) rerequire-results)))
  (when requires-changed?
    (begin
      (message "render: directory require files have changed. Resetting cache & file-modification table")
      (reset-cache) ; because stored data is obsolete
      (reset-modification-dates))) ; because rendered files are obsolete
  requires-changed?)


(define/contract (render-needed? source-path template-path output-path)
  (complete-path? (or/c #f complete-path?) complete-path? . -> . boolean?)
  (or (not (file-exists? output-path))
      (modification-date-expired? source-path template-path)
      (and (not (null-source? source-path)) (file-needed-rerequire? source-path))
      (and (world:check-directory-requires-in-render?) (directory-requires-changed? source-path))))


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
  (store-render-in-modification-dates source-path template-path) ; todo?: this may need to go after render
  (apply render-proc (cons source-path (if template-path (list template-path) null))))


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
          ((dynamic-require 'scribble/render 'render) (list (dynamic-require source-path (world:get-main-export))) (list source-path))))
  (define result (file->string (->output-path source-path)))
  (delete-file (->output-path source-path)) ; because render promises the data, not the side effect
  result)


(define/contract (render-preproc-source source-path)
  (complete-path? . -> . (or/c string? bytes?))
  (match-define-values (source-dir _ _) (split-path source-path))
  (time (parameterize ([current-directory (->complete-path source-dir)])
          (render-through-eval `(begin (require pollen/cache)(cached-require ,source-path ',(world:get-main-export)))))))


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
       (let ([,(world:get-main-export) (cached-require ,(path->string source-path) ',(world:get-main-export))]
             [,(world:get-meta-export) (cached-require ,(path->string source-path) ',(world:get-meta-export))])
         (local-require pollen/pagetree pollen/template pollen/top)
         (define here (metas->here ,(world:get-meta-export)))
         (cond 
           [(bytes? ,(world:get-main-export)) ,(world:get-main-export)] ; if main export is binary, just pass it through
           [else
            (include-template #:command-char ,(world:get-command-char) (file ,(->string (find-relative-path source-dir template-path))))]))))
  (time (parameterize ([current-directory source-dir]) ; because include-template wants to work relative to source location
          (render-through-eval expr-to-eval))))


(define/contract (templated-source? path)
  (complete-path? . -> . boolean?)
  (or (markup-source? path) (markdown-source? path)))


(define/contract+provide (get-template-for source-path)
  (complete-path? . -> . (or/c #f complete-path?))
  (match-define-values (source-dir _ _) (split-path source-path))
  (and (templated-source? source-path) ; doesn't make sense if it's not a templated source format
       (let ([output-path (->output-path source-path)])
         (or ; Build the possible paths and use the first one that either exists, or has existing source (template, preproc, or null)
          (ormap (λ(p) (if (ormap file-exists? (list p (->template-source-path p) (->preproc-source-path p) (->null-source-path p))) p #f)) 
                 (filter (λ(x) (->boolean x)) ; if any of the possibilities below are invalid, they return #f 
                         (list                     
                          (parameterize ([current-directory (world:current-project-root)])
                            (let ([source-metas (cached-require source-path (world:get-meta-export))])
                              (and ((->symbol (world:get-template-meta-key)) . in? . source-metas)
                                   (build-path source-dir (select-from-metas (->string (world:get-template-meta-key)) source-metas))))) ; path based on metas
                          (and (filename-extension output-path) (build-path (world:current-project-root) 
                                                                            (add-ext (world:get-default-template-prefix) (get-ext output-path))))))) ; path to default template
          (and (filename-extension output-path) (build-path (world:current-server-extras-path) (add-ext (world:get-fallback-template-prefix) (get-ext output-path)))))))) ; fallback template


(define/contract (file-needed-rerequire? source-path)
  (complete-path? . -> . boolean?)
  (define-values (source-dir source-name _) (split-path source-path))
  ;; use dynamic-rerequire now to force render for cached-require later,
  ;; otherwise the source file will get cached by compiler
  (define port-for-catching-file-info (open-output-string))
  (parameterize ([current-directory source-dir]
                 [current-error-port port-for-catching-file-info])
    (dynamic-rerequire source-path))
  ;; if the file needed to be reloaded, there will be a message in the port
  (> (len (get-output-string port-for-catching-file-info)) 0))


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
                                   racket/rerequire 
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
                                   pollen/reader-base
                                   pollen/pagetree
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
                 [current-output-port (current-error-port)]
                 [current-pagetree (make-project-pagetree (world:current-project-root))])
    (for-each (λ(mod-name) (namespace-attach-module cache-ns mod-name)) cached-modules)   
    (eval expr-to-eval (current-namespace))))
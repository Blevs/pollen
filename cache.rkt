#lang racket/base
(require racket/rerequire racket/serialize racket/file "world.rkt")

;; The cache is a hash with paths as keys.
;; The cache values are also hashes, with key/value pairs for that path.

(provide reset-cache current-cache make-cache cached-require cache-ref)

(define (get-cache-file-path)
  (build-path (world:current-project-root) (world:current-cache-filename)))

(define (make-cache) 
  (define cache-file-path (get-cache-file-path))
  (if (file-exists? cache-file-path)
      (deserialize (file->value cache-file-path))
      (make-hash)))

(define current-cache (make-parameter (make-cache)))

(define (reset-cache)
  (define cache-path (get-cache-file-path))
  (when (file-exists? cache-path)
    (delete-file cache-path))
  (current-cache (make-cache)))

(define (->complete-path path-string)
  (path->complete-path (if (string? path-string) (string->path path-string) path-string)))

(define (cache-ref path-string)
  (hash-ref (current-cache) (->complete-path path-string)))

(define (cache-has-key? path)
  (hash-has-key? (current-cache) path))

(define (cache path)  
  (dynamic-rerequire path)
  (hash-set! (current-cache) path (make-hash))
  (define cache-hash (cache-ref path))
  (hash-set! cache-hash 'mod-time (file-or-directory-modify-seconds path))
  (hash-set! cache-hash (world:current-main-export) (dynamic-require path (world:current-main-export)))
  (hash-set! cache-hash (world:current-meta-export) (dynamic-require path (world:current-meta-export)))
  (write-to-file (serialize (current-cache)) (get-cache-file-path) #:exists 'replace)
  (void))

(define (cached-require path-string key)
  (when (not (current-cache)) (error 'cached-require "No cache set up."))
  
  (define path 
    (with-handlers ([exn:fail? (λ(exn) (error 'cached-require (format "~a is not a valid path" path-string)))])
      (->complete-path path-string)))  
  
  (when (not (file-exists? path)) (error (format "cached-require: ~a does not exist" (path->string path))))
  
  (when (or (not (cache-has-key? path))
            (> (file-or-directory-modify-seconds path) (hash-ref (cache-ref path) 'mod-time)))
    (cache path))
  
  (hash-ref (cache-ref path) key))
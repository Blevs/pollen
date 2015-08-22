#lang racket/base
(require "world.rkt" sugar/define sugar/coerce)

(define (complete-paths? x) (and (list? x) (andmap complete-path? x)))

(define/contract+provide (get-directory-require-files source-path) ; keep contract local to ensure coercion
  (coerce/path? . -> . (or/c #f complete-paths?))
  
  (define (dirname path)
    (let-values ([(dir name dir?) (split-path path)])
      dir))
  
  (define (find-upward filename-to-find)
    (parameterize ([current-directory (dirname (->complete-path source-path))])
      (let loop ([dir (current-directory)][path (string->path filename-to-find)])
        (and dir ; dir is #f when it hits the top of the filesystem
             (let ([completed-path (path->complete-path path)]) 
               (if (file-exists? completed-path)
                   (simplify-path completed-path)
                   (loop (dirname dir) (build-path 'up path))))))))

  (define require-filenames (list world:directory-require))
  (define not-false? (λ(x) x))
  (define possible-requires (filter not-false? (map find-upward require-filenames)))
  (and (not (null? possible-requires)) possible-requires))


(define+provide/contract (require+provide-directory-require-files here-path #:provide [provide #t])
  (coerce/path? . -> . (or/c list? void?))
  
  (define (put-file-in-require-form file)
    `(file ,(path->string file)))
  
  (define directory-require-files (get-directory-require-files here-path))
  
  (if directory-require-files
      (let ([files-in-require-form (map put-file-in-require-form directory-require-files)])
        `(begin
           (require ,@files-in-require-form)
           ,@(if provide
                 (list `(provide (all-from-out ,@files-in-require-form)))
                 null)))
      '(begin)))


(define+provide (require-directory-require-files here-path)
  (require+provide-directory-require-files here-path #:provide #f))
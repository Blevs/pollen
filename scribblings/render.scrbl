#lang scribble/manual

@(require scribble/eval pollen/render pollen/world (for-label racket (except-in pollen #%module-begin) pollen/world web-server/templates pollen/file sugar pollen/render))

@(define my-eval (make-base-eval))
@(my-eval `(require pollen))

@title{Render}

@defmodule[pollen/render]

@italic{Rendering} is how Pollen source files get converted into output.

@defproc[
(render
[source-path complete-path?]
[template-path (or/c #f complete-path?) #f]) 
bytes?]
Renders @racket[_source-path]. The rendering behavior depends on the type of source file (for details, see @secref["File_formats" #:doc '(lib "pollen/scribblings/pollen.scrbl")]):

A @racketmodname[pollen/pre] file is rendered without a template.

A @racketmodname[pollen/markup] or @racketmodname[pollen/markdown] file is rendered with a template. If no template is specified with @racket[_template-path], Pollen tries to find one using @racket[get-template-for].

Be aware that rendering with a template uses @racket[include-template] within @racket[eval]. For complex pages, it can be slow the first time. Caching is used to make subsequent requests faster.

For those panicked at the use of @racket[eval], please don't be. As the author of @racket[include-template] has already advised, ``If you insist on dynamicism'' — and yes, I do insist — ``@link["http://docs.racket-lang.org/web-server/faq.html#%28part._.How_do_.I_use_templates__dynamically__%29"]{there is always @racket[eval].}''

@defproc[
(render-to-file
[source-path complete-path?]
[template-path (or/c #f complete-path?) #f]
[output-path (or/c #f complete-path?) #f]) 
void?]
Like @racket[render], but saves the file to @racket[_output-path], overwriting whatever was already there. If no @racket[_output-path] is provided, it's derived from @racket[_source-path] using @racket[->output-path].

@defproc[
(render-to-file-if-needed
[source-path complete-path?]
[template-path (or/c #f complete-path?) #f]
[output-path (or/c #f complete-path?) #f]
[#:force force-render? boolean? #f]) 
void?]
Like @racket[render-to-file], but the render only happens if one of these conditions exist:
@itemlist[#:style 'ordered

@item{The @racket[_force-render?] flag — set with the @racket[#:force] keyword — is @racket[#t].}
@item{No file exists at @racket[_output-path]. (Thus, an easy way to force a render of a particular @racket[_output-path] is to delete it.)}

@item{Either @racket[_source-path] or @racket[_template-path] have changed since the last trip through @racket[render].}

@item{One or more of the project requires have changed.}]

If none of these conditions exist, @racket[_output-path] is deemed to be up to date, and the render is skipped.




@defproc[
(render-batch
[source-paths (listof pathish?)] ...) 
void?]
Render multiple @racket[_source-paths] in one go. This can be faster than @racket[(for-each render _source-paths)] if your @racket[_source-paths] rely on a common set of templates. Templates may have their own source files that need to be compiled. If you use @racket[render], the templates will be repeatedly (and needlessly) re-compiled. Whereas if you use @racket[render-batch], each template will only be compiled once.

@defproc*[
(
[(render-pagetree [pagetree pagetree?]) void?]
[(render-pagetree [pagetree-source pathish?]) void?])]
Using @racket[_pagetree], or a pagetree loaded from @racket[_pagetree-source], render the pages in that pagetree using @racket[render-batch].

Note that @racket[_pagetree] or @racket[_pagetree_source] is used strictly as a list of files to render. It is not used, for instance, as the navigational pagetree for the rendered files.

@defproc[
(get-template-for
[source-path complete-path?])
(or/c #f complete-path?)]
Find a template file for @racket[_source-path], with the following priority:
@itemlist[#:style 'ordered

@item{If the metas for @racket[_source-path] have a key for @code[(format "~a" world:template-meta-key)], then use the value of this key.}

@item{If this key doesn't exist, or if it points to a nonexistent file, look for a default template in the project directory with the name @code[(format "~a.[output extension]" world:default-template-prefix)]. Meaning, if @racket[_source-path] is @code[(format "intro.html.~a" world:markup-source-ext)], the output path would be @code["intro.html"], so the default template would be @code[(format "~a.html" world:default-template-prefix)].}

@item{If this file doesn't exist, use the fallback template as a last resort. (See @secref["Templates"
         #:tag-prefixes '("tutorial-2")
         #:doc '(lib "pollen/scribblings/pollen.scrbl")].)}
]

This function is called when a template is needed, but a @racket[_template-path] argument is missing (for instance, in @racket[render] or @racket[render-to-file]).
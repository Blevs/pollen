#lang scribble/manual
@(require scribble/bnf scribble/eval "utils.rkt" "mb-tools.rkt"
          (for-syntax racket/base)
          (for-label pollen/world pollen/render pollen/template (only-in scribble/reader
                              use-at-readtable)))

@(define read-eval (make-base-eval))
@(interaction-eval #:eval read-eval (require (for-syntax racket/base)))

@(define (at-exp-racket)
   @racket[#, @hash-lang[] #, @racketmodname[at-exp] #, @racketidfont{racket}])

@title[#:tag "reader"]{◊ command overview}

@section{The golden rule}

Pollen uses a special character — the @italic{lozenge}, which looks like this: ◊ — to mark commands  within a Pollen source file. So when you put a ◊ in your source, whatever comes next will be treated as a command. If you don't, it will just be interpreted as plain text.


@section{The lozenge glyph (◊)}

I chose the lozenge as the command character because a) it appears in almost every font, b) it's barely used in ordinary typesetting, c) it's not used in any programming language that I know of, and d) its shape and color allow it to stand out easily in code without being distracting. 

Here's how you type it:

@bold{Mac}: option + shift + V

@bold{Windows}: holding down alt, type 9674 on the num pad

@bold{Ubuntu}: ctrl + shift + U, then 25CA

Still, if you don't want to use the lozenge as your command character, you can set Pollen's @racket[world:command-char] value to whatever character you want (see also @seclink["settable-values"]).

@margin-note{Scribble uses the @"@" sign as a delimiter. It's not a bad choice if you only work with Racket files. But as you use Pollen to work on other kinds of text-based files that commonly contain @"@" signs — HTML pages especially — it gets cumbersome. So I changed it.}

But don't knock the lozenge till you try it. 

@;--------------------------------------------------------------------
@section{The two command modes: text mode & Racket mode}

Pollen commands can be entered in one of two modes: @italic{text mode} or @italic{Racket mode}. Both modes start with a lozenge (@litchar["◊"]):

@racketblock[
 @#,BNF-seq[@litchar["◊"] @nonterm{command name} @litchar{[} @nonterm{Racket arguments ...} @litchar{]} @litchar["{"] @nonterm{text argument} @litchar["}"]]
@#,BNF-seq[@litchar["◊"]
            @litchar{(} @nonterm{Racket expression} @litchar{)}]
]

@bold{Text-mode commands}

A text-mode command has the three possible parts after the @litchar["◊"]:

@itemlist[
@item{The @italic{command name} appears immediately after the @litchar["◊"]. Typically it's a short word.} 
@item{The @italic{Racket arguments} appear between square brackets. Pollen is partly an interface to the Racket programming language. These arguments are entered using Racket conventions — e.g., a @code{string of text} needs to be put in quotes as a @code{"string of text"}. If you like programming, you'll end up using these frequently. If you don't, you won't.}
@item{The @italic{text argument} appears between braces (aka curly brackets). You can put any ordinary text here. Unlike with the Racket arguments, you don't put quotes around the text.}
]

Each of the three parts is optional. You can also nest commands within each other. However:

@itemlist[
@item{You can never have spaces between the three parts.}
@item{Whatever parts you use must always appear in the order above.}
]

Here are a few examples of correct text-mode commands:

@codeblock{
  #lang pollen
  ◊variable-name
  ◊tag{Text inside the tag.}
  ◊tag['attr: "value"]{Text inside the tag}
  ◊get-customer-id["Brennan Huff"]
  ◊tag{His ID is ◊get-customer-id["Brennan Huff"].}
}

And some incorrect examples:

@codeblock{
  #lang pollen
  ◊tag {Text inside the tag.} ; space between first and second parts
  ◊tag[Text inside the tag] ; text argument needs to be within braces
  ◊tag{Text inside the tag}['attr: "value"] ; wrong order 
}

The next section describes each of these parts in detail.

@bold{Racket-mode commands}

If you're familiar with Racket expressions, you can use the Racket-mode commands to embed them within Pollen source files. It's simple: any Racket expression can become a Pollen command by adding @litchar["◊"] to the front. So in Racket, this code:

@codeblock{
  #lang racket
  (define song "Revolution")
  (format "~a #~a" song (* 3 3))
}

Can be converted to Pollen like so: 

@codeblock{
  #lang pollen
  ◊(define song "Revolution")
  ◊(format "~a #~a" song (* 3 3))
}

And in DrRacket, they produce the same output:

@repl-output{Revolution #9}


Beyond that, there's not much to say about Racket mode — any valid expression you can write in Racket will also be a valid Racket-mode Pollen command.

@bold{The relationship of text mode and Racket mode}

Even if you don't plan to write a lot of Racket-mode commands, you should be aware that under the hood, Pollen is converting all commands in text mode to Racket mode. So a text-mode command that looks like this:

@codeblock[#:keep-lang-line? #f]{
#lang pollen
◊headline[#:size 'enormous]{Man Bites Dog!}
}


Is actually being turned into a Racket-mode command like this:

@codeblock[#:keep-lang-line? #f]{
#lang racket
(headline #:size 'enormous "Man Bites Dog!")
}

Thus a text-mode command is just an alternate way of writing a Racket-mode command. (More broadly, all of Pollen is just an alternate way of using Racket.)

The corollary is that you can always write Pollen commands using whichever mode is more convenient or readable. For instance, the earlier example, written in the Racket mode:

@codeblock{
#lang pollen
◊(define song "Revolution")
◊(format "~a #~a" song (* 3 3))
}

Can be rewritten using text mode:

@codeblock{
#lang pollen
◊define[song]{Revolution}
◊format["~a #~a" song (* 3 3)]
}

And it will work the same way.


@;--------------------------------------------------------------------
@subsection{The command name}

In Pollen, you'll typically use the command name for one of four purposes:

@itemlist[
@item{To invoke a tag function.}
@item{To invoke another function.}
@item{To insert the value of a variable.}
@item{To insert a @code{meta} value.}
@item{To insert a comment.}
]

@;--------------------------------------------------------------------
@subsubsection{Invoking tag functions}

By default, Pollen treats every command name as a @italic{tag function}. The default tag function creates a tagged X-expression with the command name as the tag, and the text argument as the content.

@codeblock{
#lang pollen
◊strong{Fancy Sauce, $1} 
}

@repl-output{'(strong "Fancy Sauce, $1")}

To streamline markup, Pollen doesn't restrict you to a certain set of tags, nor does it make you define your tags ahead of time. Just type a tag, and you can start using it.


@codeblock{
  #lang pollen
  ◊utterlyridiculoustagname{Oh really?}
}

@repl-output{'(utterlyridiculoustagname "Oh really?")}



The one restriction is that you can't invent names for tags that are already being used for other commands. For instance, @code{map} is a name permanently reserved by the Racket function @racket[map]. It's also a rarely-used HTML tag. But gosh, you really want to use it. Problem is, if you invoke it directly, Pollen will think you mean the other @racket[map]: 


@codeblock{
#lang pollen
◊map{Fancy Sauce, $1} 
}

@errorblock{
map: arity mismatch;
the expected number of arguments does not match the given number
  given: 1
  arguments...:
    "Fancy Sauce, $1"}
   
What to do? Read on.

@;--------------------------------------------------------------------
@subsubsection{Invoking other functions}

Though every command name starts out as a default tag function, it doesn't necessarily end there. You have two options for invoking other functions: defining your own, or invoking others from Racket.

@bold{Defining your own functions}

Use the @racket[define] command to create your own function for a command name. After that, when you use the command name, you'll get the new behavior. For instance, recall this example showing the default tag-function behavior:

@codeblock{
#lang pollen
◊strong{Fancy Sauce, $1} 
}

@repl-output{'(strong "Fancy Sauce, $1")}

We can define @code{strong} to do something else, like add to the text:

@codeblock{
#lang pollen
◊(define (strong text) `(strong ,(format "Hey! Listen up! ~a" text)))
◊strong{Fancy Sauce, $1} 
}

@repl-output{'(strong "Hey! Listen up! Fancy Sauce, $1")}

The replacement function has to accept any arguments that might get passed along, but it doesn't have to do anything with them. For instance, this function definition won't work because @code{strong} is going to get a text argument that it's not defined to handle:

@codeblock{
#lang pollen
◊(define (strong) '(fib "1 1 2 3 5 8 13 ..."))
◊strong{Fancy Sauce, $1} 
}

@errorblock{strong: arity mismatch;
the expected number of arguments does not match the given number
  expected: 0
  given: 1
  arguments...:
    "Fancy Sauce, $1"}

Whereas in this version, @code{strong} accepts an argument called @code{text}, but then ignores it:

@codeblock|{
  #lang pollen
  ◊(define (strong text) '(fib "1 1 2 3 5 8 13 ..."))
  ◊strong{Fancy Sauce, $1} 
}|

@repl-output{'(fib "1 1 2 3 5 8 13 ...")}


You can attach any behavior to a command name. As your project evolves, you can also update the behavior of a command name. In that way, Pollen commands become a set of hooks to which you can attach more elaborate processing.

@bold{Using Racket functions}

You aren't limited to functions you define. Any function from Racket, or any Racket library, can be invoked directly by using it as a command name. Here's the function @racket[range], which creates a list of numbers:

@codeblock|{
#lang pollen
◊range[1 20]
}|

@repl-output{'(range 1 20)}

Hold on — that's not what we want. Where's the list of numbers? The problem here is that we didn't explicitly import the @racketmodname[racket/list] library, which contains the definition for @racket[range]. (If you need to find out what library contains a certain function, the Racket documentation will tell you.) Without @racketmodname[racket/list], Pollen just thinks we're trying to use @code{range} as a tag function (and if we had been, then @repl-output{'(range 1 20)} would've been the right result). 

We fix this by using the @racket[require] command to bring in the @racketmodname[racket/list] library, which contains the @racket[range]  we want:

@codeblock|{
#lang pollen
◊(require racket/list)
◊range[1 20]
}|

@repl-output{'(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19)}

Of course, you can also invoke Racket functions indirectly, by attaching them to functions you define for command names:

@codeblock|{
#lang pollen
◊(require racket/list)
◊(define (rick start finish) (range start finish))
◊rick[1 20]
}|

@repl-output{'(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19)}


Let's return to the problem that surfaced in the last section — the fact that some command names can't be used as tag functions because they're already being used for other things. You can work around this by defining your own tag function with a non-conflicting name. 

For instance, suppose we want to use @code{map} as a tag even though Racket is using it for its own function called @racket[map]. First, we invent a command name that doesn't conflict. Let's call it @code{my-map}. As you learned above, Pollen will treat a new command name as a tag function by default:

@codeblock|{
#lang pollen
◊my-map{How I would love this to be a map.}
}|

@repl-output{'(my-map "How I would love this to be a map.")}


But @code{my-map} is not the tag we want. We need to define @code{my-map} to be a tag function for @code{map}. We can do this with the Pollen helper @racket[make-default-tag-function]. That function lives in @racket[pollen/tag], so we @racket[require] that too:


@codeblock|{
#lang pollen
◊(require pollen/tag)
◊(define my-map (make-default-tag-function 'map))
◊my-map{How I would love this to be a map.}
}|

@repl-output{'(map "How I would love this to be a map.")}

Problem solved.



@;--------------------------------------------------------------------
@subsubsection{Inserting the value of a variable}

A Pollen command name usually refers to a function, but it can also refer to a @italic{variable}, which is a data value. Once you define the variable, you can insert it into your source by using the ◊ notation without any other arguments:

@codeblock|{
#lang pollen
◊(define foo "bar")
The value of foo is ◊foo
}|

@repl-output{The value of foo is bar}


Be careful — if you include arguments, even blank ones, Pollen will treat the command name as a function. This won't work, because a variable is not a function:

@margin-note{To understand what happens here, recall the relationship between Pollen's command modes. The text-mode command @code{◊foo[]} becomes the Racket-mode command @code{(foo)}, which after variable substitution becomes @code{("bar")}. If you try to evaluate @code{("bar")} — e.g., in DrRacket — you'll get the same error.}


@codeblock|{
#lang pollen
◊(define foo "bar")
The value of foo is ◊foo[]
}|


@errorblock{application: not a procedure;
expected a procedure that can be applied to arguments
  given: "bar"
  arguments...: [none]}


The reason we can simply drop @code{◊foo} into the text argument of another Pollen command is that the variable @code{foo} holds a string (i.e., a text value). 

In preprocessor source files, Pollen will convert a variable to a string in a sensible way. For instance, numbers are easily converted:

@codeblock|{
#lang pollen
◊(define zam 42)
The value of zam is ◊zam
}|

@repl-output{The value of zam is 42}

@margin-note{In an unsaved DrRacket file, or a file without a special Pollen source extension, the @tt{#lang pollen} designation invokes the Pollen preprocessor by default. You can explicitly invoke preprocessor mode by starting a file with @tt{#lang pollen/pre}. See also @secref["Preprocessor___pp_extension_"].}

If the variable holds a container datatype (like a @racket[list], @racket[hash], or @racket[vector]), Pollen will produce the Racket text representation of the item. Here, @code{zam} is a @racket[list] of integers:

@codeblock|{
#lang pollen
◊(define zam (list 1 2 3))
The value of zam is ◊zam
}|

@repl-output{The value of zam is '(1 2 3)}

This feature is included for your convenience. But in general, your readers won't want to see the Racket representation of a container. So in these cases, you should convert to a string manually in some sensible way. Here, the integers in the list are converted to strings, which are then combined using @racket[string-join] from the @racketmodname[racket/string] library:

@codeblock|{
#lang pollen
◊(require racket/string)
◊(define zam (list 1 2 3))
The value of zam is ◊string-join[(map number->string zam)]{ and }
}|

@repl-output{The value of zam is 1 and 2 and 3}

Pollen will still produce an error if you try to convert an esoteric value to a string. Here, @code{zam} is the addition function (@racket[+]):

@codeblock|{
#lang pollen
◊(define zam +)
The value of zam is ◊zam
}|

@errorblock{Pollen decoder: can't convert #<procedure:+> to string}

Moreover, Pollen will not perform @italic{any} automatic text conversion in Pollen markup source files. Suppose we take the example above — which worked as a preprocessor source file — and change the language to @racket[pollen/markup]:

@codeblock|{
#lang pollen/markup
◊(define zam (list 1 2 3))
The value of zam is ◊zam
}|

This time, the file will produce an error:

@errorblock{
  pollen markup error: in '(root "The value of zam is " (1 2 3)), '(1 2 3) is not a valid element (must be txexpr, string, symbol, XML char, or cdata)
}

One special case to know about. In the examples above, there's a word space between the variable and the other text. But suppose you need to insert a variable into text so that there's no space in between. The simple ◊ notation won't work, because it won't be clear where the variable name ends and the text begins. 

For instance, suppose we want to use a  variable @code{edge} next to the string @code{px}:

@codeblock|{
#lang pollen
◊(define edge 100)
p { margin-left: ◊edgepx; }
}|

@errorblock{Pollen decoder: can't convert #<procedure:...t/pollen/tag.rkt:6:2> to string}

The example fails because Pollen reads the whole string after the @litchar{◊} as the single variable name @code{edgepx}. Since @code{edgepx} isn't defined, it's treated as a tag function, and since Pollen can't convert a function to a string, we get an error.

In these situations, surround the variable name with vertical bars @litchar{◊|}like so@litchar{|} to explicitly indicate where the variable name ends. The bars are not treated as part of the name, nor are they included in the result. Once we do that, we get what we intended:

@codeblock|{
#lang pollen
◊(define edge 100)
p { margin-left: ◊|edge|px; }
}|

@repl-output{p { margin-left: 100px; }}

If you use this notation when you don't need to, nothing bad will happen. The vertical bars are always ignored.

@codeblock|{
#lang pollen
◊(define edge 100)
The value of edge is ◊|edge| pixels}
}|

@repl-output{The value of edge is 100 pixels}




@;--------------------------------------------------------------------
@subsubsection{Inserting metas}

@italic{Metas} are key–value pairs embedded in a source file that are not included in the main output when the source is compiled. Rather, they're gathered and exported as a separate hash table called, unsurprisingly, @racket[metas]. This hashtable is a good place to store information about the document that you might want to use later (for instance, a list of topic categories that the document belongs to).

@margin-note{Pollen occasionally uses metas internally. For instance, the @racket[get-template-for] function will look in the metas of a source file to see if a template is explicitly specified. The @racket[pollen/template] module also contains functions for working with metas, such as @racket[select-from-metas].}

To make a meta, you create a tag with the special @code{meta} name. Then you have two choices: you can either embed the key-value pair as an attribute, or as a tagged X-expression within the meta (using the key as the tag, and the value as the body):

@codeblock{
#lang pollen

◊meta['dog: "Roxy"]
◊some-tag['key: "value"]{Normal tag}
◊meta{◊cat{Chopper}}
◊some-tag['key: "value"]{Another normal tag}
}

When you run a source file with metas in it, two things happen. First, the metas are removed from the output:

@repl-output{
'(some-tag ((key "value")) "Normal tag")

'(some-tag ((key "value")) "Another normal tag")
}


Second, the metas are collected into a hash table that is exported with the name @code{metas}. To see this hash table, run the file above in DrRacket, then switch to the interactions window and type @exec{metas} at the prompt:

@terminal{
> metas
'#hash((dog . "Roxy") (cat . "Chopper") (here-path . "unsaved-editor"))
}

The only key that's automatically defined in every meta table is @code{here-path}, which is the absolute path to the source file. (In this case, because the file hasn't been saved, you'll see the @code{unsaved-editor} name instead.) 

Still, you can override this too:

@codeblock{
#lang pollen

◊meta['dog: "Roxy"]
◊some-tag['key: "value"]{Normal tag}
◊meta{◊cat{Chopper}}
◊some-tag['key: "value"]{Another normal tag}
◊meta['here-path: "tesseract"]
}

When you run this code, the result will be the same as before, but this time the metas will be different:

@terminal{
> metas
'#hash((dog . "Roxy") (cat . "Chopper") (here-path . "tesseract"))
}


It doesn't matter how many metas you put in a source file, nor where you put them. They'll all be extracted into the @code{metas} hash table. The order of the metas is not preserved (because order is not preserved in a hash table). But if you have two metas with the same key, the later one will supersede the earlier one:

@codeblock{
#lang pollen
◊meta['dog: "Roxy"]
◊meta{◊dog{Lex}}
}

In this case, though there are two metas named @racket[dog] (and they use different forms) only the second one persists:

@terminal{
> metas
'#hash((dog . "Lex") (here-path . "unsaved-editor"))
}

You can put multiple keys and values within a single @code{meta} tag, and you can mix them between attributes and elements. As above, later keys supersede earlier ones.

@codeblock{
#lang pollen
◊meta['dog: "Roxy" 'lion: "P22"]{◊dog{Lex}}
}

@terminal{
> metas
'#hash((dog . "Lex") (here-path . "unsaved-editor") (lion . "P22"))
}

Should you store your metas as attributes or elements? That's up to you, but elements are more flexible. When your key-value pair is stored as an attribute, your value has to be a string (because that's the only datatype an attribute can hold). Whereas when your key-value pair is stored as an element, you have two extra possiblilites. 

First, the value can be any X-expression. For instance, this code uses an @racket[img] tag as the meta value:

@codeblock{
#lang pollen
◊meta['dog: "Roxy"]
◊meta{◊dog{◊img['src: "lex.gif"]}}
}

@terminal{
> metas
'#hash((dog . (img ((src "roxy.gif")))) (here-path . "unsaved-editor"))
}

Second, if you use an element, the value can be either a single value or a list or values:

@codeblock{
#lang pollen
◊meta['dog: "Roxy"]
◊meta{◊categories['brindles 'boxers 'working-dogs]}
}

@terminal{
> metas
'#hash((dog . "Roxy") (here-path . "unsaved-editor") (categories . (brindles boxers working-dogs)))
}

Be aware that if you put things inside a @racket[meta] tag that don't qualify as key-value pairs, Pollen will just discard them. So don't be surprised when this:

@codeblock{
#lang pollen
◊meta['dog: "Roxy"]{This text will be ignored}
◊meta[◊cat{Chopper}]{As will this text}
}

Gets treated as if you wrote it this way:

@codeblock{
#lang pollen
◊meta['dog: "Roxy"]
◊meta[◊cat{Chopper}]
}




@;--------------------------------------------------------------------
@subsubsection{Inserting a comment}

Two options.

To comment out the rest of a single line, use a lozenge followed by a semicolon @litchar{◊;}.

@codeblock|{
#lang pollen
◊span{This is not a comment}
◊span{Nor is this} ◊;span{But this is}
}|

@repl-output{'(span "This is not a comment") 
'(span "Nor is this")}

To comment out a multiline block, use the lozenge–semicolon signal @litchar{◊;} with curly braces, @litchar{◊;@"{"}like so@litchar{@"}"}.

@codeblock|{
#lang pollen
◊;{
◊span{This is not a comment}
◊span{Nor is this} ◊;span{But this is}
}
Actually, it's all a comment now
}|


@repl-output{Actually, it's all a comment now}

@;--------------------------------------------------------------------
@subsection{The Racket arguments}

The middle part of a text-mode Pollen command contains the @italic{Racket arguments} @litchar{[}between square brackets.@litchar{]} Most often, you'll see these used to pass extra information to commands that operate on text.

For instance, tag functions. Recall from before that any not-yet-defined command name in Pollen is treated as a tag function:

@codeblock|{
#lang pollen
◊title{The Beginning of the End}
}|

@repl-output{'(title "The Beginning of the End")}

But what if you wanted to add attributes to this tag, so that it comes out like this?

@repl-output{'(title ((class "red")(id "first")) "The Beginning of the End")}

You can do it with Racket arguments. 

Here's the hard way. You can type out your list of attributes in Racket format and drop them into the brackets as a single argument:

@codeblock|{
#lang pollen
◊title['((class "red")(id "first"))]{The Beginning of the End}
}|

@repl-output{'(title ((class "red") (id "first")) "The Beginning of the End")}


But that's a lot of parentheses to think about. So here's the easy way. Anytime you use a tag function, there's a shortcut for inserting attributes. You can enter them as a series of symbol–string pairs between the Racket-argument brackets. The only caveat is that the symbols have to begin with a quote mark @litchar{'} and end with a colon @litchar{:}. So taken together, they look like this:

@codeblock|{
#lang pollen
◊title['class: "red" 'id: "first"]{The Beginning of the End}
}|

@repl-output{'(title ((class "red") (id "first")) "The Beginning of the End")}

Racket arguments can be any valid Racket expressions. For instance, this will also work:

@codeblock|{
#lang pollen
◊title['class: (format "~a" (* 6 7)) 'id: "first"]{The Beginning of the End}
}|

@repl-output{'(title ((class "42") (id "first")) "The Beginning of the End")}

Since Pollen commands are really just Racket arguments underneath, you can use those too. Here, we'll define a variable called @code{name} and use it in the Racket arguments of @code{title}:

@codeblock|{
#lang pollen
◊(define name "Brennan")
◊title['class: "red" 'id: ◊name]{The Beginning of the End}
}|

@repl-output{'(title ((class "read") (id "Brennan")) "The Beginning of the End")}

You can also use this area for @italic{keyword arguments}. Keyword arguments can be used to provide options for a particular Pollen command, to avoid redundancy. Suppose that instead of using the @code{h1 ... h6} tags, you want to consolidate them into one command called @code{heading} and select the level separately. You can do this with a keyword, in this case @racket[#:level], which is passed as a Racket argument:

@codeblock|{
#lang pollen
◊(define (heading #:level which text)
   `(,(string->symbol (format "h~a" which)) ,text))

◊heading[#:level 1]{Major league}
◊heading[#:level 2]{Minor league}
◊heading[#:level 6]{Trivial league}
}|

@repl-output{'(h1 "Major league")
'(h2 "Minor league")
'(h6 "Trivial league")
}

@;--------------------------------------------------------------------
@subsection{The text argument}

The third part of a text-mode Pollen command is the text argument. The text argument @litchar{@"{"}appears between curly braces@litchar{@"}"}. It can contain any text you want. The text argument can also contain other Pollen commands with their own text arguments. And they can contain other Pollen commands ... and so on, all the way down.

@codeblock|{
#lang pollen
◊div{Do it again. ◊div{And again. ◊div{And yet again.}}}
}|

@repl-output{'(div "Do it again. " (div "And again. " (div "And yet again.")))}

Three small details to know about the text argument.

First, the only character that needs special handling in a text argument is the lozenge @litchar{◊}. A lozenge ordinarily marks a new command. So if you want an actual lozenge to appear in the text, you have to escape it by typing @litchar{◊"◊"}.

@codeblock|{
#lang pollen
◊definition{This is the lozenge: ◊"◊"}
}|

@repl-output{'(definition "This is the lozenge: ◊")}

Second, the whitespace-trimming policy. Here's the short version: if there's a carriage return at either end of the text argument, it is trimmed, and whitespace at the end of each line is selectively trimmed in an intelligent way. So this text argument, with carriage returns on the ends:

@codeblock|{
#lang pollen
◊div{
Roomy!
     
I agree.
}
}|

@repl-output{'(div "Roomy!" "\n" "\n" "I agree.")}

Yields the same result as this one:

@codeblock|{
#lang pollen
◊div{Roomy!
     
I agree.}
}|

@repl-output{'(div "Roomy!" "\n" "\n" "I agree.")}

For the long version, please see [future link: Spaces, Newlines, and Indentation].


Third, within a multiline text argument, newline characters become individual strings that are not merged with adjacent text. So what you end up with is a list of strings, not a single string. That's why in the last example, we got this:

@repl-output{'(div "Roomy!" "\n" "\n" "I agree.")}

Instead of this:

@repl-output{'(div "Roomy!\n\nI agree.")}

Under most circumstances, these two tagged X-expressions will behave the same way. The biggest exception is with functions. A function that operates on multiline text arguments needs to be able to handle an indefinite number of strings. For instance, this @code{jejune} function only accepts a single argument. It will work with a single-line text argument, because that produces a single string:

@codeblock|{
#lang pollen
◊(define (jejune text)
   `(jejune ,text))
◊jejune{Irrational confidence}
}|

@repl-output{'(jejune "Irrational confidence")}

But watch what happens with a multiline text argument:

@codeblock|{
#lang pollen
◊(define (jejune text)
   `(jejune ,text))
◊jejune{Deeply
        chastened}
}|

@errorblock{jejune: arity mismatch;
the expected number of arguments does not match the given number
  expected: 1
  given: 3
  arguments...:
   "Deeply"
   "\n"
   "chastened"}
 
The answer is to use a @italic{rest argument} in the function, which takes the ``rest'' of the arguments — however many there may be — and combines them into a single @racket[list]. If we rewrite   @code{jejune} with a rest argument, we can fix the problem:

@codeblock|{
#lang pollen
◊(define (jejune . texts)
   `(jejune ,@texts))
◊jejune{Deeply
        chastened}
}|

@repl-output{'(jejune "Deeply" "\n" "chastened")}



@section{Further reading}

The Pollen language is a variant of Racket's own text-processing language, called Scribble. Thus, most things that can be done with Scribble syntax can also be done with Pollen syntax. For the sake of clarity & brevity, I've only shown you the highlights here. But if you want the full story, see @secref["reader" #:doc '(lib "scribblings/scribble/scribble.scrbl")] in the Scribble documentation.
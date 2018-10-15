" autoload/editorconfig_core/ini.vim: Config-file parser for
" editorconfig-core-vimscript.  Modifed from the Python core's ini.py.
" Copyright (c) 2018 Chris White.  All rights reserved.

" === Regexes =========================================================== {{{2
" Regular expressions for parsing section headers and options.
" Allow ``]`` and escaped ``;`` and ``#`` characters in section headers
let s:SECTCRE = '\v^\s*\[(%([^\\#;]|\\\#|\\\;|\\\])+)\]'

" Regular expression for parsing option name/values.
" Allow any amount of whitespaces, followed by separator
" (either ``:`` or ``=``), followed by any amount of whitespace and then
" any characters to eol
let s:OPTCRE = '\v\s*([^:=[:space:]][^:=]*)\s*([:=])\s*(.*)$'

" }}}2
" === Main ============================================================== {{{1

" Read \p config_filename and return the options applicable to
" \p target_filename.  This is the main entry point in this file.
function! editorconfig_core#ini#read_ini_file(config_filename, target_filename)
    let l:oldenc = &encoding

    if !filereadable(a:config_filename)
        return {}
    endif

    try     " so &encoding will always be reset
        let &encoding = 'utf-8'     " so readfile() will strip BOM
        let l:lines = readfile(a:config_filename)
        let result = s:parse(a:config_filename, a:target_filename, l:lines)
    catch
        let &encoding = l:oldenc
        " rethrow, but with a prefix since throw 'Vim...' fails.
        throw '!' . string(v:exception) . ' at ' . v:throwpoint
    endtry

    let &encoding = l:oldenc
    return result
endfunction

function! s:parse(config_filename, target_filename, lines)
"    """Parse a sectioned setup file.

"    The sections in setup file contains a title line at the top,
"    indicated by a name in square brackets (`[]'), plus key/value
"    options lines, indicated by `name: value' format lines.
"    Continuations are represented by an embedded newline then
"    leading whitespace.  Blank lines, lines beginning with a '#',
"    and just about everything else are ignored.
"    """

    let l:in_section = 0
    let l:matching_section = 0
    let l:optname = ''
    let l:lineno = 0
    let l:e = []    " Errors, if any

    let l:options = {}  " Options applicable to this file
    let l:is_root = 0   " Whether a:config_filename declares root=true

    while 1
        if l:lineno == len(a:lines)
            break
        endif

        let l:line = a:lines[l:lineno]
        let l:lineno = l:lineno + 1

        " comment or blank line?
        if substitute(l:line, '\v^\s+|\s$','','g') ==# ''
            continue
        endif
        if l:line =~# '\v^[#;]'
            continue
        endif

        " a section header or option header?
        " is it a section header?
        "echom "Header? <" . l:line . ">"
        let l:mo = matchlist(l:line, s:SECTCRE)
        if len(l:mo)
            let l:sectname = l:mo[1]
            let l:in_section = 1
            let l:matching_section = s:matches_filename(
                \ a:config_filename, a:target_filename, l:sectname)
            " echom 'In section ' . l:sectname . ', which ' .
            "     \ (l:matching_section ? 'matches' : 'does not match')
            "     \ ' file ' . a:target_filename . ' (config ' .
            "     \ a:config_filename . ')'

            " So sections can't start with a continuation line
            let l:optname = ''

        " an option line?
        else
            let l:mo = matchlist(l:line, s:OPTCRE)
            if len(l:mo)
                let l:optname = mo[1]
                let l:optval = mo[3]
                " echom 'Saw raw optname <' . l:optname . '>=<' . l:optval . '>'
                if l:optval =~# '\v[;#]'
                    " ';' and '#' are comment delimiters only if
                    " preceded by a spacing character
                    let l:m = matchlist(l:optval, '\v(.{-}) [;#]')
                    if len(l:m)
                        let l:optval = l:m[1]
                    endif
                endif
                let l:optval = substitute(l:optval, '\v^\s+|\s+$', '', 'g')
                " allow empty values
                if l:optval ==? '""'
                    let l:optval = ''
                endif
                let l:optname = s:optionxform(l:optname)
                if !l:in_section && optname ==? 'root'
                    let l:is_root = (optval ==? 'true')
                endif
                " echom 'Saw option ' . l:optname . ' = ' . l:optval
                if l:matching_section
                    let l:options[l:optname] = l:optval
                    "echom '  - stashed'
                endif
            else
                " a non-fatal parsing error occurred.  set up the
                " exception but keep going. the exception will be
                " raised at the end of the file and will contain a
                " list of all bogus lines
                call add(e, "Parse error in '" . a:config_filename . "' at line " .
                    \ l:lineno . ": '" . l:line . "'")
            endif
        endif
    endwhile

    " if any parsing errors occurred, raise an exception
    if len(l:e)
        throw string(l:e)
    endif

    return {'root': l:is_root, 'options': l:options}
endfunction!

" }}}1
" === Helpers =========================================================== {{{1

function! s:optionxform(optionstr)
    let l:result = substitute(a:optionstr, '\v\s+$', '', 'g')   " rstrip
    return tolower(l:result)
endfunction

" Return true if \p glob matches \p target_filename
function! s:matches_filename(config_filename, target_filename, glob)
"    config_dirname = normpath(dirname(config_filename)).replace(sep, '/')
    let l:config_dirname = fnamemodify(a:config_filename, ':p:h') . '/'
    if editorconfig_core#util#is_win()
        let l:config_dirname = substitute(l:config_dirname, '\\', '/', 'g')
    endif

    let l:glob = substitute(a:glob, '\v\\([#;])', '\1', 'g')
    if l:glob[0] ==# '/'
        let l:glob = l:glob[1:]     " trim leading slash
        let l:glob = l:config_dirname . l:glob
    else
        let l:glob = '**/' . l:glob
    endif

    "echom 'Checking <' . a:target_filename . '> against <' . l:glob . '>'
    return editorconfig_core#fnmatch#fnmatch(a:target_filename, l:glob)
endfunction

" }}}1
" === Copyright notices ================================================= {{{2
""""EditorConfig file parser

"Based on code from ConfigParser.py file distributed with Python 2.6.

"Licensed under PSF License (see LICENSE.PSF file).

"Changes to original ConfigParser:

"- Special characters can be used in section names
"- Octothorpe can be used for comments (not just at beginning of line)
"- Only track INI options in sections that match target filename
"- Stop parsing files with when ``root = true`` is found
""""
" }}}2

" vi: set fdm=marker fdl=1:

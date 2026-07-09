" =========================
" MyTodo Syntax Highlight
" =========================

syntax clear

" sub-patterns (contained)
syntax match mytodoTaskId "\d\+:" contained contains=mytodoColon
syntax match mytodoColon ":" contained
syntax match mytodoNextId "|\s*\d\+" contained contains=mytodoPipe
syntax match mytodoPipe "|" contained
syntax match mytodoStar "^\*" contained
syntax match mytodoArrow "->" contained
syntax match mytodoDate "\d\{4}-\d\{2}-\d\{2}" contained
syntax match mytodoTime "\d\{2}:\d\{2}" contained

let s:contains = 'mytodoTaskId,mytodoNextId,mytodoArrow,mytodoDate,mytodoTime,mytodoStar'

" done tasks: all one color, no sub-highlights
syntax match mytodoComment "^--.*$"

" active and plain get sub-highlights
exe 'syntax match mytodoActive "^\*.*$" contains=' . s:contains
exe 'syntax match mytodoPlain "^[0-9].*$" contains=' . s:contains

" --- HIGHLIGHTS (using pywal colors) ---

exe 'highlight mytodoComment guifg=' . g:color8 . ' gui=italic'
highlight mytodoActive gui=bold
highlight mytodoPlain guifg=NONE
exe 'highlight mytodoTaskId guifg=' . g:color1 . ' gui=bold'
exe 'highlight mytodoNextId guifg=' . g:color1 . ' gui=bold'
highlight mytodoPipe guifg=#880808 gui=bold
exe 'highlight mytodoArrow guifg=' . g:color5
highlight mytodoColon guifg=#880808
highlight mytodoStar guifg=#880808 gui=bold
exe 'highlight mytodoDate guifg=' . g:color2
exe 'highlight mytodoTime guifg=' . g:color6

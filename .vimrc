let mapleader = ','
set nocp
execute pathogen#infect()
syntax on
filetype on           " Enable filetype detection
filetype plugin indent on    " Enable filetype-specific indenting
"filetype plugin on    " Enable filetype-specific plugins
"NOTE: the latest release interacts with ruby omnicomplete in a way that can
"cause Vim to crash if both are used simultaneously.  Until a fix is released,
"adding the following line to your vimrc will work around the issue: 
silent! ruby nil

set grepprg=ack
set nocompatible
":setlocal spell spelllang=en
"set mouse=a
runtime! macros/matchit.vim

augroup myfiletypes
  autocmd!
  autocmd FileType ruby,eruby,yaml set ai sw=2 sts=2 et
augroup END

"Before tabs, these were useful.
"map * :bn
"map & :bp

"Splits navigation
map <C-J> <C-W>j<50C-W>_
map <C-K> <C-W>k<50C-W>_
"Splits resizing
map - <C-W>-
map + <C-W>+ 

"tab navigation
map <Leader>k :tabn
map <Leader>j :tabp
map <Leader>P :call Paste_on_off()<CR>
map <Leader>o <c-o>
map <Leader>i <c-i>
map <Leader>f <c-f>
map <Leader>b <c-b>

set ruler
set bs=2 "allow backspacing
set tabstop=2
"set ai  "auto indenting
set shiftwidth=2
set expandtab
set complete+=k
set dictionary+=~nkabbara/.vimdict
iab inc include 
iab req require 
iab eac each

"autocmd FileType ruby,eruby let g:rubycomplete_buffer_loading = 1

"autocmd FileType ruby,eruby let g:rubycomplete_rails = 1

"autocmd FileType ruby,eruby let g:rubycomplete_classes_in_global = 1

autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif


"augroup filetypedetect
  "au! BufRead,BufNewFile *.rhtml setfiletype xhtml
"augroup END

" Paste Mode On/Off
set pastetoggle=<F11>

let paste_mode = 0 " 0 = normal, 1 = paste

func! Paste_on_off()
  if g:paste_mode == 0
    set paste
    let g:paste_mode = 1
  else
    set nopaste
    let g:paste_mode = 0
  endif
  return
endfunc 

let g:rubycomplete_rails = 1
set path=$PWD/**,/Users/nkabbara/dev/web/mow-provision/code/**
au BufRead,BufNewfile *.liquid setfiletype xhtml
colorscheme desert

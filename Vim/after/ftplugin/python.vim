" Vim configuration for Python

setlocal tabstop=4 shiftwidth=4 expandtab smarttab
setlocal foldmethod=indent
setlocal formatoptions=croqnl1

" Fix comments dedenting
inoremap <buffer> # X#

" Allow proper formatting for comments starting with #: (used by Sphinx for
" documenting class attributes).
autocmd Filetype python setlocal comments+=b:#:

" Source code checking (flake8, pyflakes, pep8)
" Note: the Khuno plugin does similar things.
setlocal makeprg=pep8\ --repeat\ --ignore=E501\ %
let g:syntastic_python_checker_args = "--ignore=E501"

" Quick placeholders
inoreabbrev <buffer> ... ...  # TODO
inoreabbrev <buffer> rnie raise NotImplementedError

" Debugging
inoreabbrev <buffer> pdb import pdb<Return>pdb.set_trace()
inoreabbrev <buffer> ipdb import ipdb<Return>ipdb.set_trace()
inoreabbrev <buffer> ipy import IPython<Return>IPython.embed()

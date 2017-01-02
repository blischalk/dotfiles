export PS1="\[\033[36m\]\u\[\033[m\]@\[\033[36m\]\h:\[\033[33;1m\]\w\[\033[m\]\$ "
export CLICOLOR=1
export LSCOLORS=gxFxBxDxCxegedabagacad
export HISTFILESIZE=160000
export HISTSIZE=$HISTFILESIZE
export EDITOR='/usr/bin/vim'
export PATH=$PATH:$HOME/bin
export PATH=$PATH:$HOME/.cabal/bin

alias gdc="git diff --cached"
alias ga="git add"
alias gp="git pull"
alias gb="git branch"
alias gc="git commit"
alias gs="git status"
alias gd="git diff"
alias gl="git l"
alias gt="git tag"

set -o vi

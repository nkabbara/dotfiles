#Testing boostrap.sh

export PATH=$PATH:/opt/local/bin:/usr/bin:/usr/local/bin:/Users/nkabbara/bin:/usr/local/bin/android-sdk-mac_86/tools:/usr/local/bin/eclipse:/Users/nkabbara/.rvm/gems/ree-1.8.7-2011.03@zipzoomauto/bin
export MANPATH=$MANPATH:/opt/local/share/man
export INFOPATH=$INFOPATH:/opt/local/share/info

##
# Your previous /Users/nkabbara/.bash_profile file was backed up as /Users/nkabbara/.bash_profile.macports-saved_2010-09-02_at_20:34:27
##

# MacPorts Installer addition on 2010-09-02_at_20:34:27: adding an appropriate PATH variable for use with MacPorts.
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Finished adapting your PATH environment variable for use with MacPorts.


[[ -s $HOME/.rvm/scripts/rvm ]] && source $HOME/.rvm/scripts/rvm

alias l='ls -lrthG'
alias mvt='kfmclient  move'
alias vi='vim -p'
alias b='bundle exec '

# Git aliases for bash
alias gadd='git add .'
alias gst='git status'
alias gl='git pull'
alias gp='git push'
alias glog='git log'
alias gd='git diff | vim -'
alias gc='git commit -v'
alias gca='git commit -v -a'
alias gb='git branch'
alias gba='git branch -a'
alias cuc='cucumber'
alias sudo='sudo env PATH=$PATH'
alias zgit='zknock jeff && git'
alias zgrb='zknock jeff && grb'
alias zssh='zknock jeff && ssh'

set -o vi

TZ="CST6CDT"

function cdg () {
  cdargs "$1" && cd "`cat "$HOME/.cdargsresult"`" ;
}

export PS1="\u@\w$ "

export EC2_HOME=~/.ec2
export PATH=$PATH:$EC2_HOME/bin
export EC2_PRIVATE_KEY=`ls $EC2_HOME/pk-*.pem`
export EC2_CERT=`ls $EC2_HOME/cert-*.pem`
export JAVA_HOME=/System/Library/Java/JavaVirtualMachines/1.6.0.jdk/Contents/Home/

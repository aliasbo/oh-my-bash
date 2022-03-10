#! bash oh-my-bash.module
SCM_THEME_PROMPT_PREFIX="${_omb_prompt_olive}"
SCM_THEME_PROMPT_SUFFIX="${_omb_prompt_olive}"

SCM_THEME_PROMPT_DIRTY=" ${_omb_prompt_bold_brown}✗${_omb_prompt_normal}"
SCM_THEME_PROMPT_CLEAN=" ${_omb_prompt_bold_green}✓${_omb_prompt_normal}"
SCM_GIT_CHAR="${_omb_prompt_bold_green}±${_omb_prompt_normal}"
SCM_SVN_CHAR="${_omb_prompt_bold_teal}⑆${_omb_prompt_normal}"
SCM_HG_CHAR="${_omb_prompt_bold_brown}☿${_omb_prompt_normal}"

#CLOCK_THEME_PROMPT_PREFIX="${_omb_prompt_bold_teal}"
#CLOCK_THEME_PROMPT_SUFFIX="${_omb_prompt_normal}"
THEME_SHOW_CLOCK="true"
THEME_CLOCK_COLOR="${_omb_prompt_bold_navy}"
THEME_CLOCK_FORMAT="%H:%M:%S"

#Mysql Prompt
export MYSQL_PS1="(\u@\h) [\d]> "

case $TERM in
        xterm*)
        TITLEBAR="\[\033]0;\w\007\]"
        ;;
        *)
        TITLEBAR=""
        ;;
esac

PS3=">> "

__my_rvm_ruby_version() {
    local gemset=$(echo $GEM_HOME | awk -F'@' '{print $2}')
  [ "$gemset" != "" ] && gemset="@$gemset"
    local version=$(echo $MY_RUBY_HOME | awk -F'-' '{print $2}')
    local full="$version$gemset"
  [ "$full" != "" ] && echo "[$full]"
}

is_vim_shell() {
        if [ ! -z "$VIMRUNTIME" ]
        then
                echo "[${_omb_prompt_teal}vim shell${_omb_prompt_normal}]"
        fi
}

modern_scm_prompt() {
        CHAR=$(scm_char)
        if [ $CHAR = $SCM_NONE_CHAR ]
        then
                return
        else
                echo "[$(scm_char)][$(scm_prompt_info)]"
        fi
}

# show chroot if exist
chroot(){
    if [ -n "$debian_chroot" ]
    then 
        my_ps_chroot="${_omb_prompt_bold_teal}$debian_chroot${_omb_prompt_normal}";
        echo "($my_ps_chroot)";
    fi
    }

# show virtualenvwrapper
my_ve(){
    if [ -n "$VIRTUAL_ENV" ]
    then 
        my_ps_ve="${_omb_prompt_bold_purple}$ve${_omb_prompt_normal}";
        echo "($my_ps_ve)";
    fi
    echo "";
    }

_omb_theme_PROMPT_COMMAND() {

    my_ps_user_host="${_omb_prompt_bold_gray}\u@\h${_omb_prompt_normal}";
    my_ps_user_host_root="${_omb_prompt_bold_red}\u@\h${_omb_prompt_normal}";

    my_ps_path="${_omb_prompt_bold_teal}\w${_omb_prompt_normal}";

    if [ -n "$VIRTUAL_ENV" ]
    then
        ve=`basename $VIRTUAL_ENV`;
    fi

    # nice prompt
    case "`id -u`" in
        0) PS1="${TITLEBAR}┌─$(my_ve)$(chroot)[$(clock_prompt)${_omb_prompt_normal}][$my_ps_user_host_root][$my_ps_path]$(modern_scm_prompt)$(__my_rvm_ruby_version)${_omb_prompt_normal}$(is_vim_shell)
└─▪ "
        ;;
        *) PS1="${TITLEBAR}┌─$(my_ve)$(chroot)[$(clock_prompt)${_omb_prompt_normal}][$my_ps_user_host][$my_ps_path]$(modern_scm_prompt)$(__my_rvm_ruby_version)${_omb_prompt_normal}$(is_vim_shell)
└─${_omb_prompt_olive}▪ ${_omb_prompt_normal}"
        ;;
    esac
}

PS2="└─${_omb_prompt_blue}▪ ${_omb_prompt_normal}"



_omb_util_add_prompt_command _omb_theme_PROMPT_COMMAND

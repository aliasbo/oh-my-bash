# bash completion for kn                                   -*- shell-script -*-

__kn_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE:-} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__kn_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__kn_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__kn_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__kn_handle_go_custom_completion()
{
    __kn_debug "${FUNCNAME[0]}: cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}"

    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16

    local out requestComp lastParam lastChar comp directive args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly kn allows to handle aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __completeNoDesc ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __kn_debug "${FUNCNAME[0]}: lastParam ${lastParam}, lastChar ${lastChar}"

    if [ -z "${cur}" ] && [ "${lastChar}" != "=" ]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __kn_debug "${FUNCNAME[0]}: Adding extra empty parameter"
        requestComp="${requestComp} \"\""
    fi

    __kn_debug "${FUNCNAME[0]}: calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [ "${directive}" = "${out}" ]; then
        # There is not directive specified
        directive=0
    fi
    __kn_debug "${FUNCNAME[0]}: the completion directive is: ${directive}"
    __kn_debug "${FUNCNAME[0]}: the completions are: ${out[*]}"

    if [ $((directive & shellCompDirectiveError)) -ne 0 ]; then
        # Error code.  No completion.
        __kn_debug "${FUNCNAME[0]}: received error from custom completion go code"
        return
    else
        if [ $((directive & shellCompDirectiveNoSpace)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __kn_debug "${FUNCNAME[0]}: activating no space"
                compopt -o nospace
            fi
        fi
        if [ $((directive & shellCompDirectiveNoFileComp)) -ne 0 ]; then
            if [[ $(type -t compopt) = "builtin" ]]; then
                __kn_debug "${FUNCNAME[0]}: activating no file completion"
                compopt +o default
            fi
        fi
    fi

    if [ $((directive & shellCompDirectiveFilterFileExt)) -ne 0 ]; then
        # File extension filtering
        local fullFilter filter filteringCmd
        # Do not use quotes around the $out variable or else newline
        # characters will be kept.
        for filter in ${out[*]}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __kn_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif [ $((directive & shellCompDirectiveFilterDirs)) -ne 0 ]; then
        # File completion for directories only
        local subdir
        # Use printf to strip any trailing newline
        subdir=$(printf "%s" "${out[0]}")
        if [ -n "$subdir" ]; then
            __kn_debug "Listing directories in $subdir"
            __kn_handle_subdirs_in_dir_flag "$subdir"
        else
            __kn_debug "Listing directories in ."
            _filedir -d
        fi
    else
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${out[*]}" -- "$cur")
    fi
}

__kn_handle_reply()
{
    __kn_debug "${FUNCNAME[0]}"
    local comp
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            while IFS='' read -r comp; do
                COMPREPLY+=("$comp")
            done < <(compgen -W "${allflags[*]}" -- "$cur")
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __kn_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION:-}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi

            if [[ -z "${flag_parsing_disabled}" ]]; then
                # If flag parsing is enabled, we have completed the flags and can return.
                # If flag parsing is disabled, we may not know all (or any) of the flags, so we fallthrough
                # to possibly call handle_go_custom_completion.
                return 0;
            fi
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __kn_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions+=("${must_have_one_noun[@]}")
    elif [[ -n "${has_completion_function}" ]]; then
        # if a go completion function is provided, defer to that function
        __kn_handle_go_custom_completion
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    while IFS='' read -r comp; do
        COMPREPLY+=("$comp")
    done < <(compgen -W "${completions[*]}" -- "$cur")

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        while IFS='' read -r comp; do
            COMPREPLY+=("$comp")
        done < <(compgen -W "${noun_aliases[*]}" -- "$cur")
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        if declare -F __kn_custom_func >/dev/null; then
            # try command name qualified custom func
            __kn_custom_func
        else
            # otherwise fall back to unqualified for compatibility
            declare -F __custom_func >/dev/null && __custom_func
        fi
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__kn_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__kn_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
}

__kn_handle_flag()
{
    __kn_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue=""
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __kn_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __kn_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __kn_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if [[ ${words[c]} != *"="* ]] && __kn_contains_word "${words[c]}" "${two_word_flags[@]}"; then
        __kn_debug "${FUNCNAME[0]}: found a flag ${words[c]}, skip the next argument"
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__kn_handle_noun()
{
    __kn_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __kn_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __kn_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__kn_handle_command()
{
    __kn_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_kn_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __kn_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__kn_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __kn_handle_reply
        return
    fi
    __kn_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __kn_handle_flag
    elif __kn_contains_word "${words[c]}" "${commands[@]}"; then
        __kn_handle_command
    elif [[ $c -eq 0 ]]; then
        __kn_handle_command
    elif __kn_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __kn_handle_command
        else
            __kn_handle_noun
        fi
    else
        __kn_handle_noun
    fi
    __kn_handle_word
}

_kn_broker_create()
{
    last_command="kn_broker_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--class=")
    two_word_flags+=("--class")
    local_nonpersistent_flags+=("--class")
    local_nonpersistent_flags+=("--class=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_broker_delete()
{
    last_command="kn_broker_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_broker_describe()
{
    last_command="kn_broker_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_broker_list()
{
    last_command="kn_broker_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_broker()
{
    last_command="kn_broker"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_channel_create()
{
    last_command="kn_channel_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--type=")
    two_word_flags+=("--type")
    local_nonpersistent_flags+=("--type")
    local_nonpersistent_flags+=("--type=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_channel_delete()
{
    last_command="kn_channel_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_channel_describe()
{
    last_command="kn_channel_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_channel_list()
{
    last_command="kn_channel_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_channel_list-types()
{
    last_command="kn_channel_list-types"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_channel()
{
    last_command="kn_channel"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("list-types")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_completion()
{
    last_command="kn_completion"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    local_nonpersistent_flags+=("-h")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_kn_container_add()
{
    last_command="kn_container_add"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_container()
{
    last_command="kn_container"

    command_aliases=()

    commands=()
    commands+=("add")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_domain_create()
{
    last_command="kn_domain_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--ref=")
    two_word_flags+=("--ref")
    local_nonpersistent_flags+=("--ref")
    local_nonpersistent_flags+=("--ref=")
    flags+=("--tls=")
    two_word_flags+=("--tls")
    local_nonpersistent_flags+=("--tls")
    local_nonpersistent_flags+=("--tls=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--ref=")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_domain_delete()
{
    last_command="kn_domain_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_domain_describe()
{
    last_command="kn_domain_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_domain_list()
{
    last_command="kn_domain_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_domain_update()
{
    last_command="kn_domain_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--ref=")
    two_word_flags+=("--ref")
    local_nonpersistent_flags+=("--ref")
    local_nonpersistent_flags+=("--ref=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_domain()
{
    last_command="kn_domain"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_help()
{
    last_command="kn_help"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_options()
{
    last_command="kn_options"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_plugin_list()
{
    last_command="kn_plugin_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--verbose")
    local_nonpersistent_flags+=("--verbose")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_plugin()
{
    last_command="kn_plugin"

    command_aliases=()

    commands=()
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_revision_delete()
{
    last_command="kn_revision_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--prune=")
    two_word_flags+=("--prune")
    local_nonpersistent_flags+=("--prune")
    local_nonpersistent_flags+=("--prune=")
    flags+=("--prune-all")
    local_nonpersistent_flags+=("--prune-all")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_revision_describe()
{
    last_command="kn_revision_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_revision_list()
{
    last_command="kn_revision_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--service=")
    two_word_flags+=("--service")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--service")
    local_nonpersistent_flags+=("--service=")
    local_nonpersistent_flags+=("-s")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_revision()
{
    last_command="kn_revision"

    command_aliases=()

    commands=()
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_route_describe()
{
    last_command="kn_route_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_route_list()
{
    last_command="kn_route_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_route()
{
    last_command="kn_route"

    command_aliases=()

    commands=()
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_apply()
{
    last_command="kn_service_apply"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--annotation=")
    two_word_flags+=("--annotation")
    two_word_flags+=("-a")
    local_nonpersistent_flags+=("--annotation")
    local_nonpersistent_flags+=("--annotation=")
    local_nonpersistent_flags+=("-a")
    flags+=("--annotation-revision=")
    two_word_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision=")
    flags+=("--annotation-service=")
    two_word_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service=")
    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cluster-local")
    local_nonpersistent_flags+=("--cluster-local")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--concurrency-limit=")
    two_word_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--filename=")
    two_word_flags+=("--filename")
    flags_with_completion+=("--filename")
    flags_completion+=("_filedir")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--filename")
    local_nonpersistent_flags+=("--filename=")
    local_nonpersistent_flags+=("-f")
    flags+=("--force")
    local_nonpersistent_flags+=("--force")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--label=")
    two_word_flags+=("--label")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--label")
    local_nonpersistent_flags+=("--label=")
    local_nonpersistent_flags+=("-l")
    flags+=("--label-revision=")
    two_word_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision=")
    flags+=("--label-service=")
    two_word_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--lock-to-digest")
    local_nonpersistent_flags+=("--lock-to-digest")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-cluster-local")
    local_nonpersistent_flags+=("--no-cluster-local")
    flags+=("--no-lock-to-digest")
    local_nonpersistent_flags+=("--no-lock-to-digest")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--revision-name=")
    two_word_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name=")
    flags+=("--scale=")
    two_word_flags+=("--scale")
    local_nonpersistent_flags+=("--scale")
    local_nonpersistent_flags+=("--scale=")
    flags+=("--scale-init=")
    two_word_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init=")
    flags+=("--scale-max=")
    two_word_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max=")
    flags+=("--scale-min=")
    two_word_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min=")
    flags+=("--scale-target=")
    two_word_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target=")
    flags+=("--scale-utilization=")
    two_word_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization=")
    flags+=("--scale-window=")
    two_word_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--volume=")
    two_word_flags+=("--volume")
    local_nonpersistent_flags+=("--volume")
    local_nonpersistent_flags+=("--volume=")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_create()
{
    last_command="kn_service_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--annotation=")
    two_word_flags+=("--annotation")
    two_word_flags+=("-a")
    local_nonpersistent_flags+=("--annotation")
    local_nonpersistent_flags+=("--annotation=")
    local_nonpersistent_flags+=("-a")
    flags+=("--annotation-revision=")
    two_word_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision=")
    flags+=("--annotation-service=")
    two_word_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service=")
    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cluster-local")
    local_nonpersistent_flags+=("--cluster-local")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--concurrency-limit=")
    two_word_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--filename=")
    two_word_flags+=("--filename")
    flags_with_completion+=("--filename")
    flags_completion+=("_filedir")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--filename")
    local_nonpersistent_flags+=("--filename=")
    local_nonpersistent_flags+=("-f")
    flags+=("--force")
    local_nonpersistent_flags+=("--force")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--label=")
    two_word_flags+=("--label")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--label")
    local_nonpersistent_flags+=("--label=")
    local_nonpersistent_flags+=("-l")
    flags+=("--label-revision=")
    two_word_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision=")
    flags+=("--label-service=")
    two_word_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--lock-to-digest")
    local_nonpersistent_flags+=("--lock-to-digest")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-cluster-local")
    local_nonpersistent_flags+=("--no-cluster-local")
    flags+=("--no-lock-to-digest")
    local_nonpersistent_flags+=("--no-lock-to-digest")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--revision-name=")
    two_word_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name=")
    flags+=("--scale=")
    two_word_flags+=("--scale")
    local_nonpersistent_flags+=("--scale")
    local_nonpersistent_flags+=("--scale=")
    flags+=("--scale-init=")
    two_word_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init=")
    flags+=("--scale-max=")
    two_word_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max=")
    flags+=("--scale-min=")
    two_word_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min=")
    flags+=("--scale-target=")
    two_word_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target=")
    flags+=("--scale-utilization=")
    two_word_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization=")
    flags+=("--scale-window=")
    two_word_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--tag=")
    two_word_flags+=("--tag")
    local_nonpersistent_flags+=("--tag")
    local_nonpersistent_flags+=("--tag=")
    flags+=("--target=")
    two_word_flags+=("--target")
    local_nonpersistent_flags+=("--target")
    local_nonpersistent_flags+=("--target=")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--volume=")
    two_word_flags+=("--volume")
    local_nonpersistent_flags+=("--volume")
    local_nonpersistent_flags+=("--volume=")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_delete()
{
    last_command="kn_service_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    local_nonpersistent_flags+=("--all")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--target=")
    two_word_flags+=("--target")
    local_nonpersistent_flags+=("--target")
    local_nonpersistent_flags+=("--target=")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_service_describe()
{
    last_command="kn_service_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--target=")
    two_word_flags+=("--target")
    local_nonpersistent_flags+=("--target")
    local_nonpersistent_flags+=("--target=")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_service_export()
{
    last_command="kn_service_export"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--mode=")
    two_word_flags+=("--mode")
    local_nonpersistent_flags+=("--mode")
    local_nonpersistent_flags+=("--mode=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--with-revisions")
    local_nonpersistent_flags+=("--with-revisions")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_import()
{
    last_command="kn_service_import"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_list()
{
    last_command="kn_service_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--target=")
    two_word_flags+=("--target")
    local_nonpersistent_flags+=("--target")
    local_nonpersistent_flags+=("--target=")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_service_update()
{
    last_command="kn_service_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--annotation=")
    two_word_flags+=("--annotation")
    two_word_flags+=("-a")
    local_nonpersistent_flags+=("--annotation")
    local_nonpersistent_flags+=("--annotation=")
    local_nonpersistent_flags+=("-a")
    flags+=("--annotation-revision=")
    two_word_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision")
    local_nonpersistent_flags+=("--annotation-revision=")
    flags+=("--annotation-service=")
    two_word_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service")
    local_nonpersistent_flags+=("--annotation-service=")
    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cluster-local")
    local_nonpersistent_flags+=("--cluster-local")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--concurrency-limit=")
    two_word_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit")
    local_nonpersistent_flags+=("--concurrency-limit=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--label=")
    two_word_flags+=("--label")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--label")
    local_nonpersistent_flags+=("--label=")
    local_nonpersistent_flags+=("-l")
    flags+=("--label-revision=")
    two_word_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision")
    local_nonpersistent_flags+=("--label-revision=")
    flags+=("--label-service=")
    two_word_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service")
    local_nonpersistent_flags+=("--label-service=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--lock-to-digest")
    local_nonpersistent_flags+=("--lock-to-digest")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-cluster-local")
    local_nonpersistent_flags+=("--no-cluster-local")
    flags+=("--no-lock-to-digest")
    local_nonpersistent_flags+=("--no-lock-to-digest")
    flags+=("--no-wait")
    local_nonpersistent_flags+=("--no-wait")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--revision-name=")
    two_word_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name")
    local_nonpersistent_flags+=("--revision-name=")
    flags+=("--scale=")
    two_word_flags+=("--scale")
    local_nonpersistent_flags+=("--scale")
    local_nonpersistent_flags+=("--scale=")
    flags+=("--scale-init=")
    two_word_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init")
    local_nonpersistent_flags+=("--scale-init=")
    flags+=("--scale-max=")
    two_word_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max")
    local_nonpersistent_flags+=("--scale-max=")
    flags+=("--scale-min=")
    two_word_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min")
    local_nonpersistent_flags+=("--scale-min=")
    flags+=("--scale-target=")
    two_word_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target")
    local_nonpersistent_flags+=("--scale-target=")
    flags+=("--scale-utilization=")
    two_word_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization")
    local_nonpersistent_flags+=("--scale-utilization=")
    flags+=("--scale-window=")
    two_word_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window")
    local_nonpersistent_flags+=("--scale-window=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--tag=")
    two_word_flags+=("--tag")
    local_nonpersistent_flags+=("--tag")
    local_nonpersistent_flags+=("--tag=")
    flags+=("--target=")
    two_word_flags+=("--target")
    local_nonpersistent_flags+=("--target")
    local_nonpersistent_flags+=("--target=")
    flags+=("--traffic=")
    two_word_flags+=("--traffic")
    local_nonpersistent_flags+=("--traffic")
    local_nonpersistent_flags+=("--traffic=")
    flags+=("--untag=")
    two_word_flags+=("--untag")
    local_nonpersistent_flags+=("--untag")
    local_nonpersistent_flags+=("--untag=")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--volume=")
    two_word_flags+=("--volume")
    local_nonpersistent_flags+=("--volume")
    local_nonpersistent_flags+=("--volume=")
    flags+=("--wait")
    local_nonpersistent_flags+=("--wait")
    flags+=("--wait-timeout=")
    two_word_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout")
    local_nonpersistent_flags+=("--wait-timeout=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_service()
{
    last_command="kn_service"

    command_aliases=()

    commands=()
    commands+=("apply")
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("export")
    commands+=("import")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_apiserver_create()
{
    last_command="kn_source_apiserver_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--mode=")
    two_word_flags+=("--mode")
    local_nonpersistent_flags+=("--mode")
    local_nonpersistent_flags+=("--mode=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--resource=")
    two_word_flags+=("--resource")
    local_nonpersistent_flags+=("--resource")
    local_nonpersistent_flags+=("--resource=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--resource=")
    must_have_one_flag+=("--sink=")
    must_have_one_flag+=("-s")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_apiserver_delete()
{
    last_command="kn_source_apiserver_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_apiserver_describe()
{
    last_command="kn_source_apiserver_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_apiserver_list()
{
    last_command="kn_source_apiserver_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_apiserver_update()
{
    last_command="kn_source_apiserver_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--mode=")
    two_word_flags+=("--mode")
    local_nonpersistent_flags+=("--mode")
    local_nonpersistent_flags+=("--mode=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--resource=")
    two_word_flags+=("--resource")
    local_nonpersistent_flags+=("--resource")
    local_nonpersistent_flags+=("--resource=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_apiserver()
{
    last_command="kn_source_apiserver"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_binding_create()
{
    last_command="kn_source_binding_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--subject=")
    two_word_flags+=("--subject")
    local_nonpersistent_flags+=("--subject")
    local_nonpersistent_flags+=("--subject=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--sink=")
    must_have_one_flag+=("-s")
    must_have_one_flag+=("--subject=")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_binding_delete()
{
    last_command="kn_source_binding_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_binding_describe()
{
    last_command="kn_source_binding_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_binding_list()
{
    last_command="kn_source_binding_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_binding_update()
{
    last_command="kn_source_binding_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--subject=")
    two_word_flags+=("--subject")
    local_nonpersistent_flags+=("--subject")
    local_nonpersistent_flags+=("--subject=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_binding()
{
    last_command="kn_source_binding"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_container_create()
{
    last_command="kn_source_container_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--volume=")
    two_word_flags+=("--volume")
    local_nonpersistent_flags+=("--volume")
    local_nonpersistent_flags+=("--volume=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--image=")
    must_have_one_flag+=("--sink=")
    must_have_one_flag+=("-s")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_container_delete()
{
    last_command="kn_source_container_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_container_describe()
{
    last_command="kn_source_container_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_container_list()
{
    last_command="kn_source_container_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_container_update()
{
    last_command="kn_source_container_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--arg=")
    two_word_flags+=("--arg")
    local_nonpersistent_flags+=("--arg")
    local_nonpersistent_flags+=("--arg=")
    flags+=("--cmd=")
    two_word_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd")
    local_nonpersistent_flags+=("--cmd=")
    flags+=("--containers=")
    two_word_flags+=("--containers")
    local_nonpersistent_flags+=("--containers")
    local_nonpersistent_flags+=("--containers=")
    flags+=("--env=")
    two_word_flags+=("--env")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--env")
    local_nonpersistent_flags+=("--env=")
    local_nonpersistent_flags+=("-e")
    flags+=("--env-file=")
    two_word_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file")
    local_nonpersistent_flags+=("--env-file=")
    flags+=("--env-from=")
    two_word_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from")
    local_nonpersistent_flags+=("--env-from=")
    flags+=("--env-value-from=")
    two_word_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from")
    local_nonpersistent_flags+=("--env-value-from=")
    flags+=("--image=")
    two_word_flags+=("--image")
    local_nonpersistent_flags+=("--image")
    local_nonpersistent_flags+=("--image=")
    flags+=("--limit=")
    two_word_flags+=("--limit")
    local_nonpersistent_flags+=("--limit")
    local_nonpersistent_flags+=("--limit=")
    flags+=("--mount=")
    two_word_flags+=("--mount")
    local_nonpersistent_flags+=("--mount")
    local_nonpersistent_flags+=("--mount=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--port=")
    two_word_flags+=("--port")
    two_word_flags+=("-p")
    local_nonpersistent_flags+=("--port")
    local_nonpersistent_flags+=("--port=")
    local_nonpersistent_flags+=("-p")
    flags+=("--pull-secret=")
    two_word_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret")
    local_nonpersistent_flags+=("--pull-secret=")
    flags+=("--request=")
    two_word_flags+=("--request")
    local_nonpersistent_flags+=("--request")
    local_nonpersistent_flags+=("--request=")
    flags+=("--service-account=")
    two_word_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account")
    local_nonpersistent_flags+=("--service-account=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--user=")
    two_word_flags+=("--user")
    local_nonpersistent_flags+=("--user")
    local_nonpersistent_flags+=("--user=")
    flags+=("--volume=")
    two_word_flags+=("--volume")
    local_nonpersistent_flags+=("--volume")
    local_nonpersistent_flags+=("--volume=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_container()
{
    last_command="kn_source_container"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_list()
{
    last_command="kn_source_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--type=")
    two_word_flags+=("--type")
    two_word_flags+=("-t")
    local_nonpersistent_flags+=("--type")
    local_nonpersistent_flags+=("--type=")
    local_nonpersistent_flags+=("-t")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_list-types()
{
    last_command="kn_source_list-types"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_ping_create()
{
    last_command="kn_source_ping_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--data=")
    two_word_flags+=("--data")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--data")
    local_nonpersistent_flags+=("--data=")
    local_nonpersistent_flags+=("-d")
    flags+=("--encoding=")
    two_word_flags+=("--encoding")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--encoding")
    local_nonpersistent_flags+=("--encoding=")
    local_nonpersistent_flags+=("-e")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--schedule=")
    two_word_flags+=("--schedule")
    local_nonpersistent_flags+=("--schedule")
    local_nonpersistent_flags+=("--schedule=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--sink=")
    must_have_one_flag+=("-s")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_ping_delete()
{
    last_command="kn_source_ping_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_ping_describe()
{
    last_command="kn_source_ping_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_ping_list()
{
    last_command="kn_source_ping_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source_ping_update()
{
    last_command="kn_source_ping_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ce-override=")
    two_word_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override")
    local_nonpersistent_flags+=("--ce-override=")
    flags+=("--data=")
    two_word_flags+=("--data")
    two_word_flags+=("-d")
    local_nonpersistent_flags+=("--data")
    local_nonpersistent_flags+=("--data=")
    local_nonpersistent_flags+=("-d")
    flags+=("--encoding=")
    two_word_flags+=("--encoding")
    two_word_flags+=("-e")
    local_nonpersistent_flags+=("--encoding")
    local_nonpersistent_flags+=("--encoding=")
    local_nonpersistent_flags+=("-e")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--schedule=")
    two_word_flags+=("--schedule")
    local_nonpersistent_flags+=("--schedule")
    local_nonpersistent_flags+=("--schedule=")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_source_ping()
{
    last_command="kn_source_ping"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_source()
{
    last_command="kn_source"

    command_aliases=()

    commands=()
    commands+=("apiserver")
    commands+=("binding")
    commands+=("container")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("list-types")
    commands+=("ping")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_subscription_create()
{
    last_command="kn_subscription_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--channel=")
    two_word_flags+=("--channel")
    local_nonpersistent_flags+=("--channel")
    local_nonpersistent_flags+=("--channel=")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--sink-dead-letter=")
    two_word_flags+=("--sink-dead-letter")
    local_nonpersistent_flags+=("--sink-dead-letter")
    local_nonpersistent_flags+=("--sink-dead-letter=")
    flags+=("--sink-reply=")
    two_word_flags+=("--sink-reply")
    local_nonpersistent_flags+=("--sink-reply")
    local_nonpersistent_flags+=("--sink-reply=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_subscription_delete()
{
    last_command="kn_subscription_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_subscription_describe()
{
    last_command="kn_subscription_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_subscription_list()
{
    last_command="kn_subscription_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_subscription_update()
{
    last_command="kn_subscription_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--sink-dead-letter=")
    two_word_flags+=("--sink-dead-letter")
    local_nonpersistent_flags+=("--sink-dead-letter")
    local_nonpersistent_flags+=("--sink-dead-letter=")
    flags+=("--sink-reply=")
    two_word_flags+=("--sink-reply")
    local_nonpersistent_flags+=("--sink-reply")
    local_nonpersistent_flags+=("--sink-reply=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_subscription()
{
    last_command="kn_subscription"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_trigger_create()
{
    last_command="kn_trigger_create"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--broker=")
    two_word_flags+=("--broker")
    local_nonpersistent_flags+=("--broker")
    local_nonpersistent_flags+=("--broker=")
    flags+=("--filter=")
    two_word_flags+=("--filter")
    local_nonpersistent_flags+=("--filter")
    local_nonpersistent_flags+=("--filter=")
    flags+=("--inject-broker")
    local_nonpersistent_flags+=("--inject-broker")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_flag+=("--sink=")
    must_have_one_flag+=("-s")
    must_have_one_noun=()
    noun_aliases=()
}

_kn_trigger_delete()
{
    last_command="kn_trigger_delete"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_trigger_describe()
{
    last_command="kn_trigger_describe"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--verbose")
    flags+=("-v")
    local_nonpersistent_flags+=("--verbose")
    local_nonpersistent_flags+=("-v")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_trigger_list()
{
    last_command="kn_trigger_list"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all-namespaces")
    flags+=("-A")
    local_nonpersistent_flags+=("--all-namespaces")
    local_nonpersistent_flags+=("-A")
    flags+=("--allow-missing-template-keys")
    local_nonpersistent_flags+=("--allow-missing-template-keys")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--no-headers")
    local_nonpersistent_flags+=("--no-headers")
    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--show-managed-fields")
    local_nonpersistent_flags+=("--show-managed-fields")
    flags+=("--template=")
    two_word_flags+=("--template")
    flags_with_completion+=("--template")
    flags_completion+=("_filedir")
    local_nonpersistent_flags+=("--template")
    local_nonpersistent_flags+=("--template=")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_trigger_update()
{
    last_command="kn_trigger_update"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--broker=")
    two_word_flags+=("--broker")
    local_nonpersistent_flags+=("--broker")
    local_nonpersistent_flags+=("--broker=")
    flags+=("--filter=")
    two_word_flags+=("--filter")
    local_nonpersistent_flags+=("--filter")
    local_nonpersistent_flags+=("--filter=")
    flags+=("--inject-broker")
    local_nonpersistent_flags+=("--inject-broker")
    flags+=("--namespace=")
    two_word_flags+=("--namespace")
    two_word_flags+=("-n")
    local_nonpersistent_flags+=("--namespace")
    local_nonpersistent_flags+=("--namespace=")
    local_nonpersistent_flags+=("-n")
    flags+=("--sink=")
    two_word_flags+=("--sink")
    two_word_flags+=("-s")
    local_nonpersistent_flags+=("--sink")
    local_nonpersistent_flags+=("--sink=")
    local_nonpersistent_flags+=("-s")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    has_completion_function=1
    noun_aliases=()
}

_kn_trigger()
{
    last_command="kn_trigger"

    command_aliases=()

    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("list")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ls")
        aliashash["ls"]="list"
    fi
    commands+=("update")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_version()
{
    last_command="kn_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("--output")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output")
    local_nonpersistent_flags+=("--output=")
    local_nonpersistent_flags+=("-o")
    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_kn_root_command()
{
    last_command="kn"

    command_aliases=()

    commands=()
    commands+=("broker")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("brokers")
        aliashash["brokers"]="broker"
    fi
    commands+=("channel")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("channels")
        aliashash["channels"]="channel"
    fi
    commands+=("completion")
    commands+=("container")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("containers")
        aliashash["containers"]="container"
    fi
    commands+=("domain")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("domains")
        aliashash["domains"]="domain"
    fi
    commands+=("help")
    commands+=("options")
    commands+=("plugin")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("plugins")
        aliashash["plugins"]="plugin"
    fi
    commands+=("revision")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("revisions")
        aliashash["revisions"]="revision"
    fi
    commands+=("route")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("routes")
        aliashash["routes"]="route"
    fi
    commands+=("service")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("ksvc")
        aliashash["ksvc"]="service"
        command_aliases+=("services")
        aliashash["services"]="service"
    fi
    commands+=("source")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("sources")
        aliashash["sources"]="source"
    fi
    commands+=("subscription")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("sub")
        aliashash["sub"]="subscription"
        command_aliases+=("subscriptions")
        aliashash["subscriptions"]="subscription"
    fi
    commands+=("trigger")
    if [[ -z "${BASH_VERSION:-}" || "${BASH_VERSINFO[0]:-}" -gt 3 ]]; then
        command_aliases+=("triggers")
        aliashash["triggers"]="trigger"
    fi
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--cluster=")
    two_word_flags+=("--cluster")
    flags+=("--config=")
    two_word_flags+=("--config")
    flags+=("--context=")
    two_word_flags+=("--context")
    flags+=("--kubeconfig=")
    two_word_flags+=("--kubeconfig")
    flags+=("--log-http")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_kn()
{
    local cur prev words cword split
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __kn_init_completion -n "=" || return
    fi

    local c=0
    local flag_parsing_disabled=
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("kn")
    local command_aliases=()
    local must_have_one_flag=()
    local must_have_one_noun=()
    local has_completion_function=""
    local last_command=""
    local nouns=()
    local noun_aliases=()

    __kn_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_kn kn
else
    complete -o default -o nospace -F __start_kn kn
fi

# ex: ts=4 sw=4 et filetype=sh

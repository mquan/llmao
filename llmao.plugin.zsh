# Source this file from an interactive zsh, after any other missing-command hook.

function _llmao_is_prompt {
  emulate -L zsh
  setopt extendedglob
  local word
  local plain='^[[:alpha:]][[:alnum:]]*(-[[:alnum:]]+)*( [[:alnum:]]+(-[[:alnum:]]+)*)+[.]?$'
  (( $# >= 3 )) && [[ "${(j: :)@}" =~ $plain ]] || return 1
  for word in "$@"; do
    [[ $word != *[^[:alnum:].-]* ]] || return 1
  done

  if [[ ${1:l} == please ]]; then
    shift
    (( $# >= 3 )) || return 1
  fi

  case ${1:l} in
    why|what|how|where|when)
      [[ ${2:l} == (is|are|was|were|do|does|did|can|could|should|would|will|has|have|to) ]]
      ;;
    can|could|would)
      [[ ${2:l} == you ]]
      ;;
    help)
      [[ ${2:l} == me ]]
      ;;
    explain|implement|refactor|investigate|improve)
      return 0
      ;;
    fix|create|build|update|debug|add|write|review)
      [[ ${2:l} == (a|an|the|this|these|that|my|our|some|more) ]] ||
        [[ ${1:l} == fix && ${argv[-1]:l} == (bug|error|issue|tests|failure)(.)# ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# Arguments are the input word count, the input words, then the command dictionary.
# The caller declares reply locally. It receives the outcome and any suggestion.
function _llmao_classify {
  emulate -L zsh
  setopt extendedglob
  local -i word_count=$1 index length
  shift
  local -a words=( "${(@)argv[1,word_count]}" ) edits matches
  shift "$word_count"
  local name=${words[1]} prefix suffix pair
  reply=( UNKNOWN )

  [[ $name == [a-zA-Z0-9][a-zA-Z0-9_-]# ]] || return 0
  (( ${argv[(Ie)$name]} == 0 )) || return 0
  if _llmao_is_prompt "${words[@]}"; then
    reply=( AGENT_PROMPT )
    return 0
  fi

  # These are common fragments of requests even when too short or vague to launch.
  [[ ${name:l} == help && ${words[2]:l} == (me|with) ]] && return 0

  length=${#name}
  (( length >= 3 && length <= 64 )) || return 0

  # Match a single insertion, deletion, substitution or adjacent swap.
  # Three-character names only qualify for a swap, such as gti -> git.
  for (( index = 1; index <= length; ++index )); do
    prefix=${name[1,index-1]}
    suffix=${name[index+1,-1]}
    if (( length >= 4 )); then
      edits+=( "$prefix$suffix" "$prefix?$suffix" "$prefix?$name[index,-1]" )
    fi
    if (( index < length )); then
      pair=$name[index+1]$name[index]
      edits+=( "$prefix$pair$name[index+2,-1]" )
    fi
  done
  (( length < 4 )) || edits+=( "$name?" )

  local pattern="(${(j:|:)edits})"
  matches=( "${(@uM)argv:#${~pattern}}" )
  if (( ${#matches} == 1 )) && [[ ${matches[1]} == [a-zA-Z0-9][a-zA-Z0-9_-]# ]]; then
    reply=( TYPO "${matches[1]}" )
  fi
  return 0
}

function _llmao_fallback {
  if (( ${+functions[_llmao_previous_handler]} )); then
    _llmao_previous_handler "$@"
    return $?
  fi
  builtin print -ru2 -- "zsh: command not found: $1"
  return 127
}

# Explicit configuration takes precedence. Only complete, allowlisted launch
# lines can vote or supply a flag.
function _llmao_agent_args {
  emulate -L zsh
  setopt extendedglob
  reply=( "${LLMAO_AGENT:-claude}" )
  [[ -z ${LLMAO_AGENT:-} && ${LLMAO_USE_LAUNCH_HISTORY:-0} == 1 ]] || return 0

  # zsh returns history values in descending event order. Filter before taking
  # ten so unrelated commands and subcommands such as `codex review` don't vote.
  local pattern='[[:blank:]]#(codex(|[[:blank:]]##--yolo)|claude(|[[:blank:]]##--dangerously-skip-permissions))[[:blank:]]#'
  local -a launches=( "${(@M)history:#${~pattern}}" )
  local -a words
  local -A votes=( claude 0 codex 0 ) flags
  local line agent latest_agent winner
  for line in "${(@)launches[1,10]}"; do
    words=( "${(@z)line}" )
    agent=${words[1]}
    latest_agent=${latest_agent:-$agent}
    if (( votes[$agent] == 0 )); then
      flags[$agent]=${words[2]-}
    fi
    (( ++votes[$agent] ))
  done
  if (( votes[codex] > votes[claude] )); then
    winner=codex
  elif (( votes[claude] > votes[codex] )); then
    winner=claude
  else
    winner=${latest_agent:-claude}
  fi
  reply=( "$winner" )
  if [[ -n ${flags[$winner]} ]]; then
    reply+=( "${flags[$winner]}" )
  fi
}

# These arrays belong to the shell. Reading commands lets zsh populate its own
# hash on demand. There is no hook on the successful command path.
function _llmao_handle {
  emulate -L zsh
  setopt extendedglob
  local -a reply
  _llmao_classify "$#" "$@" "${(@k)commands}" "${(@k)aliases}" \
    "${(@k)functions}" "${(@k)builtins}" "${reswords[@]}"

  case ${reply[1]} in
    TYPO)
      if [[ ${LLMAO_SUGGEST_TYPOS:-1} == 1 ]]; then
        builtin print -ru2 -- "Command '$1' not found. Did you mean '${reply[2]}'?"
        return 127
      fi
      ;;
    AGENT_PROMPT)
      # History can corroborate a simple line, but it cannot undo expansion.
      local line=${history[$HISTCMD]} safe='^[[:blank:][:alnum:]_.-]+$'
      if [[ ${LLMAO_AUTO_LAUNCH:-1} == 1 && -t 0 && -t 1 && -t 2 &&
            $ZSH_SUBSHELL == 1 && ${#funcstack} == 2 && $line =~ $safe ]]; then
        local -a typed=( "${(@z)line}" )
        if [[ "${(j: :)typed}" == "${(j: :)@}" ]]; then
          _llmao_agent_args
          local label executable flag=${reply[2]-}
          case ${reply[1]} in
            claude) label='Claude Code' ;;
            codex) label='Codex' ;;
          esac
          if [[ -n $label ]] && executable=$(builtin whence -p -- "${reply[1]}"); then
            builtin print -ru2 -- "✦ Starting $label${flag:+ ($flag)}..."
            builtin exec -- "$executable" "${(@)reply[2,-1]}" "${(j: :)@}"
          fi
        fi
      fi
      ;;
  esac
  return 125
}

if [[ -o interactive ]] && builtin zmodload zsh/parameter; then
  if (( ! ${+functions[_llmao_hook]} )); then
    if (( ${+functions[command_not_found_handler]} )); then
      builtin functions -c command_not_found_handler _llmao_previous_handler
    fi
    function _llmao_hook {
      _llmao_handle "$@" || {
        local result=$?
        (( result == 125 )) || return "$result"
        _llmao_fallback "$@"
      }
    }
    builtin functions -c _llmao_hook command_not_found_handler
  fi
fi

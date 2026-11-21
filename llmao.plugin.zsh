# Source this file from an interactive zsh, after any other missing-command hook.

# Arguments are the first word and the command dictionary. The caller declares
# reply locally. A typo can block a launch even when there is no unique correction.
function _llmao_classify {
  emulate -L zsh
  setopt extendedglob
  local name=$1 prefix suffix pair
  local -i length=${#name} index
  local -a edits matches
  shift
  reply=( UNKNOWN )

  [[ -n $name && $name != */* ]] || return 0
  (( ${argv[(Ie)$name]} == 0 )) || return 0
  reply=( AGENT_PROMPT )
  (( length >= 3 && length <= 64 )) || return 0

  # Match a single insertion, deletion, substitution or adjacent swap.
  # Three-character names only qualify for a swap, such as gti -> git.
  for (( index = 1; index <= length; ++index )); do
    prefix=${(b)name[1,index-1]}
    suffix=${(b)name[index+1,-1]}
    if (( length >= 4 )); then
      edits+=( "$prefix$suffix" "$prefix?$suffix" "$prefix?${(b)name[index,-1]}" )
    fi
    if (( index < length )); then
      pair=${(b)name[index+1]}${(b)name[index]}
      edits+=( "$prefix$pair${(b)name[index+2,-1]}" )
    fi
  done
  (( length < 4 )) || edits+=( "${(b)name}?" )

  local pattern="(${(j:|:)edits})"
  matches=( "${(@uM)argv:#${~pattern}}" )
  if (( ${#matches} > 0 )); then
    reply=( TYPO )
    if (( ${#matches} == 1 )) && [[ ${matches[1]} == [[:alnum:]_.+-]## ]]; then
      reply+=( "${matches[1]}" )
    fi
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
  reply=()
  if [[ -n ${LLMAO_AGENT:-} ]]; then
    reply=( "$LLMAO_AGENT" )
    return 0
  fi

  local agent
  local -a installed
  for agent in claude codex; do
    if builtin whence -p -- "$agent" >/dev/null; then
      installed+=( "$agent" )
    fi
  done
  if (( ${#installed} == 1 )); then
    reply=( "${installed[1]}" )
  fi
  [[ ${LLMAO_USE_LAUNCH_HISTORY:-0} == 1 ]] && (( ${#installed} > 0 )) || return 0

  # The caller provides newest entries first. Filter before taking ten so
  # unrelated commands and subcommands such as `codex review` don't vote.
  local pattern='[[:blank:]]#(codex(|[[:blank:]]##--yolo)|claude(|[[:blank:]]##--dangerously-skip-permissions))[[:blank:]]#'
  local -a launches=( "${(@M)argv:#${~pattern}}" )
  local -a words
  local -A votes=( claude 0 codex 0 ) flags
  local line latest_agent winner
  for line in "${(@)launches[1,10]}"; do
    words=( "${(@z)line}" )
    agent=${words[1]}
    (( ${installed[(Ie)$agent]} )) || continue
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
    winner=$latest_agent
  fi
  [[ -n $winner ]] || return 0
  reply=( "$winner" )
  if [[ -n ${flags[$winner]} ]]; then
    reply+=( "${flags[$winner]}" )
  fi
}

function _llmao_prompt_matches {
  emulate -L zsh
  local line=$1
  shift
  # Compare literal tokens to the argv supplied by the shell without evaluating
  # the input. Expansion and compound shell syntax stay with the shell.
  [[ -n $line && $line != *[$'\n\r'\$\`\\]* ]] || return 1
  local -a typed=( "${(@z)line}" )
  (( ${#typed} == $# )) || return 1
  typed=( "${(@Q)typed}" )
  local -i index
  for (( index = 1; index <= $#; ++index )); do
    [[ ${typed[index]} == "${argv[index]}" ]] || return 1
  done
  return 0
}

# These arrays belong to the shell. Reading commands lets zsh populate its own
# hash on demand. There is no hook on the successful command path.
function _llmao_handle {
  emulate -L zsh
  setopt extendedglob
  local -a reply
  local LLMAO_AGENT=${LLMAO_AGENT-} LLMAO_USE_LAUNCH_HISTORY=${LLMAO_USE_LAUNCH_HISTORY-}
  local LLMAO_AUTO_LAUNCH=${LLMAO_AUTO_LAUNCH-} LLMAO_SUGGEST_TYPOS=${LLMAO_SUGGEST_TYPOS-}
  local config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/llmao setting
  for setting in LLMAO_AGENT LLMAO_USE_LAUNCH_HISTORY LLMAO_AUTO_LAUNCH LLMAO_SUGGEST_TYPOS; do
    if [[ -r $config_dir/$setting ]]; then
      IFS= builtin read -r "$setting" < "$config_dir/$setting" || :
    fi
  done
  _llmao_classify "$1" "${(@k)commands}" "${(@k)aliases}" \
    "${(@k)functions}" "${(@k)builtins}" "${reswords[@]}"

  case ${reply[1]} in
    TYPO)
      if [[ ${LLMAO_SUGGEST_TYPOS:-1} == 1 && -n ${reply[2]-} ]]; then
        builtin print -ru2 -- "Command '$1' not found. Did you mean '${reply[2]}'?"
        return 127
      fi
      ;;
    AGENT_PROMPT)
      # History can corroborate a simple line, but it cannot undo expansion.
      if [[ ${LLMAO_AUTO_LAUNCH:-1} == 1 && -t 0 && -t 1 && -t 2 &&
            $ZSH_SUBSHELL == 1 && ${#funcstack} == 2 ]] &&
         _llmao_prompt_matches "${history[$HISTCMD]}" "$@"; then
        if [[ -z ${LLMAO_AGENT:-} && ${LLMAO_USE_LAUNCH_HISTORY:-0} == 1 ]]; then
          _llmao_agent_args "${history[@]}"
        else
          _llmao_agent_args
        fi
        local label executable flag=${reply[2]-}
        case ${reply[1]} in
          claude) label='Claude Code' ;;
          codex) label='Codex' ;;
        esac
        if [[ -n $label ]] && executable=$(builtin whence -p -- "${reply[1]}"); then
          builtin print -ru2 -- "✦ Starting $label${flag:+ ($flag)}..."
          builtin exec -- "$executable" "${(@)reply[2,-1]}" -- "${(j: :)@}"
        fi
      fi
      ;;
  esac
  return 125
}

if [[ -o interactive ]] && builtin zmodload zsh/parameter; then
  if (( ! ${+functions[_llmao_hook]} )); then
    typeset -g _llmao_zsh_dir=${${(%):-%x}:A:h}
    if [[ -x $_llmao_zsh_dir/llmao ]] && ! builtin whence llmao >/dev/null; then
      function llmao {
        "$_llmao_zsh_dir/llmao" "$@"
      }
    fi
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

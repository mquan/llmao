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

  local -a agents=( claude codex opencode devin copilot agy cursor-agent gemini kiro-cli qwen goose pi cline amp auggie )
  local agent executable cursor_executable
  local -a installed
  for agent in "${agents[@]}"; do
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
  local -a launch_patterns=( "${agents[@]}"
    'codex[[:blank:]]##--yolo' 'claude[[:blank:]]##--dangerously-skip-permissions'
    'cursor-agent[[:blank:]]##agent' 'kiro-cli[[:blank:]]##chat' 'goose[[:blank:]]##session' )
  if cursor_executable=$(builtin whence -p -- cursor-agent) && executable=$(builtin whence -p -- agent) &&
     [[ $cursor_executable -ef $executable ]]; then
    launch_patterns+=( agent 'agent[[:blank:]]##agent' )
  fi
  local pattern="[[:blank:]]#(${(j:|:)launch_patterns})[[:blank:]]#"
  local -a launches=( "${(@M)argv:#${~pattern}}" )
  local -a words recent_agents
  local -A votes flags
  local line winner
  local -i winning_votes=0
  for line in "${(@)launches[1,10]}"; do
    words=( "${(@z)line}" )
    agent=${words[1]}
    [[ $agent != agent ]] || agent=cursor-agent
    (( ${installed[(Ie)$agent]} )) || continue
    if (( votes[$agent] == 0 )); then
      case $agent in
        claude|codex) flags[$agent]=${words[2]-} ;;
      esac
      recent_agents+=( "$agent" )
    fi
    (( ++votes[$agent] ))
  done
  for agent in "${recent_agents[@]}"; do
    if (( votes[$agent] > winning_votes )); then
      winner=$agent
      winning_votes=${votes[$agent]}
    fi
  done
  [[ -n $winner ]] || return 0
  reply=( "$winner" )
  if [[ -n ${flags[$winner]} ]]; then
    reply+=( "${flags[$winner]}" )
  fi
}

# Return the display label and the exact arguments for an interactive launch.
function _llmao_agent_command {
  emulate -L zsh
  local agent=$1 flag=$2 prompt=$3 label
  local -a args
  case $agent in
    claude) label='Claude Code'; args=( -- "$prompt" ) ;;
    codex) label=Codex; args=( -- "$prompt" ) ;;
    opencode) label=OpenCode; args=( "--prompt=$prompt" ) ;;
    devin) label='Devin CLI'; args=( -- "$prompt" ) ;;
    copilot) label='GitHub Copilot CLI'; args=( "--interactive=$prompt" ) ;;
    agy) label='Antigravity CLI'; args=( "--prompt-interactive=$prompt" ) ;;
    cursor-agent) label='Cursor CLI'; args=( agent -- "$prompt" ) ;;
    gemini) label='Gemini CLI'; args=( "--prompt-interactive=$prompt" ) ;;
    kiro-cli) label='Kiro CLI'; args=( chat -- "$prompt" ) ;;
    qwen) label='Qwen Code'; args=( "--prompt-interactive=$prompt" ) ;;
    goose) label=Goose; args=( run --interactive "--text=$prompt" ) ;;
    pi) label=Pi; args=( -- "$prompt" ) ;;
    cline) label='Cline CLI'; args=( -i -- "$prompt" ) ;;
    amp) label=Amp; args=( "$prompt" ) ;;
    auggie) label='Auggie CLI'; args=( -- "$prompt" ) ;;
    *) return 1 ;;
  esac
  if [[ -n $flag ]]; then
    label+=" ($flag)"
    args=( "$flag" "${args[@]}" )
  fi
  reply=( "$label" "${args[@]}" )
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
        local executable agent=${reply[1]-}
        if _llmao_agent_command "$agent" "${reply[2]-}" "${(j: :)@}" &&
           executable=$(builtin whence -p -- "$agent"); then
          builtin print -ru2 -- "✦ Starting ${reply[1]}..."
          if [[ $agent == amp ]]; then
            builtin exec -- "$executable" < <(builtin print -r -- "${reply[2]}")
          else
            builtin exec -- "$executable" "${(@)reply[2,-1]}"
          fi
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

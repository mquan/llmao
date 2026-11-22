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

function _llmao_agent_names {
  reply=( claude codex opencode devin copilot agy cursor-agent gemini kiro-cli qwen goose pi cline amp auggie )
}

function _llmao_installed_agents {
  reply=()
  local agent
  for agent; do
    if builtin whence -p -- "$agent" >/dev/null; then
      reply+=( "$agent" )
    fi
  done
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

  _llmao_agent_names
  local -a agents=( "${reply[@]}" )
  _llmao_installed_agents "${agents[@]}"
  local -a installed=( "${reply[@]}" )
  reply=()
  local agent executable cursor_executable
  if (( ${#installed} == 1 )); then
    reply=( "${installed[1]}" )
  fi
  [[ ${LLMAO_USE_LAUNCH_HISTORY:-1} == 1 ]] && (( ${#installed} > 0 )) || return 0

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
  # Replay permission flags only when launch history was explicitly enabled.
  if [[ ${LLMAO_USE_LAUNCH_HISTORY:-} == 1 && -n ${flags[$winner]} ]]; then
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
  [[ -n $line && $line != *[$'\n\r']* ]] || return 1
  local -a typed=( "${(@z)line}" )
  (( ${#typed} == $# )) || return 1
  local token
  for token in "${typed[@]}"; do
    # These characters are literal in a whole single-quoted shell word.
    if [[ $token == *[\$\`\\]* && ( $token != \'*\' || ${token[2,-2]} == *\'* ) ]]; then
      return 1
    fi
  done
  typed=( "${(@Q)typed}" )
  local -i index
  for (( index = 1; index <= $#; ++index )); do
    [[ ${typed[index]} == "${argv[index]}" ]] || return 1
  done
  return 0
}

function _llmao_read_setting {
  local setting_file=${XDG_CONFIG_HOME:-$HOME/.config}/llmao/$1
  if [[ -r $setting_file ]]; then
    IFS= builtin read -r "$1" < "$setting_file" || :
  fi
}

function _llmao_exec_agent {
  local agent=$1 executable
  local -a reply
  _llmao_agent_command "$@" && executable=$(builtin whence -p -- "$agent") || return 125
  builtin print -ru2 -- "✦ Starting ${reply[1]}..."
  if [[ $agent == amp ]]; then
    builtin exec -- "$executable" < <(builtin print -r -- "${reply[2]}")
  else
    builtin exec -- "$executable" "${(@)reply[2,-1]}"
  fi
}

function _llmao_ask {
  emulate -L zsh
  local usage='Usage: llmao ask [--agent NAME] [--] PROMPT'
  local agent
  local -a reply
  case ${1-} in
    -h|--help) builtin print -r -- "$usage"; return 0 ;;
    --agent)
      [[ -n ${2-} ]] || { builtin print -ru2 -- "$usage"; return 2; }
      agent=$2
      shift 2
      ;;
  esac
  [[ ${1-} != -- ]] || shift
  [[ -n ${(j: :)@} ]] || { builtin print -ru2 -- "$usage"; return 2; }
  [[ -t 0 && -t 1 && -t 2 ]] || {
    builtin print -ru2 -- 'llmao ask needs an interactive terminal.'
    return 1
  }
  if [[ -z $agent ]]; then
    local LLMAO_AGENT=${LLMAO_AGENT-} LLMAO_USE_LAUNCH_HISTORY=0
    _llmao_read_setting LLMAO_AGENT
    _llmao_agent_args
    agent=${reply[1]-}
    if [[ -z $agent ]]; then
      _llmao_agent_names
      _llmao_installed_agents "${reply[@]}"
      if (( ! ${#reply} )); then
        builtin print -ru2 -- 'No supported coding agent is installed.'
        return 1
      fi
      local PS3='Choose a coding agent: '
      select agent in "${reply[@]}"; do
        [[ -z $agent ]] || break
      done
      [[ -n $agent ]] || return 1
    fi
  fi
  _llmao_exec_agent "$agent" '' "${(j: :)@}"
  builtin print -ru2 -- "Coding agent unavailable: $agent"
  return 1
}

function _llmao_prompt_hint {
  (( $# >= 4 )) && _llmao_prompt_matches "$@" || return 1
  local word
  for word in "${@[3,-1]}"; do
    [[ $word == [[:alpha:]]* && $word != */* ]] || return 1
  done
  builtin print -r -- 'To send this as a prompt, use llmao ask with the text in quotes.'
}

# These arrays belong to the shell. Reading commands lets zsh populate its own
# hash on demand.
function _llmao_classify_shell_word {
  _llmao_classify "$1" "${(@k)commands}" "${(@k)aliases}" \
    "${(@k)functions}" "${(@k)builtins}" "${reswords[@]}"
}

function _llmao_quote_question_mark {
  [[ $BUFFER == *\?* && $CONTEXT == start && -o glob && -o nomatch && ! -o nullglob ]] || return 0
  [[ ! -o histignorespace || $BUFFER != ' '* ]] || return 0
  setopt localoptions extendedglob noksharrays nobashrematch
  local MATCH MBEGIN MEND
  local -a match mbegin mend reply
  local plain_question='^([[:blank:]]*([[:alpha:]][[:alnum:]_-]*)[[:blank:]]+([[:alnum:]_,.-]+[[:blank:]]+)*([[:alnum:]_,.-]*[[:alnum:]]))\?([[:blank:]]*)$'
  [[ $BUFFER =~ $plain_question ]] || return 0
  local question="${match[1]}'?'${match[5]}" first_word=${match[2]} pattern="${match[4]}?"
  local LLMAO_AUTO_LAUNCH=${LLMAO_AUTO_LAUNCH-}
  _llmao_read_setting LLMAO_AUTO_LAUNCH
  [[ ${LLMAO_AUTO_LAUNCH:-1} == 1 ]] || return 0
  _llmao_classify_shell_word "$first_word"
  [[ $reply[1] == AGENT_PROMPT ]] || return 0
  local word
  for word in ${(z)BUFFER}; do
    [[ -z ${galiases[$word]+x} ]] || return 0
  done

  # Retain real filename matches. Quote only when the wildcard would fail
  # before zsh could call the missing-command handler.
  local -a filenames=( ${~pattern}(#qN) )
  (( ! ${#filenames} )) || return 0

  # Leave zsh's original error in place if this shell has no launch target.
  [[ ${functions[command_not_found_handler]} == "${functions[_llmao_hook]}" ]] || return 0
  local LLMAO_AGENT=${LLMAO_AGENT-} LLMAO_USE_LAUNCH_HISTORY=${LLMAO_USE_LAUNCH_HISTORY-}
  _llmao_read_setting LLMAO_AGENT
  _llmao_read_setting LLMAO_USE_LAUNCH_HISTORY
  _llmao_agent_args "${history[@]}"
  local agent=${reply[1]-}
  _llmao_agent_command "$agent" '' '' && builtin whence -p -- "$agent" >/dev/null || return 0
  BUFFER=$question
  return 0
}

function _llmao_handle {
  emulate -L zsh
  setopt extendedglob
  local -a reply
  local LLMAO_AGENT=${LLMAO_AGENT-} LLMAO_USE_LAUNCH_HISTORY=${LLMAO_USE_LAUNCH_HISTORY-}
  local LLMAO_AUTO_LAUNCH=${LLMAO_AUTO_LAUNCH-} LLMAO_SUGGEST_TYPOS=${LLMAO_SUGGEST_TYPOS-}
  local setting
  for setting in LLMAO_AGENT LLMAO_USE_LAUNCH_HISTORY LLMAO_AUTO_LAUNCH LLMAO_SUGGEST_TYPOS; do
    _llmao_read_setting "$setting"
  done
  _llmao_classify_shell_word "$1"

  case ${reply[1]} in
    TYPO)
      if [[ ${LLMAO_SUGGEST_TYPOS:-1} == 1 && -n ${reply[2]-} ]]; then
        builtin print -ru2 -- "Command '$1' not found. Did you mean '${reply[2]}'?"
        return 127
      fi
      if [[ ${LLMAO_SUGGEST_TYPOS:-1} == 1 && ${LLMAO_AUTO_LAUNCH:-1} == 1 && -z ${reply[2]-} &&
            -t 0 && -t 1 && -t 2 && $ZSH_SUBSHELL == 1 && ${#funcstack} == 2 ]]; then
        _llmao_prompt_hint "${history[$HISTCMD]}" "$@" >&2
      fi
      ;;
    AGENT_PROMPT)
      # History can corroborate a simple line, but it cannot undo expansion.
      if [[ ${LLMAO_AUTO_LAUNCH:-1} == 1 && -t 0 && -t 1 && -t 2 &&
            $ZSH_SUBSHELL == 1 && ${#funcstack} == 2 ]] &&
         _llmao_prompt_matches "${history[$HISTCMD]}" "$@"; then
        if [[ -z ${LLMAO_AGENT:-} && ${LLMAO_USE_LAUNCH_HISTORY:-1} == 1 ]]; then
          _llmao_agent_args "${history[@]}"
        else
          _llmao_agent_args
        fi
        _llmao_exec_agent "${reply[1]-}" "${reply[2]-}" "${(j: :)@}"
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
    if [[ -o zle ]] && builtin zmodload zsh/zle; then
      autoload -Uz add-zle-hook-widget
      add-zle-hook-widget line-finish _llmao_quote_question_mark
    fi
  fi
fi

# Source from interactive Bash 4+ after any other missing-command integration.
[[ $- == *i* && ${BASH_VERSINFO[0]} -ge 4 ]] || return 0
[[ ! ${_llmao_bash_dir+x} && -x /bin/zsh ]] || return 0
_llmao_bash_file=${BASH_SOURCE[0]}
case $_llmao_bash_file in
  */*) _llmao_bash_dir=$(CDPATH= builtin cd -- "${_llmao_bash_file%/*}" && builtin pwd -P) ;;
  *) _llmao_bash_dir=$PWD ;;
esac
unset _llmao_bash_file
[[ -r $_llmao_bash_dir/llmao-bridge.zsh ]] || return 0
if [[ -x $_llmao_bash_dir/llmao ]] && ! builtin type llmao >/dev/null 2>&1; then
  function llmao {
    "$_llmao_bash_dir/llmao" "$@"
  }
fi

if _llmao_original=$(builtin declare -f command_not_found_handle); then
  # Copy a function already defined by the shell configuration.
  builtin eval "${_llmao_original/#command_not_found_handle /_llmao_previous_bash_handler }"
fi
unset _llmao_original

# Bash history can omit a line (e.g. ignorespace). Record the next expected
# event at the prompt so a stale history entry cannot approve expanded input.
_llmao_bash_prompt() {
  _llmao_bash_next_history=$HISTCMD
}
_llmao_prompt_declaration=$(builtin declare -p PROMPT_COMMAND 2>/dev/null) || _llmao_prompt_declaration=
if [[ ! $_llmao_prompt_declaration =~ ^declare\ -[^[:space:]]*r ]]; then
  if [[ $_llmao_prompt_declaration == 'declare -a'* ]] &&
     (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
    PROMPT_COMMAND+=(_llmao_bash_prompt)
  else
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_llmao_bash_prompt"
  fi
fi
unset _llmao_prompt_declaration

command_not_found_handle() {
  local raw= entry marker= decision kind agent flag executable label
  local LLMAO_AGENT=${LLMAO_AGENT-} LLMAO_USE_LAUNCH_HISTORY=${LLMAO_USE_LAUNCH_HISTORY-}
  local LLMAO_AUTO_LAUNCH=${LLMAO_AUTO_LAUNCH-} LLMAO_SUGGEST_TYPOS=${LLMAO_SUGGEST_TYPOS-}
  local config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/llmao setting
  for setting in LLMAO_AGENT LLMAO_USE_LAUNCH_HISTORY LLMAO_AUTO_LAUNCH LLMAO_SUGGEST_TYPOS; do
    if [[ -r $config_dir/$setting ]]; then
      IFS= builtin read -r "$setting" < "$config_dir/$setting" || :
    fi
  done
  if [[ ${LLMAO_AUTO_LAUNCH:-1} == 1 && -t 0 && -t 1 && -t 2 &&
        $BASH_SUBSHELL == 0 && ${#FUNCNAME[@]} == 1 &&
        $HISTCMD == "${_llmao_bash_next_history-}" ]] && builtin shopt -qo history; then
    entry=$(HISTTIMEFORMAT= builtin history 1)
    if [[ $entry =~ ^[[:blank:]]*"$HISTCMD"[[:blank:]]+(.*)$ ]]; then
      raw=${BASH_REMATCH[1]}
    fi
    if [[ -n $raw && -z ${LLMAO_AGENT:-} && ${LLMAO_USE_LAUNCH_HISTORY:-0} == 1 ]]; then
      marker="llmao-${BASHPID}-${RANDOM}-${RANDOM}:"
    fi
  fi

  local -a dictionary agent_args=()
  builtin mapfile -t dictionary < <(builtin compgen -A alias -A function -A builtin -A keyword)
  decision=$(
    if [[ -n $marker ]]; then HISTTIMEFORMAT=$marker builtin history; fi |
      /bin/zsh -df "$_llmao_bash_dir/llmao-bridge.zsh" "$marker" "$raw" \
        "${LLMAO_AGENT-}" "${LLMAO_USE_LAUNCH_HISTORY-}" "$#" "$@" "${dictionary[@]}"
  )
  IFS=' ' read -r kind agent flag <<< "$decision"
  case $kind in
    typo)
      if [[ ${LLMAO_SUGGEST_TYPOS:-1} == 1 ]]; then
        builtin printf "Command '%s' not found. Did you mean '%s'?\n" "$1" "$agent" >&2
        return 127
      fi
      ;;
    prompt)
      if executable=$(builtin type -P -- "$agent"); then
        case $agent in
          claude) label='Claude Code' ;;
          codex) label='Codex' ;;
        esac
        [[ -z $flag ]] || agent_args+=( "$flag" )
        builtin printf '✦ Starting %s%s...\n' "$label" "${flag:+ ($flag)}" >&2
        local IFS=' '
        builtin exec -- "$executable" "${agent_args[@]}" -- "$*"
      fi
      ;;
  esac

  if builtin declare -F _llmao_previous_bash_handler >/dev/null; then
    _llmao_previous_bash_handler "$@"
    return $?
  fi
  builtin printf 'bash: %s: command not found\n' "$1" >&2
  return 127
}

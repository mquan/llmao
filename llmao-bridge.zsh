# Bash and Fish call this in macOS's stock zsh, and only on a command miss.
source "${0:A:h}/llmao.plugin.zsh"
emulate -L zsh
zmodload zsh/parameter

local input_format=$1 raw=$2 LLMAO_AGENT=$3 LLMAO_USE_LAUNCH_HISTORY=$4
local -i count=$5
shift 5
local -a reply launches words=( "${(@)argv[1,count]}" )
shift "$count"
_llmao_classify "${words[1]}" "$@" "${(@k)commands}"

case ${reply[1]} in
  TYPO)
    [[ -z ${reply[2]-} ]] || print -r -- "typo ${reply[2]}"
    ;;
  AGENT_PROMPT)
    _llmao_prompt_matches "$raw" "${words[@]}" || exit 0
    if [[ -z $LLMAO_AGENT && $LLMAO_USE_LAUNCH_HISTORY == 1 ]]; then
      local entry
      if [[ $input_format == fish ]]; then
        # Fish supplies most recent first, preserving multiline entry boundaries.
        while IFS= read -r -d '' entry; do
          launches+=( "$entry" )
        done
      elif [[ -n $input_format ]]; then
        # Bash history is oldest first. The per-call marker distinguishes event
        # headers from continuation lines, and multiline entries do not vote.
        local line header="^[[:blank:]]*[0-9]+[[:blank:]]+${input_format}(.*)$"
        while IFS= read -r line; do
          if [[ $line =~ $header ]]; then
            [[ -z $entry ]] || launches+=( "$entry" )
            entry=${match[1]}
          else
            entry=''
          fi
        done
        [[ -z $entry ]] || launches+=( "$entry" )
        launches=( "${(@Oa)launches}" )
      fi
    fi
    _llmao_agent_args "${launches[@]}"
    case ${reply[1]} in
      claude|codex) print -r -- prompt "${reply[@]}" ;;
    esac
    ;;
esac

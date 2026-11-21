#!/bin/zsh -f
emulate -L zsh
setopt extendedglob
cd -- "${0:A:h}/.." || exit 1
source ./llmao.plugin.zsh
zmodload zsh/datetime

typeset -a dictionary reply words
typeset -i total failures false_launches missed_prompts typo_total typo_correct
typeset -F 6 elapsed=0 max_elapsed=0
typeset -F start duration

check() {
  local expected=$1 input=$2 suggestion=${3-}
  words=( "${(@z)input}" )
  # Decode quoting without performing substitutions or running the input.
  words=( "${(@Q)words}" )
  start=$EPOCHREALTIME
  _llmao_classify "${#words}" "${words[@]}" "${dictionary[@]}"
  duration=$(( EPOCHREALTIME - start ))
  (( elapsed += duration, max_elapsed = duration > max_elapsed ? duration : max_elapsed ))
  (( ++total ))
  [[ $expected == TYPO ]] && (( ++typo_total ))
  if [[ ${reply[1]} == "$expected" && ${reply[2]-} == "$suggestion" ]]; then
    [[ $expected == TYPO ]] && (( ++typo_correct ))
  else
    (( ++failures ))
    [[ ${reply[1]} == AGENT_PROMPT && $expected != AGENT_PROMPT ]] && (( ++false_launches ))
    [[ $expected == AGENT_PROMPT && ${reply[1]} != AGENT_PROMPT ]] && (( ++missed_prompts ))
    print -ru2 -- "$input -> ${reply[*]} (expected $expected $suggestion)"
  fi
}

for profile in developer minimal; do
  dictionary=( git python kubectl docker npm pnpm node cargo claude codex grep printf make curl )
  if [[ $profile == developer ]]; then
    dictionary+=( bun zig go rustup helm terraform ruby swift xcodebuild ls cat fi git-lfs )
  fi
  while IFS=$'\t' read -r expected input suggestion; do
    check "$expected" "$input" "$suggestion"
  done < tests/corpus.tsv
done

dictionary=( git "weird|name" )
check TYPO 'gti status' git
check UNKNOWN 'pyhton app.py'
dictionary=( python python3 )
check TYPO 'pyhton app.py' python
dictionary=( python python3 pythn )
check UNKNOWN 'pyton app.py'
dictionary=( fit )
check AGENT_PROMPT 'fix the login bug'
dictionary=( fix fit )
check UNKNOWN 'fix the login bug'
dictionary=( docker docker )
check TYPO 'dcoker --version' docker
dictionary=( npm )
check UNKNOWN 'np test'
check UNKNOWN 'npx test'

printf '%d cases, %d failed\n' "$total" "$failures"
printf '%d false agent launches, %d missed prompts, %d/%d typos correctly suggested\n' \
  "$false_launches" "$missed_prompts" "$typo_correct" "$typo_total"
printf 'Classifier mean %.3f ms, max %.3f ms (fixture dictionaries)\n' \
  "$((elapsed * 1000 / total))" "$((max_elapsed * 1000))"

zmodload zsh/parameter
dictionary=( "${(@k)commands}" "${(@k)aliases}" "${(@k)builtins}" )
start=$EPOCHREALTIME
repeat 150; do
  _llmao_classify 2 gti status "${dictionary[@]}"
  _llmao_classify 3 explain this error "${dictionary[@]}"
  _llmao_classify 2 unknown-llmao-benchmark --help "${dictionary[@]}"
done
printf 'Classifier mean %.3f ms with local dictionary (%d entries, 450 calls)\n' \
  "$(((EPOCHREALTIME - start) * 1000 / 450))" "${#dictionary}"
(( failures == 0 ))

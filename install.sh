#!/bin/sh
set -eu

case ${1-} in
  '') activate=0 ;;
  --activate) activate=1 ;;
  *) printf 'Usage: %s [--activate]\n' "$0" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [--activate]\n' "$0" >&2
  exit 2
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/llmao
activation='source "${XDG_DATA_HOME:-$HOME/.local/share}/llmao/llmao.plugin.zsh"'

mkdir -p "$target_dir"
install -m 644 "$source_dir/llmao.plugin.zsh" "$target_dir/llmao.plugin.zsh"
printf 'Installed %s\n' "$target_dir/llmao.plugin.zsh"

if [ "$activate" -eq 1 ]; then
  config_dir=${ZDOTDIR:-"$HOME"}
  config=$config_dir/.zshrc
  mkdir -p "$config_dir"
  if ! grep -Fqx -- "$activation" "$config" 2>/dev/null; then
    printf '\n%s\n' "$activation" >> "$config"
  fi
  printf 'Open a new zsh session to activate llmao.\n'
else
  printf 'Add to your .zshrc after any existing command-not-found integration:\n%s\n' "$activation"
fi

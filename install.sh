#!/bin/sh
set -eu

activate=0
login_shell=${SHELL:-zsh}
shell_name=${login_shell##*/}
while [ "$#" -gt 0 ]; do
  case $1 in
    --activate) activate=1 ;;
    --shell)
      if [ "$#" -lt 2 ]; then
        printf 'Usage: %s [--activate] [--shell zsh|bash|fish]\n' "$0" >&2
        exit 2
      fi
      shift
      shell_name=$1
      ;;
    *)
      printf 'Usage: %s [--activate] [--shell zsh|bash|fish]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

case $shell_name in
  zsh)
    config=${ZDOTDIR:-"$HOME"}/.zshrc
    activation='source "${XDG_DATA_HOME:-$HOME/.local/share}/llmao/llmao.plugin.zsh"'
    ;;
  bash)
    config=$HOME/.bashrc
    login_config=$HOME/.bash_profile
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -f "$candidate" ]; then
        login_config=$candidate
        break
      fi
    done
    activation='source "${XDG_DATA_HOME:-$HOME/.local/share}/llmao/llmao.plugin.bash"'
    ;;
  fish)
    config=${XDG_CONFIG_HOME:-"$HOME/.config"}/fish/config.fish
    activation='if test -n "$XDG_DATA_HOME"; source "$XDG_DATA_HOME/llmao/llmao.plugin.fish"; else; source "$HOME/.local/share/llmao/llmao.plugin.fish"; end'
    ;;
  *)
    printf 'Choose a supported shell with --shell zsh, --shell bash, or --shell fish.\n' >&2
    exit 2
    ;;
esac

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/llmao
mkdir -p "$target_dir"
install -m 644 "$source_dir/llmao.plugin.zsh" "$source_dir/llmao.plugin.bash" \
  "$source_dir/llmao.plugin.fish" "$source_dir/llmao-bridge.zsh" "$source_dir/LICENSE" "$target_dir/"
install -m 755 "$source_dir/llmao" "$target_dir/"
printf 'Installed llmao in %s\n' "$target_dir"

activate_in() {
  mkdir -p "$(dirname -- "$1")"
  if ! grep -Fqx -- "$activation" "$1" 2>/dev/null; then
    printf '\n%s\n' "$activation" >> "$1"
  fi
}

if [ "$activate" -eq 1 ]; then
  activate_in "$config"
  if [ "$shell_name" = bash ]; then
    activate_in "$login_config"
  fi
  printf 'Open a new %s session to activate llmao.\n' "$shell_name"
else
  printf 'Add this to %s after any existing command-not-found integration:\n%s\n' "$config" "$activation"
  if [ "$shell_name" = bash ]; then
    printf 'For Bash login sessions, also add it to %s if it does not source .bashrc.\n' "$login_config"
  fi
fi

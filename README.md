# llmao

Type `fix the login bug` into zsh and llmao starts your coding agent when `fix` is unknown and the input looks like a simple request. A likely typo such as `gti status` gets a suggestion. zsh resolves recognized commands normally.

## Install

On macOS with zsh, install with Homebrew:

```sh
brew install mquan/tap/llmao
```

Add the printed `source` line to `.zshrc` after any existing command-not-found integration, then open a new zsh session. After the tap is registered, `brew install llmao` also works.

For a standalone install with automatic activation:

```zsh
(set -o pipefail; curl -fsSL https://github.com/mquan/llmao/releases/latest/download/install.sh | sh -s -- --activate)
```

The installer verifies the release archive checksum, then appends the source line once. Omit `--activate` to print the source line for manual setup. From a checkout or unpacked release, run `./install.sh` with the same options.

Rerun the installer to upgrade a script installation or use `brew upgrade llmao` for Homebrew.

To uninstall, remove the source line from `.zshrc` and start a new zsh session. For a script installation, remove `llmao.plugin.zsh` from `${XDG_DATA_HOME:-$HOME/.local/share}/llmao/`. For a Homebrew installation, run `brew uninstall llmao`.

## Configure

These settings can go in `.zshrc` and take effect for the next command miss.

| Setting | Default | Effect |
| --- | --- | --- |
| `LLMAO_AGENT` | `claude` | Select `claude` (Claude Code) or `codex`. |
| `LLMAO_USE_LAUNCH_HISTORY` | `0` | Set to `1` to pick an agent from the last ten recognized launches in zsh history. |
| `LLMAO_AUTO_LAUNCH` | `1` | Set to `0` to disable automatic launches. |
| `LLMAO_SUGGEST_TYPOS` | `1` | Set to `0` to disable typo suggestions. |

Install and configure your chosen agent separately. llmao launches it interactively in the current directory and passes the prompt as one argument. If the executable is missing, llmao defers to the previous missing-command handler or prints the standard interactive zsh diagnostic and returns 127.

If you only have Codex installed, set `LLMAO_AGENT=codex` for a fixed choice or enable launch history below to infer it from recent sessions.

### Choose an agent from recent launches

Set `LLMAO_USE_LAUNCH_HISTORY=1` in `.zshrc` and leave `LLMAO_AGENT` unset. llmao picks the most frequent agent from up to ten matching launches in the history visible to the current zsh session. The most recent matching launch breaks ties. Claude is the default when history has no matches. Only standalone lines matching these commands count.

```sh
claude
claude --dangerously-skip-permissions
codex
codex --yolo
```

Commands such as `codex review` and `codex exec` are outside the vote. Reviews started inside a bare `codex` session still count as Codex launches because zsh only sees how the session started.

The most recent matching launch for the winning agent determines whether its permission-skipping flag is reused. A bare launch selects that agent's normal settings. When a flag is reused, the startup message shows it.

## Input and shell behavior

- Type a simple request, for example `explain this error`, `why is the build slow`, or `can you add tests`. The classifier favors recognizable English phrasing and uses the live zsh command tables for typo suggestions. Ambiguous corrections fall through.
- A launch requires a foreground interactive terminal and agreement between the parsed arguments and the current history entry. History settings can affect whether that evidence is available. Spaces between words are normalized in the prompt.
- zsh parses and expands input before the hook runs. Shell syntax such as redirection, pipes, substitutions, globs, and quotes can already have taken effect. History is a conservative check and can itself reflect shell history expansion. Use a simple line of words for automatic launch. A bare question mark can trigger a zsh glob error before the hook is called.
- The hook runs only on command misses. It uses zsh's own command hash, and `rehash` can refresh it after installing new executables into an existing PATH directory.

## Development

```sh
zsh tests/classifier.zsh
python3 tests/integration.py
```

The first command tests multiple command dictionaries and reports classification latency and accuracy. The second uses a pseudo-terminal and local agent stubs to check terminal input, Ctrl-C, working directory, exit status, and fallbacks. Python is used for tests only.

To prepare a release, run `./scripts/package-release OWNER v0.1.0 OUTPUT_DIRECTORY`. Upload the versioned archive and generated `install.sh` to the matching release of `OWNER/llmao`. Use the generated formula in the tap's `Formula/` directory. The installer and formula both use the checksum of the exact archive.

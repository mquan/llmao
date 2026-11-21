# llmao

I keep typing plain English in my shell prompt all the time

```text
$ explain what this project is about
zsh: command not found: explain
```

With **llmao**, natural language text automatically opens my coding agent of choice. Supports all [major coding agents](#supported-agents) on **zsh**, **Bash 4+**, and **Fish 3.6+**.

<img src="llmao.gif" width="700" alt="Terminal demo showing llmao open Codex after the user types ‘explain this project’">

## Install

**Homebrew (macOS)**

```sh
brew install mquan/tap/llmao
```

Add the printed `source` line to your shell config.

**Standalone install with automatic activation**

```sh
curl -fsSL https://github.com/mquan/llmao/releases/latest/download/install.sh | sh -s -- --activate
```

Open a new shell after installation.

## How it works

- **The shell goes first.** llmao kicks in only when your interactive shell can’t find a command. Commands like `git status` run as usual.
- **Likely typos stay in the shell.** Type `gti status` and llmao suggests `git` if it’s the only match. If several commands match, you get the usual shell error.
- **Everything runs locally.** A line like `explain this project` can open your agent in the same terminal, using your current folder. Your shell still handles lines that use syntax like `|`, `>`, or `*.py`.
- **Coding agent selection.** llmao automatically opens your only installed supported agent. If you have several, it picks the one you used most often among your last 10 recognized agent launches. Ties go to the most recent launch.

## Configure

```sh
llmao config                     # Show saved preferences
llmao config agent codex         # Always use Codex
llmao config agent auto          # Use automatic selection
llmao config launch-history off  # Ignore recent launches in auto mode
```

Run `llmao --help` for all settings. Changes apply immediately.

Install and configure your agent separately. If llmao can’t select an installed agent, it falls back to your shell’s missing-command handler.

### Supported agents

| Coding agent | `llmao config agent` value |
| --- | --- |
| Amp | `amp` |
| Antigravity CLI | `agy` |
| Auggie CLI | `auggie` |
| Claude Code | `claude` |
| Cline CLI | `cline` |
| Codex | `codex` |
| Cursor CLI | `cursor-agent` |
| Devin CLI | `devin` |
| Gemini CLI | `gemini` |
| GitHub Copilot CLI | `copilot` |
| Goose | `goose` |
| Kiro CLI | `kiro-cli` |
| OpenCode | `opencode` |
| Pi | `pi` |
| Qwen Code | `qwen` |

Launch history counts recognized start commands in your shell history, such as `opencode` or `kiro-cli chat`. Fish merges repeated identical commands into a single history entry, so those repeats count once.

By default, launch history is used to choose an agent. Explicitly setting `llmao config launch-history on` can also reuse a supported approval-skipping flag from the chosen agent’s most recent launch.

## Development

```sh
zsh tests/classifier.zsh
python3 tests/integration.py
```

The first command tests classification. The second uses a pseudo-terminal and agent stubs to check launches, terminal input, Ctrl-C, and fallbacks. It also tests modern Bash and Fish when installed. Bash and Fish use macOS's built-in `/bin/zsh` for the shared classifier.

To prepare a release, run `./scripts/package-release OWNER v0.4.0 OUTPUT_DIRECTORY`. Upload the versioned archive and generated `install.sh` to the matching release of `OWNER/llmao`. Use the generated formula in the tap's `Formula/` directory. The installer and formula both use the checksum of the exact archive.

## License

[MIT](LICENSE)

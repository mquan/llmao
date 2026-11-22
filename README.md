# llmao

I keep typing plain English in my shell prompt by mistake all the time

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

Follow Homebrew’s post-install instructions to copy the `source` line for your shell into its startup file.

**Standalone install with automatic activation**

```sh
curl -fsSL https://github.com/mquan/llmao/releases/latest/download/install.sh | sh -s -- --activate
```

After either install, open a new terminal to load llmao.

## How it works

- **Shell commands run as usual.** When your interactive shell can’t find a command, llmao checks whether you typed a prompt.
- **llmao checks for command typos.** Type `gti status` and llmao suggests `git` if it’s the only match. If several commands match, you get the usual shell error.
- **llmao classifies shell input locally.** It passes the prompt to your chosen agent and starts it in your current directory. The agent and its configuration determine what it reads, sends, and stores. Your shell still handles syntax like `|`, `>`, or `*.py`.
- **Coding agent selection.** llmao automatically opens your only installed supported agent. If you have several, it picks the one you used most often among your last 10 recognized agent launches.

## How to use it

Type a plain-text prompt directly at your shell prompt and press Enter. Here are a few examples:

```text
$ explain what this project is about
$ how can we improve security?
$ let's work on this project
$ what is the next task?
```

llmao passes the prompt to your coding agent and launches it in the current directory.

### Send a prompt explicitly

Use `llmao ask` when the shell would interpret part of your prompt as a command or shell syntax. Put the prompt in quotes so the shell passes it as text.

```sh
llmao ask 'what do $PATH and !! mean?'
llmao ask --agent codex 'lets brainstorm ideas to improve security'
```

`llmao ask` uses your configured agent when set, or opens the only supported agent installed. With several agents installed, it lets you choose an agent for that request.

To keep a prompt out of shell history, run `llmao ask --input` or `llmao ask --agent codex --input`. After llmao shows the agent and current directory, type a single line and press Enter to send it. Press Ctrl-C to cancel. Depending on the agent, llmao may still pass the prompt as a process argument.

## Configure

```sh
llmao config                     # Show saved preferences
llmao config agent codex         # Always use Codex
llmao config agent auto          # Use automatic selection
llmao config launch-history off  # Ignore recent launches in auto mode
```

Run `llmao --help` for all settings. Changes apply immediately.

Install and configure your agent separately. If llmao can’t select an installed agent, it falls back to your shell's missing-command handler.

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

To prepare a release, run `./scripts/package-release OWNER v0.6.0 OUTPUT_DIRECTORY`. Upload the versioned archive and generated `install.sh` to the matching release of `OWNER/llmao`. Use the generated formula in the tap's `Formula/` directory. The installer and formula both use the checksum of the exact archive.

## License

[MIT](LICENSE)

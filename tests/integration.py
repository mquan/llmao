#!/usr/bin/env python3
import errno
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import termios
import time

PLUGIN = Path(__file__).resolve().parents[1] / "llmao.plugin.zsh"
ZSH = shutil.which("zsh")
STUB = """#!/bin/zsh -f
name=${0:t}
[[ -t 0 && -t 1 && -t 2 ]] || exit 91
argc=$#
if [[ $1 == (--yolo|--dangerously-skip-permissions) ]]; then
  print -r -- "FLAG=$1"
  shift
fi
if [[ $1 == -- ]]; then
  shift
  (( --argc ))
  print -r -- 'LITERAL=1'
fi
printf 'AGENT=%s ARGC=%d PROMPT=%s CWD=%s\\n' "$name" "$argc" "$1" "$PWD"
case $1 in
  'explain terminal input')
    if IFS= read -r input; then print -r -- "READ=$input"; else exit 92; fi
    ;;
  'explain interrupt handling')
    exec /bin/sleep 30
    ;;
esac
exit 42
"""


class Shell:
    def __init__(self, cwd, path, name="zsh", executable=ZSH, extra_env=None):
        self.name = name
        startup = {
            "zsh": ["-dfi"],
            "bash": ["--noprofile", "--norc", "-i"],
            "fish": ["--no-config", "-i"],
        }
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            env = {
                "HOME": str(cwd), "PATH": str(path), "TERM": "dumb",
                "LC_ALL": "en_US.UTF-8",
                "XDG_CONFIG_HOME": str(cwd / "config"),
                "XDG_DATA_HOME": str(cwd / "data"),
            }
            if name == "fish":
                env.update(TERM="xterm", fish_features="no-query-term,no-mark-prompt")
            env.update(extra_env or {})
            os.execve(executable, [executable, *startup[name]], env)
        self.pending = b""
        prompts = {
            "zsh": "unsetopt zle prompt_cr prompt_sp; PS1=$'\\x52EADY> '; PS2='MORE> '",
            "bash": "PS1=$'\\x52EADY> '; unset HISTFILE",
            "fish": "function fish_prompt; printf '%s%s> ' RE ADY; end",
        }
        self.send(prompts[name])
        self.read_until(b"READY> ")
        attributes = termios.tcgetattr(self.fd)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(self.fd, termios.TCSANOW, attributes)

    def send(self, line):
        os.write(self.fd, line.encode() + b"\n")

    def read_until(self, marker):
        deadline = time.monotonic() + 5
        while marker not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.fd], [], [], remaining)[0]:
                raise AssertionError(f"Timed out waiting for {marker!r}: {self.pending!r}")
            try:
                data = os.read(self.fd, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            if not data:
                raise AssertionError(f"Shell exited waiting for {marker!r}: {self.pending!r}")
            self.pending += data
        output, self.pending = self.pending.split(marker, 1)
        return output.decode(errors="replace").replace("\r", "")

    def run(self, line):
        self.send(line)
        return self.read_until(b"READY> ")

    def status(self, expected):
        last_status = "$status" if self.name == "fish" else "$?"
        output = self.run(f"printf 'STATUS=%s\\n' {last_status}")
        assert f"STATUS={expected}\n" in output, output

    def close(self):
        try:
            os.killpg(self.pid, signal.SIGHUP)
        except ProcessLookupError:
            pass
        os.close(self.fd)
        os.waitpid(self.pid, 0)


def make_command(path, name, body):
    file = path / name
    file.write_text(body)
    file.chmod(0o755)


def check_config(shell):
    def configure(setting, value):
        output = shell.run(f"PATH=/usr/bin:/bin llmao config {setting} {value}")
        assert f"{setting} {value}\n" in output, output

    configure("agent", "codex")
    output = shell.run("explain this project")
    assert "Starting Codex..." in output and "AGENT=codex" in output, output
    configure("auto-launch", "off")
    output = shell.run("explain this project")
    assert "Starting " not in output, output
    configure("suggest-typos", "off")
    output = shell.run("gti status")
    assert "Did you mean" not in output, output
    configure("auto-launch", "on")
    configure("launch-history", "off")
    configure("agent", "auto")
    output = shell.run("explain this project")
    assert "Starting " not in output, output
    output = shell.run("llmao config")
    assert "agent auto\nlaunch-history off\nauto-launch on\nsuggest-typos off\n" in output, output


def check_agent_support(shell, cwd):
    prompt = "--unknown-option café with spaces"
    agents = {
        "opencode": ("OpenCode", [f"--prompt={prompt}"]),
        "devin": ("Devin CLI", ["--", prompt]),
        "copilot": ("GitHub Copilot CLI", [f"--interactive={prompt}"]),
        "agy": ("Antigravity CLI", [f"--prompt-interactive={prompt}"]),
        "cursor-agent": ("Cursor CLI", ["agent", "--", prompt]),
        "gemini": ("Gemini CLI", [f"--prompt-interactive={prompt}"]),
        "kiro-cli": ("Kiro CLI", ["chat", "--", prompt]),
        "qwen": ("Qwen Code", [f"--prompt-interactive={prompt}"]),
        "goose": ("Goose", ["run", "--interactive", f"--text={prompt}"]),
        "pi": ("Pi", ["--", prompt]),
        "cline": ("Cline CLI", ["-i", "--", prompt]),
        "amp": ("Amp", []),
        "auggie": ("Auggie CLI", ["--", prompt]),
    }
    stub = """#!/bin/zsh -f
[[ -t 1 && -t 2 ]] || exit 91
print -r -- "AGENT=${0:t} ARGC=$# CWD=$PWD"
if [[ ${0:t} == amp && ! -t 0 ]]; then
  IFS= read -r prompt || exit 92
  print -r -- "STDIN=$prompt"
else
  [[ -t 0 ]] || exit 91
  for arg in "$@"; do print -r -- "ARG=$arg"; done
fi
exit 42
"""
    commands = cwd / f"agents-{shell.name}"
    commands.mkdir()
    make_command(commands, "opencode", stub)
    path = shlex.quote(str(commands))
    shell.run(f"set -gx PATH {path}" if shell.name == "fish" else f"PATH={path}")
    assert "Starting OpenCode..." in shell.run("explain this project")

    for name, (label, args) in agents.items():
        make_command(commands, name, stub)
        assert f"agent {name}\n" in shell.run(f"PATH=/usr/bin:/bin llmao config agent {name}")
        output = shell.run(prompt)
        assert f"Starting {label}..." in output, output
        assert f"AGENT={name} ARGC={len(args)} CWD={cwd}\n" in output, output
        assert re.findall(r"^ARG=(.*)$", output, re.M) == args, output
        if name == "amp":
            assert f"STDIN={prompt}\n" in output, output
        shell.status(127 if shell.name == "fish" else 42)

    shell.run("PATH=/usr/bin:/bin llmao config agent auto")
    assert "Starting " not in shell.run("explain this project")
    shell.run("PATH=/usr/bin:/bin llmao config launch-history on")
    for launch in ("kiro-cli", "kiro-cli chat", "devin", "agy", "opencode --help"):
        shell.run(launch)
    assert "Starting Kiro CLI..." in shell.run("explain this project")
    (commands / "agent").symlink_to("cursor-agent")
    for launch in ("agent", "cursor-agent"):
        shell.run(launch)
    assert "Starting Cursor CLI..." in shell.run("explain this project")


def check_other_shells(cwd, commands):
    for name, required in (("bash", (4, 0)), ("fish", (3, 6))):
        executable = os.environ.get(f"LLMAO_TEST_{name.upper()}") or shutil.which(name)
        if not executable:
            print(f"Skipping {name} PTY checks (shell unavailable)")
            continue
        extra_env = {"XDG_CONFIG_HOME": str(cwd / f"config-{name}")}
        if os.environ.get("LLMAO_TEST_DYLD"):
            extra_env["DYLD_LIBRARY_PATH"] = os.environ["LLMAO_TEST_DYLD"]
        version = subprocess.check_output(
            [executable, "--version"], text=True, env={**os.environ, **extra_env}
        )
        found = re.search(r"(\d+)\.(\d+)", version)
        if tuple(map(int, found.groups())) < required:
            print(f"Skipping {name} PTY checks (version too old)")
            continue
        shell = Shell(cwd, commands, name, executable, extra_env)
        try:
            source = f"source {shlex.quote(str(PLUGIN.with_suffix('.' + name)))}"
            agent_status = 42 if name == "bash" else 127
            previous = (
                "command_not_found_handle() { printf 'PREVIOUS=%s\\n' \"$1\"; return 44; }"
                if name == "bash"
                else "function fish_command_not_found; printf 'PREVIOUS=%s\\n' $argv[1]; return 44; end"
            )
            shell.run(previous)
            if name == "bash":
                shell.run("PROMPT_COMMAND=('printf PC1' 'printf PC2'); HISTCONTROL=ignorespace")
            output = shell.run(source)
            if name == "bash":
                assert "PC1PC2" in output, output
            shell.run(source)
            output = shell.run("git status")
            assert "GIT=status" in output and "Starting " not in output, output
            output = shell.run("gti status")
            assert "Did you mean 'git'?" in output, output
            shell.status(127)
            output = shell.run("deploy-y")
            assert "PREVIOUS=deploy-y" in output and "Starting " not in output, output
            shell.status(44 if name == "bash" else 127)
            output = shell.run("explain this project")
            assert "PREVIOUS=explain" in output and "Starting " not in output, output
            shell.run("LLMAO_AGENT=claude" if name == "bash" else "set -g LLMAO_AGENT claude")
            for line in ("explain what this project is about", "解释一下这个项目", "foobar", "foo --version"):
                output = shell.run(line)
                assert "Starting Claude Code..." in output and "LITERAL=1" in output, output
                assert f"AGENT=claude ARGC=1 PROMPT={line}" in output, output
                shell.status(agent_status)
            for line in (
                "fix the login bug; true",
                "fix the login bug >/dev/tty",
                "why does $(printf login) fail",
            ):
                output = shell.run(line)
                assert "Starting " not in output and "PREVIOUS=" in output, (line, output)
            if name == "bash":
                shell.run("fix the login bug")
                output = shell.run(' fix the "login" bug')
                assert "Starting " not in output and "PREVIOUS=fix" in output, output

            shell.run("unset LLMAO_AGENT" if name == "bash" else "set -e LLMAO_AGENT")
            shell.run("codex --yolo")
            shell.run("LLMAO_USE_LAUNCH_HISTORY=1" if name == "bash" else "set -g LLMAO_USE_LAUNCH_HISTORY 1")
            output = shell.run("fix the login bug")
            assert "Starting Codex (--yolo)" in output and "FLAG=--yolo" in output, output
            shell.status(agent_status)
            shell.send("explain terminal input")
            assert "AGENT=codex" in shell.read_until(f"CWD={cwd}\r\n".encode())
            shell.send("readable")
            assert "READ=readable" in shell.read_until(b"READY> ")
            shell.status(agent_status)
            shell.send("explain interrupt handling")
            shell.read_until(f"CWD={cwd}\r\n".encode())
            os.write(shell.fd, b"\x03")
            shell.read_until(b"READY> ")
            shell.status(130 if name == "bash" else 127)
            check_config(shell)
            check_agent_support(shell, cwd)
        finally:
            shell.close()
        print(f"{name} PTY integration passed")


def main():
    with tempfile.TemporaryDirectory(prefix="llmao-") as tmp:
        cwd = Path(tmp).resolve()
        commands = cwd / "original-bin"
        commands.mkdir()
        shell = Shell(cwd, commands)
        try:
            def missing(line, prefix):
                output = shell.run(line)
                assert prefix in output and "Starting " not in output, (line, output)
                shell.status(127)

            for name in ("claude", "codex"):
                make_command(commands, name, STUB)
            for name in ("deploy-x", "deploy-z"):
                make_command(commands, name, "#!/bin/zsh -f\nexit 0\n")
            make_command(commands, "git", "#!/bin/zsh -f\nprint -r -- GIT=$*\n")
            source = f"source {shlex.quote(str(PLUGIN))}"
            shell.run(source)
            shell.run(source)
            output = shell.run("git status")
            assert "GIT=status" in output, output
            shell.status(0)
            missing("gti status", "Did you mean 'git'?")
            missing("gti 'path with spaces' --help", "Did you mean 'git'?")
            missing("deploy-y", "zsh: command not found: deploy-y")
            missing("./gti status", "no such file or directory: ./gti")
            missing("explain this project", "zsh: command not found: explain")
            shell.run("LLMAO_AGENT=claude")
            for line, prompt in (
                ("foobar", "foobar"),
                ("foo --version", "foo --version"),
                ("--missing-option", "--missing-option"),
                ("explique cette erreur", "explique cette erreur"),
                ("解释一下这个项目", "解释一下这个项目"),
                ('unknown-llmao "login bug"', "unknown-llmao login bug"),
            ):
                output = shell.run(line)
                assert "Starting Claude Code..." in output and "LITERAL=1" in output, (line, output)
                assert f"ARGC=1 PROMPT={prompt} CWD={cwd}" in output, (line, output)
                shell.status(42)
            for line in (
                "fix the \\login bug",
                "fix the login bug; true",
                "fix the login bug && true",
                "why does $(print cache) fail",
                "why does `print cache` fail",
                "thing=cache why does $thing fail",
                "thing=cache fix the login bug",
                "command fix the login bug",
                "(fix the login bug)",
                "fix the login bug | /bin/cat",
                "fix the login bug >/dev/tty",
                "fix the login bug </dev/tty",
            ):
                output = shell.run(line)
                assert "command not found:" in output and "Starting " not in output, (line, output)
            (cwd / "llmao-glob-target").touch()
            output = shell.run("fix the llmao-glob-* bug")
            assert "command not found: fix" in output and "Starting " not in output, output
            assert "no matches found:" in shell.run("why is this failing?")
            shell.run("alias explain='print -r -- ALIAS'")
            assert "ALIAS this error" in shell.run("explain this error")
            assert "Did you mean 'explain'?" in shell.run("expalin this error")
            shell.run("unalias explain; function explain { print -r -- FUNCTION \"$@\"; }")
            assert "FUNCTION this error" in shell.run("explain this error")
            assert "Did you mean 'explain'?" in shell.run("expalin this error")
            shell.run("unfunction explain")
            missing("pritnf hello", "Did you mean 'printf'?")

            output = shell.run("fix the login bug")
            assert "Starting Claude Code" in output, output
            assert f"AGENT=claude ARGC=1 PROMPT=fix the login bug CWD={cwd}\n" in output, output
            shell.status(42)
            shell.run("LLMAO_AGENT=codex")
            shell.send("explain terminal input")
            output = shell.read_until(f"CWD={cwd}\r\n".encode())
            assert "Starting Codex" in output and "AGENT=codex ARGC=1" in output, output
            shell.send("readable")
            assert "READ=readable" in shell.read_until(b"READY> ")
            shell.status(42)
            shell.send("explain interrupt handling")
            shell.read_until(f"CWD={cwd}\r\n".encode())
            os.write(shell.fd, b"\x03")
            shell.read_until(b"READY> ")
            shell.status(130)

            shell.run("LLMAO_AUTO_LAUNCH=0")
            missing("fix the login bug", "command not found: fix")
            shell.run("LLMAO_SUGGEST_TYPOS=0")
            missing("gti status", "zsh: command not found: gti")
            shell.run("unset LLMAO_AUTO_LAUNCH LLMAO_SUGGEST_TYPOS")
            shell.run("unset LLMAO_AGENT")
            shell.run("codex --yolo")
            missing("fix the login bug", "zsh: command not found: fix")
            shell.run("LLMAO_USE_LAUNCH_HISTORY=1")
            output = shell.run("fix the login bug")
            assert "Starting Codex (--yolo)" in output and "FLAG=--yolo" in output, output
            assert "ARGC=2 PROMPT=fix the login bug" in output, output
            shell.status(42)
            shell.run("claude --dangerously-skip-permissions")
            shell.run("codex --yolo unexpected")
            shell.run("codex --yolo; true")
            output = shell.run("fix the login bug")
            assert "Starting Claude Code (--dangerously-skip-permissions)" in output, output
            assert "FLAG=--dangerously-skip-permissions" in output, output
            shell.run("codex")
            output = shell.run("fix the login bug")
            assert "Starting Codex..." in output and "FLAG=" not in output, output
            shell.run("codex --yolo")
            shell.run("LLMAO_AGENT=claude")
            output = shell.run("fix the login bug")
            assert "Starting Claude Code..." in output and "FLAG=" not in output, output

            other_path = cwd / "new-bin"
            other_path.mkdir()
            make_command(other_path, "kubectl", "#!/bin/zsh -f\nexit 94\n")
            shell.run(f"PATH={shlex.quote(str(other_path))}")
            missing("kubect get pods", "Did you mean 'kubectl'?")
            missing("gti status", "zsh: command not found: gti")
            make_command(other_path, "codex", STUB)
            missing("fix the login bug", "zsh: command not found: fix")
            shell.run("unset LLMAO_AGENT")
            output = shell.run("fix the login bug")
            assert "Starting Codex (--yolo)" in output and "FLAG=--yolo" in output, output
            shell.run("unset LLMAO_USE_LAUNCH_HISTORY")
            output = shell.run("fix the login bug")
            assert "Starting Codex..." in output and "FLAG=" not in output, output
            shell.status(42)
        finally:
            shell.close()

        shell = Shell(cwd, commands)
        try:
            shell.run('function command_not_found_handler { print -r -- "PREVIOUS:$#:${2}"; return 44; }')
            shell.run(source)
            shell.run(source)
            output = shell.run("LLMAO_AUTO_LAUNCH=0 xyzzy 'kept as one argument'")
            assert "PREVIOUS:2:kept as one argument" in output, output
            shell.status(44)
            shell.run("LLMAO_AGENT=unsupported")
            output = shell.run("fix the login bug")
            assert "PREVIOUS:4:the" in output and "Starting " not in output, output
            shell.status(44)
        finally:
            shell.close()

        shell = Shell(cwd, commands)
        try:
            shell.run(source)
            shell.run("LLMAO_USE_LAUNCH_HISTORY=1; HISTSIZE=512")
            missing("fix the login bug", "zsh: command not found: fix")

            # A tie follows the most recent eligible launch.
            shell.run("claude")
            shell.run("codex --yolo")
            output = shell.run("fix the login bug")
            assert "Starting Codex (--yolo)" in output and "FLAG=--yolo" in output, output
            shell.run("codex")
            shell.run("claude")
            output = shell.run("fix the login bug")
            assert "Starting Claude Code..." in output and "FLAG=" not in output, output
            # Older and more recent Codex launches would win an all-history
            # tally, but the last ten eligible launches are six Claude to four.
            for _ in range(6):
                shell.run("codex")
            for _ in range(5):
                shell.run("claude")
            shell.run("claude --dangerously-skip-permissions")
            for _ in range(4):
                shell.run("codex --yolo")
            for _ in range(6):
                shell.run("codex review --uncommitted")
                shell.run("codex --yolo --yolo")
            for index in range(105):
                shell.run(f": unrelated-{index}")
            output = shell.run("fix the login bug")
            assert "Starting Claude Code (--dangerously-skip-permissions)" in output, output
            assert "FLAG=--dangerously-skip-permissions" in output, output
            shell.status(42)

            # A newer bare launch clears the flag of the winning agent.
            shell.run("claude")
            output = shell.run("fix the login bug")
            assert "Starting Claude Code..." in output and "FLAG=" not in output, output
            check_config(shell)
            check_agent_support(shell, cwd)
        finally:
            shell.close()
        check_other_shells(cwd, commands)
    print("PTY integration passed (terminal, signals, status, discovery, syntax, fallback, launch history)")


if __name__ == "__main__":
    main()

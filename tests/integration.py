#!/usr/bin/env python3
import errno
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import tempfile
import termios
import time

PLUGIN = Path(__file__).resolve().parents[1] / "llmao.plugin.zsh"
ZSH = shutil.which("zsh")
STUB = """#!/bin/zsh -f
name=${0:t}
[[ -t 0 && -t 1 && -t 2 ]] || exit 91
argc=$#
if [[ $1 == --* ]]; then
  print -r -- "FLAG=$1"
  shift
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
    def __init__(self, cwd, path):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execve(ZSH, [ZSH, "-dfi"], {
                "HOME": str(cwd), "PATH": str(path), "TERM": "dumb",
            })
        self.pending = b""
        self.send("unsetopt zle prompt_cr prompt_sp; PS1=$'\\x52EADY> '; PS2='MORE> '")
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
        output = self.run("print -r -- STATUS=$?")
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
            make_command(commands, "git", "#!/bin/zsh -f\nprint -r -- GIT=$*\n")
            source = f"source {shlex.quote(str(PLUGIN))}"
            shell.run(source)
            shell.run(source)
            output = shell.run("git status")
            assert "GIT=status" in output, output
            shell.status(0)
            missing("gti status", "Did you mean 'git'?")
            missing("gti 'path with spaces' --help", "Did you mean 'git'?")
            missing("foobar", "zsh: command not found: foobar")
            missing("foo --version", "zsh: command not found: foo")
            missing("./gti status", "no such file or directory: ./gti")
            for line in (
                "fix the \"login bug\"",
                "fix 'the' login bug",
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
            output = shell.run("fix the login bug")
            assert "Starting Claude Code..." in output and "FLAG=" not in output, output
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
            missing("fix the login bug", "zsh: command not found: fix")
        finally:
            shell.close()

        shell = Shell(cwd, commands)
        try:
            shell.run('function command_not_found_handler { print -r -- "PREVIOUS:$#:${2}"; return 44; }')
            shell.run(source)
            shell.run(source)
            output = shell.run("xyzzy 'kept as one argument'")
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
            output = shell.run("fix the login bug")
            assert "Starting Claude Code..." in output and "FLAG=" not in output, output

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
        finally:
            shell.close()
    print("PTY integration passed (terminal, signals, status, discovery, syntax, fallback, launch history)")


if __name__ == "__main__":
    main()

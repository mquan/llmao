# Source from interactive Fish 3.6+ after any other missing-command integration.
status is-interactive; or return
set -q _llmao_fish_dir; and return
test -x /bin/zsh; or return
set -g _llmao_fish_dir (path dirname -- (path resolve -- (status filename)))
test -r "$_llmao_fish_dir/llmao-bridge.zsh"; or return

if test -x "$_llmao_fish_dir/llmao"; and not type -q llmao
    function llmao
        command "$_llmao_fish_dir/llmao" $argv
    end
end

if functions -q fish_command_not_found
    functions -c fish_command_not_found _llmao_previous_fish_handler
end

function fish_command_not_found
    set -l raw ''
    set -l use_history ''
    set -l LLMAO_AGENT "$LLMAO_AGENT"
    set -l LLMAO_USE_LAUNCH_HISTORY "$LLMAO_USE_LAUNCH_HISTORY"
    set -l LLMAO_AUTO_LAUNCH "$LLMAO_AUTO_LAUNCH"
    set -l LLMAO_SUGGEST_TYPOS "$LLMAO_SUGGEST_TYPOS"
    set -l config_dir "$HOME/.config/llmao"
    if test -n "$XDG_CONFIG_HOME"
        set config_dir "$XDG_CONFIG_HOME/llmao"
    end
    for setting in LLMAO_AGENT LLMAO_USE_LAUNCH_HISTORY LLMAO_AUTO_LAUNCH LLMAO_SUGGEST_TYPOS
        if test -r "$config_dir/$setting"
            read "$setting" < "$config_dir/$setting"
        end
    end
    # Fish invokes this handler with stdout redirected to stderr.
    if test "$LLMAO_AUTO_LAUNCH" != 0; and test -t 0; and test -t 2
        if not status is-command-substitution
            set raw (status current-commandline 2>/dev/null | string collect)
            set -q raw[1]; or set raw ''
        end
        if test -n "$raw"; and test -z "$LLMAO_AGENT"; and test "$LLMAO_USE_LAUNCH_HISTORY" = 1
            set use_history 1
        end
    end

    set -l decision (begin
        if test "$use_history" = 1
            builtin history search --null
        end
    end | /bin/zsh -df "$_llmao_fish_dir/llmao-bridge.zsh" fish "$raw" \
        "$LLMAO_AGENT" "$use_history" (count $argv) $argv (builtin --names) (functions --names))
    set -l fields (string split ' ' -- "$decision")
    switch "$fields[1]"
        case typo
            if test "$LLMAO_SUGGEST_TYPOS" != 0
                printf "Command '%s' not found. Did you mean '%s'?\n" "$argv[1]" "$fields[2]" >&2
                return 127
            end
        case prompt
            set -l executable (command -s -- "$fields[2]")
            if set -q executable[1]
                set -l label
                switch "$fields[2]"
                    case claude
                        set label 'Claude Code'
                    case codex
                        set label Codex
                end
                if set -q fields[3]
                    set label "$label ($fields[3])"
                end
                printf '✦ Starting %s...\n' "$label" >&2
                command "$executable" $fields[3] -- (string join ' ' -- $argv)
                return $status
            end
    end

    if functions -q _llmao_previous_fish_handler
        _llmao_previous_fish_handler $argv
    else
        __fish_default_command_not_found_handler $argv
    end
end

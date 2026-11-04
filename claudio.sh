#!/usr/bin/env bash
# Linux launcher: runs Claude Code in the claudio container from the current
# directory. Podman runs natively, so unlike claudio.ps1 there is no machine.
set -euo pipefail

# Resolve the repository directory through the ~/.local/bin symlink
ScriptDir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)

ConfigFile="$HOME/claudio.ini"
UpdateStampFile="$HOME/.claudio-update-check"

warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

if ! command -v podman >/dev/null 2>&1; then
    die "podman not found. Install it with your package manager (e.g. 'sudo dnf install podman' or 'sudo apt install podman')."
fi

if [ ! -f "$ConfigFile" ]; then
    cat > "$ConfigFile" <<'EOF'
; claudio configuration
; host directory holding Claude's settings, credentials and .env
home=~/claudehome
; check for a newer Claude Code once the image is this many days old (0 = never)
update_check_days=7
; extra options for 'podman run', placed before the image name; quote values
; containing spaces. E.g. to reach a service listening on the host's
; 127.0.0.1:9876 at the container's 127.0.0.1:9876 (and no other host port):
;podman_args=--network pasta:-T,9876
EOF
    echo "Created default config at $ConfigFile"
fi

# Same format as on Windows: key=value lines, ; and # start comments
declare -A config=()
iniLine='^([^=;#[]+)=(.*)$'
while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [[ $line =~ $iniLine ]]; then
        key=$(echo "${BASH_REMATCH[1]}" | xargs)
        value=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        config[$key]=$value
    fi
done < "$ConfigFile"

ClaudeHome=${config[home]:-~/claudehome}
ClaudeHome=${ClaudeHome/#\~/$HOME}
UpdateCheckDays=${config[update_check_days]:-7}
[[ $UpdateCheckDays =~ ^[0-9]+$ ]] || UpdateCheckDays=7

# Split podman_args like a shell would (honouring quotes) without evaluating
# it: xargs never expands variables or runs commands
PodmanExtraArgs=()
if [ -n "${config[podman_args]:-}" ]; then
    parsed=$(xargs printf '%s\n' <<< "${config[podman_args]}" 2>/dev/null) ||
        die "Cannot parse podman_args in $ConfigFile (unbalanced quotes?)."
    mapfile -t PodmanExtraArgs <<< "$parsed"
fi

confirm() {
    local answer
    # Never prompt when not interactive: treat it as a no
    [ -t 0 ] || return 1
    read -r -p "$1 (y/N) " answer
    [[ $answer =~ ^[Yy]$ ]]
}

if ! podman image exists claudio 2>/dev/null; then
    echo "The 'claudio' image is not present."
    if confirm "Build it now?"; then
        podman build -t claudio "$ScriptDir" || die "Image build failed."
    else
        echo ""
        echo "Build it first:"
        echo ""
        echo "  cd $ScriptDir"
        echo "  podman build -t claudio ."
        echo ""
        exit 1
    fi
fi

# Once the image (or the last check) is older than update_check_days, compare
# the Claude Code version inside the image with the latest release
lastUpdateCheck() {
    local last stamp
    last=$(podman image inspect claudio --format '{{.Created.Unix}}')
    if [ -f "$UpdateStampFile" ]; then
        stamp=$(head -n 1 "$UpdateStampFile" | tr -d '\r')
        if [[ $stamp =~ ^[0-9]+$ ]] && [ "$stamp" -gt "$last" ]; then
            last=$stamp
        fi
    fi
    echo "$last"
}

if [ "$UpdateCheckDays" -gt 0 ] && [ -t 0 ] &&
    [ "$(lastUpdateCheck)" -lt $(( $(date +%s) - UpdateCheckDays * 86400 )) ]; then
    echo "Checking for Claude Code updates..."
    latest=$(curl -fsSL --max-time 5 https://downloads.claude.ai/claude-code-releases/latest 2>/dev/null | tr -d '[:space:]' || true)
    [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || latest=
    installed=$(podman run --rm claudio --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)

    if [ -n "$latest" ] && [ -n "$installed" ] && [ "$installed" != "$latest" ] &&
        [ "$(printf '%s\n' "$installed" "$latest" | sort -V | head -n 1)" = "$installed" ]; then
        echo "The 'claudio' image has Claude Code $installed, $latest is available."
        if confirm "Rebuild the image now?"; then
            podman build -t claudio --build-arg "CLAUDE_CODE_VERSION=$latest" "$ScriptDir" ||
                warn "Image rebuild failed, continuing with Claude Code $installed."
        fi
    fi

    # Remember the check (also when declined or offline) so it runs again
    # only after another update_check_days
    date +%s > "$UpdateStampFile"
fi

# Map the host directory to a unique path under /app, so each project gets
# its own Claude memory (e.g. /home/me/foo -> /app/home/me/foo). Symlinks are
# resolved, so the same directory always gets the same container path however
# it was reached (e.g. /home -> /var/home on Fedora Atomic): Claude keys its
# sessions and memory by that path
currentDir=$(pwd -P)
containerDir="/app${currentDir%/}"

# podman fails on missing bind-mount sources and env files: create them
# on first run
mkdir -p "$ClaudeHome/claude"
[ -f "$ClaudeHome/claude.json" ] || echo '{}' > "$ClaudeHome/claude.json"
if [ ! -f "$ClaudeHome/.env" ]; then
    cat > "$ClaudeHome/.env" <<'EOF'
# Environment for the claudio container, one VAR=value per line.
# Leave the credentials unset to log in with /login inside Claude (the login
# is kept in claude/), or set one of:
#CLAUDE_CODE_OAUTH_TOKEN=
#ANTHROPIC_API_KEY=
EOF
    echo "Created $ClaudeHome/.env: edit it to set credentials or other variables."
fi

podmanArgs=(run --rm -i)
# Only allocate a TTY when attached to a terminal, so output can be piped
if [ -t 0 ] && [ -t 1 ]; then
    podmanArgs+=(-t)
fi
# Rootless podman: run the container's claude user (uid 1000) as the host
# user, so files it writes in the project and Claude home are owned by you
if [ "$(id -u)" -ne 0 ]; then
    podmanArgs+=(--userns=keep-id:uid=1000,gid=1000)
fi
podmanArgs+=(
    # SELinux would deny access to the bind mounts; relabelling them with :z
    # would permanently change the labels of your files instead
    --security-opt label=disable
    -v "${currentDir}:${containerDir}"
    -w "$containerDir"
    -v "${ClaudeHome}/claude/:/home/claude/.claude/"
    -v "${ClaudeHome}/claude.json:/home/claude/.claude.json"
    --env-file "${ClaudeHome}/.env"
    # User options from podman_args: before the image, since anything after
    # it goes to claude
    "${PodmanExtraArgs[@]}"
    claudio
)

# Forward any extra arguments to claude; exec propagates its exit code
exec podman "${podmanArgs[@]}" "$@"

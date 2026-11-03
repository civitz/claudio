#!/usr/bin/env bash
# Linux installer: links ~/.local/bin/claudio to claudio.sh in this repository
# and builds the container image.
set -euo pipefail

ScriptDir=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
InstallDir="$HOME/.local/bin"

confirm() {
    local answer
    read -r -p "$1 (y/N) " answer
    [[ $answer =~ ^[Yy]$ ]]
}

pathAdded=false
case ":$PATH:" in
    *":$InstallDir:"* | *":$InstallDir/:"*) ;;
    *)
        case "$(basename "${SHELL:-}")" in
            bash) rcFile="$HOME/.bashrc" ;;
            zsh) rcFile="$HOME/.zshrc" ;;
            *) rcFile="$HOME/.profile" ;;
        esac
        echo "'$InstallDir' is not in your PATH."
        if ! confirm "Add it to $rcFile now?"; then
            echo "Aborted. Add '$InstallDir' to your PATH and re-run the installer." >&2
            exit 1
        fi
        # Single quotes: $HOME and $PATH are expanded by the shell at startup
        printf '\n# Added by the claudio installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rcFile"
        echo "Added '$InstallDir' to your PATH in $rcFile."
        pathAdded=true
        ;;
esac

mkdir -p "$InstallDir"

# Link instead of copying, so claudio.sh stays in (and updates with) the repo.
# The executable bit can be lost when the repo is checked out from Windows.
chmod +x "$ScriptDir/claudio.sh"
ln -sfn "$ScriptDir/claudio.sh" "$InstallDir/claudio"
echo "Installed $InstallDir/claudio -> $ScriptDir/claudio.sh"

if ! command -v podman >/dev/null 2>&1; then
    echo "WARNING: podman not found. Install it with your package manager, then build the image:" >&2
    echo "  podman build -t claudio $ScriptDir" >&2
elif podman image exists claudio 2>/dev/null; then
    echo "The 'claudio' image is already present."
elif confirm "The 'claudio' image is not present. Build it now?"; then
    podman build -t claudio "$ScriptDir" || { echo "ERROR: Image build failed." >&2; exit 1; }
else
    echo "Skipped. claudio will offer to build the image on first run."
fi

echo ""
echo "Installation complete."
if $pathAdded; then
    echo "Restart your terminal (or open a new one) for the PATH change to take effect."
fi

# claudio

Run [Claude Code](https://claude.ai/code) inside a Podman container from any project directory on Windows.

## Prerequisites

- [Podman Desktop](https://podman-desktop.io/) installed
- PowerShell 5 or later
- `%USERPROFILE%\.local\bin` directory exists on disk

## Build the image

From the repository root, build the `claudio` container image once:

```powershell
podman build -t claudio .
```

## Install

Open a **PowerShell** terminal, navigate to the repository root, and run:

```powershell
.\install.ps1
```

The installer will:

1. Check whether `%USERPROFILE%\.local\bin` is on your PATH — if not, it will offer to add it.
2. Write a configured `claudio.bat` to `%USERPROFILE%\.local\bin`, pointing back to `claudio.ps1` in the repository.

`claudio.ps1` is not copied — it stays in the repository directory.

If the PATH was updated, **restart your terminal** before continuing.

## Usage

Navigate to any project directory and run:

```cmd
claudio
```

This starts the Podman machine (creating it on first run if needed) and launches an interactive Claude Code session inside the container.

The current directory is mounted under `/app`, mirroring its host path (e.g. `C:\work\foo` becomes `/app/c/work/foo`), and Claude is started from there. This way each project keeps its own Claude memory and settings.

Any arguments are forwarded to `claude`:

```cmd
claudio --continue
claudio -p "explain this repo"
```

## Configuration

On first run `claudio` creates `%USERPROFILE%\claudio.ini`:

| Key | Default | Meaning |
| --- | --- | --- |
| `home` | `~/claudehome` | Host directory holding Claude's settings and credentials (see below) |
| `mountpoints` | your user folder and every drive | Comma-separated `host:machine` paths shared with the Podman machine |
| `machine` | `podman-machine-default` | Podman machine to use |
| `update_check_days` | `7` | See [Updates](#updates) |

### Claude home

The `home` directory is mounted into every container, so settings, login and history survive across sessions. `claudio` creates what is missing on first run:

- `.claude\` and `claude.json`: Claude Code's settings and state
- `.env`: environment variables for the container, one `VAR=value` per line

To authenticate, either run `/login` inside Claude (the login is kept in `.claude\`), or put one of these in `.env`:

```
CLAUDE_CODE_OAUTH_TOKEN=<token from `claude setup-token`>
ANTHROPIC_API_KEY=<API key>
```

### Mountpoints

`mountpoints` is only applied when `claudio` creates the Podman machine: editing it afterwards has no effect, and `claudio` warns when it no longer matches the machine. To apply new mountpoints, remove the machine and let `claudio` create it again:

```powershell
podman machine rm podman-machine-default
claudio
```

## Updates

Claude Code's auto-updater is disabled inside the container, since updates would be lost when it exits. Instead, once the image is older than `update_check_days` (default 7, set in `claudio.ini`; `0` disables the check), `claudio` compares the Claude Code version in the image with the latest release and offers to rebuild the image. After a check it waits another `update_check_days` before checking again.

To rebuild manually with a specific version:

```powershell
podman build -t claudio --build-arg CLAUDE_CODE_VERSION=<version> .
```

## Uninstall

Delete the installed launcher (`claudio.ps1` stays in the repository):

```powershell
Remove-Item "$env:USERPROFILE\.local\bin\claudio.bat"
```

To also remove the configuration and the state files `claudio` keeps next to it:

```powershell
Remove-Item "$env:USERPROFILE\claudio.ini", "$env:USERPROFILE\.claudio-*"
```

The Claude home (`home` in `claudio.ini`, by default `%USERPROFILE%\claudehome`) holds your Claude settings, login and history: delete it only if you no longer need them. The image can be removed with `podman rmi claudio`.

To also remove the directory from your PATH, open **System Properties → Environment Variables** and edit the `Path` user variable.

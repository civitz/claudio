# claudio

Run [Claude Code](https://claude.ai/code) inside a Podman container from any project directory, on Windows or Linux.

## Prerequisites

**Windows**

- [Podman Desktop](https://podman-desktop.io/) installed
- PowerShell 5 or later
- `%USERPROFILE%\.local\bin` directory exists on disk

**Linux**

- [Podman](https://podman.io/docs/installation) 4.3 or later (e.g. `sudo dnf install podman` or `sudo apt install podman`)
- bash and curl

## Install

The installer puts a `claudio` launcher in `~/.local/bin` and offers to build the `claudio` container image if it is not present yet. If you skip the build, `claudio` offers it again on first run.

### Windows

Open a **PowerShell** terminal, navigate to the repository root, and run:

```powershell
.\install.ps1
```

The installer will:

1. Check whether `%USERPROFILE%\.local\bin` is on your PATH — if not, it will offer to add it.
2. Write a configured `claudio.bat` to `%USERPROFILE%\.local\bin`, pointing back to `claudio.ps1` in the repository.
3. Offer to build the image. This needs a running Podman machine: if there is none yet, `claudio` creates it on first run and offers the build then.

`claudio.ps1` is not copied — it stays in the repository directory.

### Linux

From the repository root, run:

```sh
./install.sh
```

The installer will:

1. Check whether `~/.local/bin` is on your PATH — if not, it will offer to add it in `~/.bashrc`, `~/.zshrc` or `~/.profile`, depending on your shell.
2. Create `~/.local/bin/claudio` as a symlink to `claudio.sh` in the repository.
3. Offer to build the image.

If the PATH was updated, **restart your terminal** before continuing.

## Usage

Navigate to any project directory and run:

```sh
claudio
```

This launches an interactive Claude Code session inside the container. On Windows it first starts the Podman machine (creating it on first run if needed); on Linux Podman runs natively and no machine is needed.

The current directory is mounted under `/app`, mirroring its host path (e.g. `C:\work\foo` becomes `/app/c/work/foo`, `/home/me/foo` becomes `/app/home/me/foo`), and Claude is started from there. This way each project keeps its own Claude memory and settings. Symlinks (and on Windows junctions, `subst` drives and letter case) are resolved first, so a project keeps the same path, and its sessions, however you navigate to it.

Any arguments are forwarded to `claude`:

```sh
claudio --continue
claudio -p "explain this repo"
```

## Configuration

On first run `claudio` creates `~/claudio.ini` (`%USERPROFILE%\claudio.ini` on Windows):

| Key | Default | Meaning |
| --- | --- | --- |
| `home` | `~/claudehome` | Host directory holding Claude's settings and credentials (see below) |
| `update_check_days` | `7` | See [Updates](#updates) |
| `mountpoints` | your user folder and every drive | Windows only: comma-separated `host:machine` paths shared with the Podman machine |
| `machine` | `podman-machine-default` | Windows only: Podman machine to use |

### Claude home

The `home` directory is mounted into every container, so settings, login and history survive across sessions. `claudio` creates what is missing on first run:

- `claude/` and `claude.json`: Claude Code's settings and state
- `.env`: environment variables for the container, one `VAR=value` per line

To authenticate, either run `/login` inside Claude (the login is kept in `claude/`), or put one of these in `.env`:

```
CLAUDE_CODE_OAUTH_TOKEN=<token from `claude setup-token`>
ANTHROPIC_API_KEY=<API key>
```

### Mountpoints (Windows)

`mountpoints` is only applied when `claudio` creates the Podman machine: editing it afterwards has no effect, and `claudio` warns when it no longer matches the machine. To apply new mountpoints, remove the machine and let `claudio` create it again:

```powershell
podman machine rm podman-machine-default
claudio
```

### File ownership and SELinux (Linux)

With rootless Podman, `claudio` runs the container's `claude` user as your own user (`--userns=keep-id`), so files Claude creates in your project and Claude home are owned by you.

On SELinux systems (Fedora, RHEL, ...) the container could not access the mounted directories, so `claudio` disables SELinux labelling for the container (`--security-opt label=disable`) instead of relabelling your files.

## Updates

Claude Code's auto-updater is disabled inside the container, since updates would be lost when it exits. Instead, once the image is older than `update_check_days` (default 7, set in `claudio.ini`; `0` disables the check), `claudio` compares the Claude Code version in the image with the latest release and offers to rebuild the image. After a check it waits another `update_check_days` before checking again. On Linux the check is skipped when `claudio` is not run from a terminal.

To rebuild manually with a specific version, from the repository root:

```sh
podman build -t claudio --build-arg CLAUDE_CODE_VERSION=<version> .
```

## Uninstall

The Claude home (`home` in `claudio.ini`, by default `~/claudehome`) holds your Claude settings, login and history: delete it only if you no longer need them. The image can be removed with `podman rmi claudio`.

### Windows

Delete the installed launcher (`claudio.ps1` stays in the repository):

```powershell
Remove-Item "$env:USERPROFILE\.local\bin\claudio.bat"
```

To also remove the configuration and the state files `claudio` keeps next to it:

```powershell
Remove-Item "$env:USERPROFILE\claudio.ini", "$env:USERPROFILE\.claudio-*"
```

To also remove the directory from your PATH, open **System Properties → Environment Variables** and edit the `Path` user variable.

### Linux

Delete the launcher symlink, and optionally the configuration and state files:

```sh
rm ~/.local/bin/claudio
rm ~/claudio.ini ~/.claudio-*
```

If the installer added `~/.local/bin` to your PATH, remove the lines marked `# Added by the claudio installer` from your shell startup file.

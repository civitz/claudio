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

This starts the Podman machine (creating it on first run if needed) and launches an interactive Claude Code session with the current directory mounted as `/app` inside the container.

## Uninstall

Delete the two installed files:

```powershell
Remove-Item "$env:USERPROFILE\.local\bin\claudio.bat"
Remove-Item "$env:USERPROFILE\.local\bin\claudio.ps1"
```

`claudio.ps1` lives in the repository and is not touched by uninstall.

To also remove the directory from your PATH, open **System Properties → Environment Variables** and edit the `Path` user variable.

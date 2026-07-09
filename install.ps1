$InstallDir = "$env:USERPROFILE\.local\bin"

# Check if install dir is on PATH (user or machine scope)
$UserPath    = [Environment]::GetEnvironmentVariable("PATH", "User")
$MachinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$AllPaths    = ($UserPath + ";" + $MachinePath) -split ";" | ForEach-Object { $_.TrimEnd("\") }

if ($AllPaths -notcontains $InstallDir.TrimEnd("\")) {
    Write-Host "'$InstallDir' is not in your PATH."
    $confirm = Read-Host "Add it now? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Error "Aborted. Add '$InstallDir' to your PATH and re-run the installer."
        exit 1
    }
    $NewUserPath = ($UserPath.TrimEnd(";") + ";" + $InstallDir).TrimStart(";")
    [Environment]::SetEnvironmentVariable("PATH", $NewUserPath, "User")
    Write-Host "Added '$InstallDir' to your user PATH."
    $pathAdded = $true
} else {
    $pathAdded = $false
}

# Ensure the install directory exists
if (-not (Test-Path $InstallDir)) {
    Write-Error "'$InstallDir' does not exist on disk. Create it first, then re-run the installer."
    exit 1
}

# Write claudio.bat with the repo dir baked in (claudio.ps1 stays here)
$batContent = (Get-Content "$PSScriptRoot\claudio.bat" -Raw) -replace "__SCRIPT_DIR__", $PSScriptRoot
Set-Content "$InstallDir\claudio.bat" $batContent -NoNewline
Write-Host "Installed claudio.bat -> $InstallDir\claudio.bat"
Write-Host "claudio.ps1 remains at $PSScriptRoot\claudio.ps1"

Write-Host ""
Write-Host "Installation complete."
if ($pathAdded) {
    Write-Host "Restart your terminal (or open a new one) for the PATH change to take effect."
}

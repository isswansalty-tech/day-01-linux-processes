<#
.SYNOPSIS
    Helper script to push day-01-linux-processes to GitHub via WSL or Git
#>
$GH_USER = "isswansalty-tech"
$REPO_NAME = "day-01-linux-processes"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   GitHub Deployment Helper: $GH_USER/$REPO_NAME            " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Check if WSL is available
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    Write-Host "[+] WSL detected. Invoking WSL push helper..." -ForegroundColor Green
    wsl bash /mnt/c/Users/pc/.gemini/antigravity/scratch/day-01-linux-processes/push_to_github.sh
} else {
    Write-Host "[!] WSL not found. Please install Git for Windows or run from WSL." -ForegroundColor Yellow
}

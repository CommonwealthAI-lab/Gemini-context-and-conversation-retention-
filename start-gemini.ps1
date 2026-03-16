# This script ensures the main run-gemini.ps1 script is executed with administrator privileges.

# --- Check for Admin Privileges and Re-launch if Necessary ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Not running as admin, so re-launch the main run script with elevation and exit the current one.
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-File", "D:\run-gemini.ps1"
    exit
}

# --- If already admin, just run the main script ---
& "D:\run-gemini.ps1"

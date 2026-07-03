# ============================================================
# Profil PowerShell partage (versionne dans workstation-setup)
# ============================================================
#
# Source de verite du profil pwsh : pose par setup.ps1 dans
#   <Documents>\PowerShell\profile.workstation.ps1
# et dot-source depuis $PROFILE. Les persos locales (ex: fonction
# 'deploy' boulot) restent dans $PROFILE et ne sont PAS ecrasees.

Import-Module posh-git

# Wrapper Maven Wrapper : 'mvnw' depuis n'importe ou, avec message clair
# si le wrapper est absent du projet courant.
function Invoke-MvnwWrapper {
    if (-not (Test-Path ".\mvnw.cmd")) {
        Write-Error "Maven Wrapper manquant dans '$(Get-Location)'"
        Write-Host "Sans wrapper -> mvn clean compile" -ForegroundColor Yellow
        return 1
    }
    & ".\mvnw.cmd" @args
}

Set-Alias mvnw Invoke-MvnwWrapper

# Raccourci docker compose
function dc { docker compose $args }

# Encode en UTF-8 pwsh pour afficher correctement les caracteres accentues
# (notamment la sortie de psql).
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:LC_ALL = 'C.UTF-8'

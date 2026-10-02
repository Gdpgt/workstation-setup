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

# Bases a la demande : les services MySQL / PostgreSQL / MongoDB sont en demarrage
# Manuel (cf. setup.ps1 -HardenDb). Detection par chemin de l'executable (pas par nom).
#   dbstart|dbstop [pg|postgres] [mysql] [mongo]   -- sans argument : les 3 bases
# Demarrer/arreter un service exige l'admin : hors shell admin, la fonction s'eleve
# elle-meme (un prompt UAC par appel).
function Invoke-DbService {
    param([ValidateSet('Start', 'Stop')][string]$Action, [string[]]$Names)

    $kindOf = @{
        pg = 'postgres'; postgres = 'postgres'; postgresql = 'postgres'
        mysql = 'mysql'; mariadb = 'mysql'
        mongo = 'mongo'; mongod = 'mongo'; mongodb = 'mongo'
    }
    $wanted = @()
    foreach ($n in $Names) {
        if (-not $kindOf.ContainsKey($n.ToLower())) {
            Write-Error "Base inconnue : '$n' (pg | mysql | mongo)"; return
        }
        $wanted += $kindOf[$n.ToLower()]
    }

    $services = @(Get-CimInstance Win32_Service | Where-Object {
        $_.PathName -match 'mysqld\.exe|pg_ctl\.exe|mongod\.exe'
    } | Where-Object {
        $kind = if ($_.PathName -match 'mysqld\.exe') { 'mysql' }
                elseif ($_.PathName -match 'pg_ctl\.exe') { 'postgres' } else { 'mongo' }
        (-not $wanted) -or ($kind -in $wanted)
    })
    if (-not $services) { Write-Warning "Aucun service de base de donnees correspondant."; return }

    $svcNames = ($services | ForEach-Object { "'" + ($_.Name -replace "'", "''") + "'" }) -join ','
    $cmd = "$Action-Service -Name $svcNames -ErrorAction Continue"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
        IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Invoke-Expression $cmd
    }
    else {
        $self = (Get-Process -Id $PID).Path
        Start-Process -FilePath $self -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-Command', "`"$cmd`"")
    }
    $services | ForEach-Object { Get-Service -Name $_.Name } | Format-Table Name, Status -AutoSize
}
function dbstart { Invoke-DbService -Action Start -Names $args }
function dbstop  { Invoke-DbService -Action Stop  -Names $args }

# Encode en UTF-8 pwsh pour afficher correctement les caracteres accentues
# (notamment la sortie de psql).
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:LC_ALL = 'C.UTF-8'

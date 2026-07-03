<#
.SYNOPSIS
    Amorcage d'un PC Windows 11 vierge (avant setup.ps1).
.DESCRIPTION
    A lancer EN PREMIER sur une machine fraiche. Il :
      1. installe git via winget (si absent)
      2. clone le repo workstation-setup dans ~\code (idempotent)
      3. installe Claude Code en NATIF (irm officiel, sans Node, auto-update)
      4. affiche les etapes suivantes

    Recuperation sur PC vierge (le seul fetch manuel, in-memory -> pas
    d'ExecutionPolicy a contourner) :
      irm https://raw.githubusercontent.com/Gdpgt/workstation-setup/main/Notes_changement_pc_WINDOWS_perso/bootstrap.ps1 | iex

    NB: ne PAS lancer ce script comme fichier (.\bootstrap.ps1) sans
    'Set-ExecutionPolicy -Scope Process Bypass' au prealable. La voie irm|iex
    ci-dessus est la voie nominale.
    A lancer en PowerShell USER (pas admin) : winget et le clone n'ont pas besoin
    d'admin, et Claude Code non plus.
#>

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/Gdpgt/workstation-setup.git'
$RepoDir = Join-Path $HOME 'code\workstation-setup'

function Write-Info($m) { Write-Host "--> $m" -ForegroundColor Cyan }
function Write-Ok  ($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[!]  $m" -ForegroundColor Yellow }

function Update-PathFromRegistry {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"
}

# --- Pre-requis : winget (App Installer) ---
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn "winget introuvable. Installe 'App Installer' depuis le Microsoft Store, puis relance."
    exit 1
}

# --- 1. git ---
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "git deja installe"
} else {
    Write-Info "Installation de git via winget..."
    winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
    # Le PATH machine est mis a jour mais PAS la session courante -> refresh,
    # sinon 'git clone' juste apres echoue (git introuvable).
    Update-PathFromRegistry
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn "git toujours introuvable apres install. Ouvre un nouveau terminal et relance."
        exit 1
    }
    Write-Ok "git installe"
}

# --- 2. Clone idempotent (jamais de pull aveugle : Claude edite setup.ps1) ---
if (Test-Path (Join-Path $RepoDir '.git')) {
    Write-Info "Repo deja present : tentative de mise a jour (fast-forward only)..."
    git -C $RepoDir pull --ff-only 2>$null
    Write-Ok "Repo a jour : $RepoDir"
} else {
    Write-Info "Clone du repo dans $RepoDir ..."
    New-Item -ItemType Directory -Force -Path (Join-Path $HOME 'code') | Out-Null
    git clone $RepoUrl $RepoDir
    Write-Ok "Repo clone : $RepoDir"
}

# --- 3. Claude Code natif (sans Node, auto-update) ---
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Ok "Claude Code deja installe"
} else {
    Write-Info "Installation de Claude Code (natif)..."
    irm https://claude.ai/install.ps1 | iex
    # L'installer pose claude.exe dans %USERPROFILE%\.local\bin -> refresh PATH.
    Update-PathFromRegistry
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Ok "Claude Code installe"
    } else {
        Write-Warn "claude pas encore dans le PATH de cette session (normal)."
    }
}

# --- 4. Etapes suivantes ---
Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Bootstrap termine." -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
@"

  Etapes suivantes :

  1. Ouvre un NOUVEAU terminal (pour que 'claude' soit dans le PATH).

  2. cd $RepoDir

  3. claude
       -> login (compte Claude Pro / Max / Team / Enterprise / Console REQUIS ;
          le plan gratuit ne donne PAS acces a Claude Code)

  4. Provisionne le PC. Modele recommande : TOI tu lances le script, Claude
     repare les erreurs.
       .\setup.ps1
     Si exit 2, demande a Claude :
       "lis %LOCALAPPDATA%\workstation-setup\last-run.log et corrige les erreurs"

  5. Etape opt-in (PowerShell ADMIN, a lancer toi-meme) :
       .\setup.ps1 -EnrollTpm     # BitLocker TPM+PIN (note la cle de recuperation !)

"@ | Write-Host -ForegroundColor White

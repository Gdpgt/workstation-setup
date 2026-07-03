<#
.SYNOPSIS
    Provisionne un nouveau PC Windows 11 (env dev fullstack Java/Spring + outils perso).
.DESCRIPTION
    Installe les logiciels via winget, Scoop, npm, PowerShellGet et l'installer
    officiel Google (pour Antigravity CLI).
    Idempotent : peut etre relance sans risque.
    Lancer depuis PowerShell USER (pas admin). WSL2 doit deja etre installe
    (voir l'Etape 1 - Pre-requis WSL2 de Note_Provisionnement_nouveau_PC_Window.md).

    En cas d'echec, le script affiche un RECAP rouge a la fin avec tous les paquets
    qui ont foire, leurs codes de retour et le chemin du log conserve.
    Exit code 0 = tout OK, exit code 2 = au moins un echec.
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -SkipScoop
    .\setup.ps1 -SkipAntigravity
#>

[CmdletBinding()]
param(
    [switch]$SkipWinget,
    [switch]$SkipScoop,
    [switch]$SkipNpm,
    [switch]$SkipPwshModules,
    [switch]$SkipAntigravity,
    [switch]$EnrollTpm        # OPT-IN : active BitLocker TPM+PIN (exige ADMIN), puis sort.
)

$ErrorActionPreference = 'Continue'

# ============================================================
# Self-logging (transcript) + sortie propre
# ============================================================
#
# Start-Transcript capture le fil narratif du run (sections, OK/echecs, recap)
# dans un fichier fixe -> c'est ce que Claude Code lit pour diagnostiquer. NB:
# le DETAIL winget/scoop/npm est deja detourne vers %TEMP%\setup_*.log (ne passe
# pas par la console), donc le transcript ne le contient pas (par design).
# Tous les 'exit' passent par Exit-Setup qui ferme proprement le transcript et
# ecrit la ligne EXIT= (sinon un exit precoce laisse le transcript ouvert).

$script:LogDir = Join-Path $env:LOCALAPPDATA 'workstation-setup'
New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
$script:LastRunLog = Join-Path $script:LogDir 'last-run.log'
try { Start-Transcript -Path $script:LastRunLog -Force | Out-Null } catch {}

function Exit-Setup {
    param([int]$Code)
    Write-Host "EXIT=$Code"
    try { Stop-Transcript | Out-Null } catch {}
    exit $Code
}

# ============================================================
# Configuration
# ============================================================

$WingetPackages = @(
    'Microsoft.PowerShell'
    'Google.Chrome'
    'Foxit.FoxitReader'
    'TheDocumentFoundation.LibreOffice'
    # 'Google.Antigravity'                   # SKIP (mai 2026) : depuis Google I/O,
                                             #   ce paquet pointe vers la plateforme
                                             #   d'orchestration d'agents v2.0+, plus
                                             #   l'IDE. Le nouveau paquet "Antigravity
                                             #   IDE" est en cours d'ajout sur
                                             #   winget-pkgs (issue #376908).
                                             #   En attendant : install manuelle depuis
                                             #   https://antigravity.google/download
    'PostgreSQL.PostgreSQL'
    'Oracle.MySQL'
    'MongoDB.Server'
    'MongoDB.Shell'
    'MongoDB.Compass.Full'
    'Docker.DockerDesktop'
    'Mozilla.Thunderbird'
    'Notepad++.Notepad++'
    'Stremio.Stremio'
    'Valve.Steam'
    'Dropbox.Dropbox'
)

$ScoopBuckets = @('extras', 'java')

$ScoopPackages = @(
    'vscode'
    'idea'                  # IntelliJ IDEA Community (extras bucket).
                            #   Ultimate = 'idea-ultimate' si licence dispo.
    'maven'
    'temurin17-jdk'
    'temurin21-jdk'
    'temurin25-jdk'
    'nodejs-lts'
    'python'
    'bruno'
    'dbeaver'
)

# NB: @anthropic-ai/claude-code a ete RETIRE (2026-06-19). Claude Code est
# desormais installe en NATIF par bootstrap.ps1 (irm https://claude.ai/install.ps1
# | iex), qui n'exige pas Node et s'auto-update. Garder AUSSI le npm creerait deux
# 'claude' dans le PATH -> source unique = le natif. La section npm retire au
# passage tout binaire npm orphelin.
#
# NB: @google/gemini-cli a ete RETIRE apres Google I/O 2026 (19 mai 2026, deadline
# consumer 18 juin 2026), remplace par Antigravity CLI.
$NpmGlobals = @(
    '@openai/codex'
    '@angular/cli'                # Tooling dev front (pas une CLI IA) : fournit
                                  #   la commande 'ng'. Latest (non pinne), coherent
                                  #   avec les autres globals ; suivi via npm update -g.
)

$PwshModules = @(
    'posh-git'
)

# ============================================================
# Collecteur d'echecs (recap a la fin)
# ============================================================

$script:Failures = New-Object System.Collections.Generic.List[psobject]

function Register-Failure {
    param(
        [Parameter(Mandatory)][string]$Type,      # winget | scoop | npm | pwsh | curl
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Reason,
        [string]$LogPath = ''
    )
    $script:Failures.Add([PSCustomObject]@{
        Type    = $Type
        Package = $Package
        Reason  = $Reason
        LogPath = $LogPath
    })
}

# ============================================================
# Helpers
# ============================================================

function Write-Section($title) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Write-Info ($m) { Write-Host "  --> $m" -ForegroundColor Gray }
function Write-Ok   ($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn ($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Write-Err  ($m) { Write-Host "  [X]  $m" -ForegroundColor Red }

function Update-PathFromRegistry {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-Wsl2Installed {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    wsl --status 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-ScoopBucketAdded {
    param([string]$Bucket)
    # Plus robuste qu'un regex sur "scoop bucket list" (format de sortie
    # variable selon les versions). Le bucket est forcement materialise
    # sous ~/scoop/buckets/<nom> apres ajout.
    return Test-Path "$env:USERPROFILE\scoop\buckets\$Bucket"
}

function New-LogFile {
    param([string]$Prefix)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $name  = "setup_${Prefix}_${stamp}.log"
    return Join-Path $env:TEMP $name
}

# ============================================================
# BitLocker TPM + PIN (opt-in via -EnrollTpm)
# ============================================================
#
# Lie le chiffrement disque au TPM avec un PIN -> au boot on tape juste le PIN
# (pas la passphrase). Exige l'ADMIN (contrairement au reste du script). Gere les
# deux etats : disque clair (Enable-BitLocker) vs deja chiffre par Device
# Encryption (ajout TpmPin + retrait du protecteur Tpm-seul, sinon pas de PIN
# demande au boot). La cle de recuperation est affichee a l'ecran (jamais ecrite
# en clair sur le disque qu'on chiffre).

function Invoke-BitLockerEnroll {
    Write-Section "BitLocker TPM + PIN (opt-in)"

    if (-not (Test-IsAdmin)) {
        Write-Err "Cette operation exige un PowerShell ADMINISTRATEUR."
        Write-Err "Relance : clic droit sur PowerShell > 'Executer en tant qu'administrateur',"
        Write-Err "          puis : .\setup.ps1 -EnrollTpm"
        Exit-Setup 1
    }

    # 1. TPM present et pret ?
    $tpm = Get-Tpm
    if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) {
        Write-Err "TPM absent ou non pret (TpmPresent=$($tpm.TpmPresent), TpmReady=$($tpm.TpmReady))."
        Register-Failure -Type 'bitlocker' -Package 'TPM' -Reason 'TPM not present/ready'
        Exit-Setup 2
    }
    Write-Ok "TPM 2.0 present et pret"

    # 2. Autoriser le PIN par policy (sinon -TpmAndPinProtector echoue).
    #    UseAdvancedStartup=1 ; UseTPMPIN=2 (2=Allow ; PAS 1=Require qui rendrait
    #    le PIN obligatoire partout + bloquerait le retrait du Tpm-seul).
    $fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    New-Item -Path $fve -Force | Out-Null
    Set-ItemProperty -Path $fve -Name 'UseAdvancedStartup' -Value 1 -Type DWord
    Set-ItemProperty -Path $fve -Name 'UseTPMPIN'          -Value 2 -Type DWord
    Write-Ok "Policy FVE : PIN autorise (UseAdvancedStartup=1, UseTPMPIN=2)"

    $mp  = 'C:'
    $vol = Get-BitLockerVolume -MountPoint $mp

    # 3. Idempotence : protecteur TpmPin deja present ?
    if ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin') {
        Write-Ok "Protecteur TpmPin deja present sur $mp : rien a faire."
        Exit-Setup 0
    }

    # 4. PIN (SecureString ; Read-Host -AsSecureString en produit un directement).
    Write-Info "Choisis un PIN de demarrage (6-20 caracteres)."
    $pin = Read-Host -AsSecureString "PIN BitLocker"

    try {
        if ($vol.VolumeStatus -eq 'FullyDecrypted' -and $vol.ProtectionStatus -eq 'Off') {
            # Disque clair : Enable-BitLocker (cree volume + protecteur) PUIS recovery.
            Write-Info "Disque non chiffre : activation BitLocker (XtsAes256, en tache de fond)..."
            Enable-BitLocker -MountPoint $mp -EncryptionMethod XtsAes256 `
                -TpmAndPinProtector -Pin $pin -UsedSpaceOnly -ErrorAction Stop | Out-Null
            Add-BitLockerKeyProtector -MountPoint $mp -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
            Write-Ok "BitLocker active avec TPM+PIN"
        }
        else {
            # Deja chiffre (Device Encryption) : ajouter TpmPin PUIS retirer Tpm-seul.
            Write-Info "Disque deja chiffre : ajout du protecteur TPM+PIN..."
            Add-BitLockerKeyProtector -MountPoint $mp -TpmAndPinProtector -Pin $pin -ErrorAction Stop | Out-Null
            Write-Ok "Protecteur TPM+PIN ajoute"
            $tpmOnly = (Get-BitLockerVolume -MountPoint $mp).KeyProtector |
                Where-Object KeyProtectorType -eq 'Tpm'
            foreach ($kp in $tpmOnly) {
                Remove-BitLockerKeyProtector -MountPoint $mp -KeyProtectorId $kp.KeyProtectorId -ErrorAction Stop | Out-Null
                Write-Ok "Protecteur Tpm-seul retire (sinon pas de PIN au boot)"
            }
            if (-not ((Get-BitLockerVolume -MountPoint $mp).KeyProtector |
                      Where-Object KeyProtectorType -eq 'RecoveryPassword')) {
                Add-BitLockerKeyProtector -MountPoint $mp -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
            }
        }
    }
    catch {
        Write-Err "Echec configuration BitLocker : $($_.Exception.Message)"
        Register-Failure -Type 'bitlocker' -Package 'BitLocker' -Reason $_.Exception.Message
        Exit-Setup 2
    }

    # 5. Cle de recuperation : AFFICHEE (priorite ecran, pas de fichier en clair).
    $rec = (Get-BitLockerVolume -MountPoint $mp).KeyProtector |
        Where-Object KeyProtectorType -eq 'RecoveryPassword'
    Write-Section "CLE DE RECUPERATION BitLocker — RECOPIE-LA HORS MACHINE"
    foreach ($r in $rec) {
        Write-Warn "ID $($r.KeyProtectorId) : $($r.RecoveryPassword)"
    }
    Write-Warn "Sans cette cle, une panne TPM ou une MAJ firmware = donnees PERDUES."
    Write-Warn "Note-la dans un gestionnaire de mots de passe / sur papier, hors de ce PC."
    Write-Info "Prochain boot : le PIN sera demande. Une MAJ firmware peut declencher"
    Write-Info "l'ecran de recuperation BitLocker (d'ou l'importance de la cle ci-dessus)."

    Exit-Setup 0
}

# Court-circuit OPT-IN : si -EnrollTpm, on fait UNIQUEMENT BitLocker puis on sort,
# AVANT le check "pas d'admin" du provisioning normal (qui ferait exit 1 en admin).
if ($EnrollTpm) {
    Invoke-BitLockerEnroll
}

# ============================================================
# Pre-requis
# ============================================================

Write-Section "Verification des pre-requis"

if (Test-IsAdmin) {
    Write-Err "Ce script ne doit PAS etre lance en admin (Scoop refuse)."
    Write-Err "Relance-le depuis PowerShell USER."
    Exit-Setup 1
}
Write-Ok "Mode user (non-admin)"

if (-not (Test-Wsl2Installed)) {
    Write-Err "WSL2 n'est pas installe."
    Write-Host ""
    Write-Host "  Etapes manuelles AVANT de relancer ce script :" -ForegroundColor Yellow
    Write-Host "    1. Ouvre PowerShell ADMIN" -ForegroundColor White
    Write-Host "    2. Lance : wsl --install" -ForegroundColor White
    Write-Host "    3. Redemarre le PC" -ForegroundColor White
    Write-Host "    4. Relance ce script (PowerShell user)" -ForegroundColor White
    Exit-Setup 1
}
Write-Ok "WSL2 detecte"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget introuvable. Installe 'App Installer' depuis le Microsoft Store."
    Exit-Setup 1
}
Write-Ok "winget detecte"

Write-Warn "Note : des prompts UAC vont apparaitre pendant l'execution"
Write-Warn "       (Docker Desktop, PostgreSQL, MySQL, MongoDB.Server) malgre --silent."
Write-Warn "       --silent passe au installer, pas a UAC."

# ============================================================
# Winget
# ============================================================

if (-not $SkipWinget) {
    Write-Section "Paquets Winget"

    Write-Info "Mise a jour des sources..."
    winget source update | Out-Null

    foreach ($pkg in $WingetPackages) {
        Write-Info "Installation : $pkg"
        $logFile = New-LogFile "winget_$($pkg -replace '[^\w]','_')"
        winget install -e --id $pkg `
            --accept-package-agreements `
            --accept-source-agreements `
            --silent *>&1 | Out-File -FilePath $logFile -Encoding utf8

        switch ($LASTEXITCODE) {
            0           {
                Write-Ok "$pkg"
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            }
            -1978335189 {
                # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
                # = paquet deja installe et a jour (winget tente l'upgrade implicite)
                Write-Ok "$pkg (deja a jour)"
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            }
            default     {
                Write-Err "$pkg : code $LASTEXITCODE (log : $logFile)"
                Register-Failure -Type 'winget' -Package $pkg `
                    -Reason "exit $LASTEXITCODE" -LogPath $logFile
            }
        }
    }

    Update-PathFromRegistry
}

# ============================================================
# Scoop
# ============================================================

if (-not $SkipScoop) {
    Write-Section "Scoop"

    $SkipScoopBody = $false

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Info "Installation de Scoop..."
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-RestMethod get.scoop.sh | Invoke-Expression
            Update-PathFromRegistry
            Write-Ok "Scoop installe"
        } catch {
            Write-Err "Echec install Scoop : $_"
            Register-Failure -Type 'scoop' -Package '(scoop itself)' `
                -Reason "install script failed: $_"
            # Sans Scoop on ne peut pas continuer la section : on saute la
            $SkipScoopBody = $true
        }
    } else {
        Write-Ok "Scoop deja installe"
    }

    if (-not $SkipScoopBody) {
        Write-Info "Git (pre-requis pour les buckets)..."
        $gitLog = New-LogFile 'scoop_git'
        scoop install git *>&1 | Out-File -FilePath $gitLog -Encoding utf8
        if ($LASTEXITCODE -eq 0) {
            Remove-Item $gitLog -Force -ErrorAction SilentlyContinue
        } else {
            Write-Err "scoop install git : code $LASTEXITCODE (log : $gitLog)"
            Register-Failure -Type 'scoop' -Package 'git' `
                -Reason "exit $LASTEXITCODE" -LogPath $gitLog
        }

        foreach ($bucket in $ScoopBuckets) {
            if (Test-ScoopBucketAdded $bucket) {
                Write-Ok "Bucket $bucket deja ajoute"
            } else {
                Write-Info "Ajout du bucket : $bucket"
                $bucketLog = New-LogFile "scoop_bucket_$bucket"
                scoop bucket add $bucket *>&1 | Out-File -FilePath $bucketLog -Encoding utf8
                if (Test-ScoopBucketAdded $bucket) {
                    Write-Ok "Bucket $bucket"
                    Remove-Item $bucketLog -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Err "Bucket $bucket : echec (log : $bucketLog)"
                    Register-Failure -Type 'scoop' -Package "bucket:$bucket" `
                        -Reason "bucket add failed" -LogPath $bucketLog
                }
            }
        }

        Write-Section "Paquets Scoop"
        foreach ($pkg in $ScoopPackages) {
            Write-Info "Installation : $pkg"
            $logFile = New-LogFile "scoop_$pkg"
            scoop install $pkg *>&1 | Out-File -FilePath $logFile -Encoding utf8
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "$pkg"
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            } else {
                Write-Err "$pkg : code $LASTEXITCODE (log : $logFile)"
                Register-Failure -Type 'scoop' -Package $pkg `
                    -Reason "exit $LASTEXITCODE" -LogPath $logFile
            }
        }

        Update-PathFromRegistry
    }
}

# ============================================================
# Configuration Git (~/.gitconfig)
# ============================================================
#
# Ecrit mes options + alias Git via 'git config --global' (une commande par
# cle). Non destructif : ne touche pas a l'identite (user.name / user.email),
# qui reste une etape manuelle. Idempotent : 'git config' ecrase la valeur
# existante a chaque run.
# Git provient de Scoop (section precedente) ; si absent (ex: -SkipScoop), on
# saute proprement.

Write-Section "Configuration Git (~/.gitconfig)"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn "git introuvable (Scoop saute ?) : configuration Git sautee."
} else {
    # Cles simples (cle = valeur). Single quotes = valeur litterale : les '!'
    # et '&&' des alias ne doivent pas etre interpretes par PowerShell.
    $gitSettings = [ordered]@{
        'pull.rebase'       = 'true'
        'color.status'      = 'auto'
        'color.diff'        = 'auto'
        'color.branch'      = 'auto'
        'core.editor'       = 'C:/Program Files/Notepad++/notepad++.exe'
        'core.excludesfile' = '~/.gitignore_global'
        'alias.ca'          = 'commit --amend'
        'alias.can'         = 'commit --amend --no-edit'
        'alias.frm'         = '!git fetch && git reset --hard origin/main'
        'alias.ac'          = '!git add . && git commit -m'
        'alias.acan'        = '!git add . && git commit --amend --no-edit'
        'alias.fsc'         = '!git fetch && git switch -c'
        'alias.p'           = 'push'
        'alias.pf'          = 'push --force-with-lease'
    }

    foreach ($key in $gitSettings.Keys) {
        $value = $gitSettings[$key]
        git config --global $key $value
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$key = $value"
        } else {
            Write-Err "git config --global $key : code $LASTEXITCODE"
            Register-Failure -Type 'git' -Package $key `
                -Reason "git config set failed (exit $LASTEXITCODE)"
        }
    }

    Write-Info "Identite Git (user.name / user.email) : a definir manuellement"
}

# ============================================================
# gitignore global (~/.gitignore_global)
# ============================================================
#
# Pose le fichier pointe par core.excludesfile (section Git ci-dessus). Sans lui,
# l'option pointe vers un fichier inexistant => aucun effet. Hors du 'if git' :
# la creation ne depend pas de git (simple fichier texte).
#
# Strategie : CREER SI ABSENT (on ne touche pas a un fichier existant, pour
# preserver d'eventuels ajouts manuels). Consequence : une evolution future de
# ce contenu de base ne se propage pas sur une machine deja provisionnee.
#
# NB : contenu duplique a l'identique dans setup.sh (Linux). Les deux dossiers OS
# sont autonomes (pas de fichier partage). Volontairement EXCLU : *.properties
# (casse application.properties / Spring) et env* (casse environment.ts /
# Angular) — trop larges en global.

Write-Section "gitignore global (~/.gitignore_global)"

# Chemin reel via Join-Path $HOME (ce que git resout aussi pour '~'). Pas de
# "~/..." litteral : '~' ne s'etend pas dans les API .NET.
$gitignoreGlobal = Join-Path $HOME '.gitignore_global'

if (Test-Path $gitignoreGlobal) {
    Write-Ok "~/.gitignore_global deja present : laisse tel quel"
} else {
    # Here-string LITTERALE @'...'@ : pas d'interpolation des '$' ni des '!'.
    $gitignoreContent = @'
# gitignore global — exclusions valables pour tous mes dépôts.
# Référencé par core.excludesfile (~/.gitconfig).

# --- OS ---
.DS_Store
Thumbs.db
desktop.ini

# --- Éditeurs / IDE ---
.idea/
*.iml
.vscode/
*.swp
*.swo
*~

# --- Java / Maven ---
target/
*.class

# --- Node / Angular ---
node_modules/
npm-debug.log*
.angular/cache/

# --- Variables d'environnement / secrets ---
# Ordre obligatoire : exclusion AVANT négation. C'est *.env.* qui capte
# .env.example, et !*.env.* qui le ré-inclut ensuite.
.env
*.env
*.env.*
!*.env.example
!*.env.exemple
!*.env.template

# --- Logs & divers ---
*.log
'@

    try {
        # UTF-8 SANS BOM impose : 'Out-File -Encoding utf8' poserait un BOM sous
        # PS5 (cf. avertissement plus bas), qui colle a la 1re regle et la fait
        # ignorer par git. Le contenu a des accents => BOM reellement en jeu.
        [System.IO.File]::WriteAllText(
            $gitignoreGlobal,
            $gitignoreContent,
            [System.Text.UTF8Encoding]::new($false)
        )
        Write-Ok "~/.gitignore_global cree"
    } catch {
        $msg = $_.Exception.Message
        Write-Err "gitignore global : $msg"
        Register-Failure -Type 'git' -Package '.gitignore_global' -Reason $msg
    }
}

# ============================================================
# Identite git perso (noreply) pour les repos sous ~/code
# ============================================================
#
# Ce repo est PUBLIC : un commit expose l'email git de la machine. Pour ne jamais
# fuiter d'email reel (gmail perso, ou email pro sur un PC de travail), on route
# tous mes repos PERSO (ranges sous ~/code) vers l'adresse noreply GitHub, via un
# 'includeIf' conditionnel. Ca ne touche PAS l'identite globale par defaut : sur
# un PC pro, les repos sous ~/workspace gardent l'email pro. Idempotent.

Write-Section "Identite git perso (noreply pour ~/code)"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn "git absent : identite perso non configuree (non bloquant)"
} else {
    $persoFile = Join-Path $HOME '.gitconfig-perso'
    # 'git config --file' cree/met a jour ces 2 cles sans toucher au reste.
    git config --file $persoFile user.name  "Guillaume de Puget"
    git config --file $persoFile user.email "142890016+Gdpgt@users.noreply.github.com"
    # gitdir/i : matching insensible a la casse (chemins Windows).
    git config --global 'includeIf.gitdir/i:~/code/.path' '~/.gitconfig-perso'
    Write-Ok "Repos sous ~/code -> noreply (includeIf)"
}

# ============================================================
# CLI IA via npm
# ============================================================

if (-not $SkipNpm) {
    Write-Section "CLI IA (npm globals)"

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Err "npm introuvable. Verifie que nodejs-lts est bien installe via Scoop."
        Register-Failure -Type 'npm' -Package '(npm itself)' `
            -Reason "npm command not found (nodejs-lts manquant ?)"
    } else {
        # Nettoyage : retire l'ancien claude-code npm (machines provisionnees avant
        # le 2026-06-19). Claude Code vient du natif (bootstrap.ps1) -> on evite le
        # double binaire 'claude'. Idempotent : no-op si absent.
        npm ls -g --depth=0 '@anthropic-ai/claude-code' *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Retrait de l'ancien @anthropic-ai/claude-code (npm) -> natif"
            npm uninstall -g '@anthropic-ai/claude-code' *>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "claude-code npm retire (natif prend le relais)" }
            else { Write-Warn "Echec retrait claude-code npm (non bloquant)" }
        }

        foreach ($pkg in $NpmGlobals) {
            Write-Info "Installation : $pkg"
            $logFile = New-LogFile "npm_$($pkg -replace '[^\w]','_')"
            npm install -g $pkg *>&1 | Out-File -FilePath $logFile -Encoding utf8
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "$pkg"
                Remove-Item $logFile -Force -ErrorAction SilentlyContinue
            } else {
                Write-Err "$pkg : code $LASTEXITCODE (log : $logFile)"
                Register-Failure -Type 'npm' -Package $pkg `
                    -Reason "exit $LASTEXITCODE" -LogPath $logFile
            }
        }
    }
}

# ============================================================
# Antigravity CLI (Google) - remplace Gemini CLI depuis I/O 2026
# ============================================================
#
# Annonce Google I/O 2026 (19 mai 2026) : Gemini CLI est remplace par
# Antigravity CLI. Pour les comptes consumer (Google AI Pro/Ultra +
# tier gratuit), Gemini CLI cesse de fonctionner le 18 juin 2026.
# Antigravity CLI est ecrit en Go, partage le meme agent harness que
# l'app desktop Antigravity 2.0. Binaire installe : 'agy'.

if (-not $SkipAntigravity) {
    Write-Section "Antigravity CLI (Google)"

    if (Get-Command agy -ErrorAction SilentlyContinue) {
        Write-Ok "Antigravity CLI (agy) deja installe"
    } else {
        Write-Info "Installation : Antigravity CLI via l'installer officiel..."
        $agyLog = New-LogFile 'antigravity_cli'
        # NB: 'irm | iex' a la meme limite que 'curl | bash' : si le HTTP renvoie
        # du contenu malforme mais en 200 OK, iex peut "reussir" en n'executant
        # rien d'utile. D'ou la verification post-install via Get-Command.
        try {
            $installScript = Invoke-RestMethod -Uri 'https://antigravity.google/cli/install.ps1' `
                                               -UseBasicParsing
            Invoke-Expression $installScript *>&1 | Out-File -FilePath $agyLog -Encoding utf8

            # Refresh du PATH puisque l'installer ajoute son repertoire au PATH user
            Update-PathFromRegistry

            if (Get-Command agy -ErrorAction SilentlyContinue) {
                Write-Ok "Antigravity CLI (agy)"
                Remove-Item $agyLog -Force -ErrorAction SilentlyContinue
            } else {
                Write-Err "Antigravity CLI : installer execute mais 'agy' introuvable (log : $agyLog)"
                Register-Failure -Type 'curl' -Package 'antigravity-cli' `
                    -Reason "installer ran but 'agy' not found on PATH" -LogPath $agyLog
            }
        } catch {
            $msg = $_.Exception.Message
            Write-Err "Antigravity CLI : echec installer ($msg)"
            Register-Failure -Type 'curl' -Package 'antigravity-cli' `
                -Reason $msg -LogPath $agyLog
        }
    }
}

# ============================================================
# Modules PowerShell (posh-git, etc.)
# ============================================================

if (-not $SkipPwshModules) {
    Write-Section "Modules PowerShell"

    # Trust PSGallery pour eviter le prompt interactif "Untrusted repository"
    $psg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($psg -and $psg.InstallationPolicy -ne 'Trusted') {
        Write-Info "Trust PSGallery..."
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    foreach ($mod in $PwshModules) {
        if (Get-Module -ListAvailable -Name $mod) {
            Write-Ok "$mod deja installe"
        } else {
            Write-Info "Installation : $mod"
            try {
                Install-Module -Name $mod -Scope CurrentUser -Force -ErrorAction Stop
                Write-Ok "$mod"
            } catch {
                $msg = $_.Exception.Message
                Write-Err "$mod : $msg"
                Register-Failure -Type 'pwsh' -Package $mod -Reason $msg
            }
        }
    }
}

# ============================================================
# Profil PowerShell ($PROFILE)
# ============================================================
#
# Pose le profil partage (posh-git, wrapper mvnw, alias dc, encodage UTF-8)
# versionne a cote de ce script. Strategie : on copie le fichier versionne dans
# le dossier du profil sous le nom 'profile.workstation.ps1' (source de verite,
# reecrite a chaque run), puis on s'assure que $PROFILE le dot-source. On NE
# touche PAS au contenu existant de $PROFILE (persos locales type fonction
# 'deploy' preservees).
#
# NB : lancer ce script SOUS pwsh 7 pour que $PROFILE cible
# Documents\PowerShell\... (et non le profil Windows PowerShell 5).

Write-Section "Profil PowerShell"

# Garde-fou : sous Windows PowerShell 5, $PROFILE cible Documents\WindowsPowerShell\
# (et non Documents\PowerShell\ de pwsh 7). On poserait alors le profil au mauvais
# endroit silencieusement. On avertit sans bloquer (l'utilisateur peut vouloir le
# profil PS5 en connaissance de cause).
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warn "Tu tournes sous PowerShell $($PSVersionTable.PSVersion) (pas pwsh 7)."
    Write-Warn "  `$PROFILE va cibler Documents\WindowsPowerShell\ au lieu de Documents\PowerShell\."
    Write-Warn "  Relance ce script sous pwsh 7 pour poser le profil au bon endroit."
}

$profileSource = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'

if (-not (Test-Path $profileSource)) {
    Write-Err "Profil versionne introuvable : $profileSource"
    Register-Failure -Type 'pwsh' -Package 'profile.workstation.ps1' `
        -Reason "source file missing: $profileSource"
} else {
    try {
        $profileDir  = Split-Path $PROFILE -Parent
        $managedFile = Join-Path $profileDir 'profile.workstation.ps1'

        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        # Source de verite : on ecrase a chaque run.
        Copy-Item -Path $profileSource -Destination $managedFile -Force
        Write-Ok "Profil partage copie : $managedFile"

        # Dot-source idempotent depuis $PROFILE.
        $sourceLine = ". `"$managedFile`""
        if (-not (Test-Path $PROFILE)) {
            New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        }
        $profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($profileContent -and $profileContent.Contains($sourceLine)) {
            Write-Ok "`$PROFILE dot-source deja present"
        } else {
            Add-Content -Path $PROFILE -Value @"

# workstation-setup : charge le profil partage versionne
$sourceLine
"@
            Write-Ok "Dot-source ajoute a `$PROFILE"
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Err "Profil PowerShell : $msg"
        Register-Failure -Type 'pwsh' -Package 'profile.workstation.ps1' -Reason $msg
    }
}

# ============================================================
# Variables d'environnement
# ============================================================

Write-Section "Variables d'environnement"

$gitBashPath = "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
if (Test-Path $gitBashPath) {
    $current = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
    if ($current -ne $gitBashPath) {
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $gitBashPath, 'User')
        Write-Ok "CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath"
    } else {
        Write-Ok "CLAUDE_CODE_GIT_BASH_PATH deja definie"
    }
} else {
    Write-Warn "git bash (Scoop) introuvable, variable non definie"
}

# ============================================================
# Etapes manuelles
# ============================================================

Write-Section "Etapes manuelles restantes"

@"

  [ ] Docker Desktop  : Settings > General > activer le backend WSL2

  [ ] PostgreSQL      : mot de passe SUPERUSER par defaut = "postgres"
                        (cf. EDB unattended install via winget).
                        A CHANGER apres l'install :
                          psql -U postgres
                          ALTER USER postgres WITH PASSWORD '<nouveau>';

  [ ] MySQL           : noter le mot de passe root genere pendant l'install
                        (UAC interactif, pas vraiment silencieux)

  [ ] MongoDB         : le service MongoDB demarre automatiquement.
                        Verifier : Get-Service MongoDB

  [ ] BitLocker TPM+PIN: (opt-in) boot par PIN. Depuis un PowerShell ADMIN :
                          .\setup.ps1 -EnrollTpm
                        /!\ NOTE LA CLE DE RECUPERATION affichee (hors machine).
                        Une MAJ firmware peut declencher l'ecran de recuperation
                        BitLocker -> garde la cle precieusement.

  [ ] Antigravity IDE : depuis Google I/O 2026 (19 mai 2026), la marque
                        Antigravity regroupe 4 surfaces sur le meme agent harness :
                          - Antigravity 2.0 : app desktop d'orchestration d'agents
                          - Antigravity CLI : terminal (deja installe via irm|iex,
                                              binaire 'agy', remplace Gemini CLI)
                          - Antigravity SDK : programmation d'agents custom
                          - Antigravity IDE : l'IDE historique de Nov 2025
                        Le winget package 'Google.Antigravity' pointe vers l'app
                        desktop v2.0 (plus un IDE). Pour avoir l'editeur original :
                        DL manuel sur https://antigravity.google/download
                        Re-active la ligne dans `$WingetPackages quand le nouveau
                        paquet (Google.AntigravityIDE ?) sera publie.

  [ ] Marvin          -> https://amazingmarvin.com
  [ ] Freedom         -> https://freedom.to
  [ ] Mem.ai          -> https://mem.ai

  [ ] Git identite    : options + alias deja configures par le script.
                        Reste a definir l'identite :
                          git config --global user.name "..."
                          git config --global user.email "..."

  [ ] Authent         : se logger dans :
                        - Claude Code      (claude)
                        - Codex CLI        (codex auth)
                        - Antigravity CLI  (agy auth) -- successeur Gemini CLI
                        - Antigravity IDE  (quand installe)

  [ ] PowerShell 7    : pwsh est installe. Pour les futures sessions, relance
                        Windows Terminal sur le profil "PowerShell" (pwsh)
                        et non "Windows PowerShell" (powershell.exe v5).

"@ | Write-Host -ForegroundColor White

# ============================================================
# RECAP final : echecs eventuels
# ============================================================

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "###############################################" -ForegroundColor Red
    Write-Host "#                                             #" -ForegroundColor Red
    $count = $script:Failures.Count
    Write-Host "#   ECHEC(S) D'INSTALLATION : $($count.ToString().PadRight(15))#" -ForegroundColor Red
    Write-Host "#                                             #" -ForegroundColor Red
    Write-Host "###############################################" -ForegroundColor Red
    Write-Host ""

    # Recap groupe par type
    $script:Failures | Group-Object Type | ForEach-Object {
        Write-Host "  --- $($_.Name.ToUpper()) ($($_.Count)) ---" -ForegroundColor Red
        foreach ($f in $_.Group) {
            Write-Host "    * $($f.Package)" -ForegroundColor Red
            Write-Host "        Raison : $($f.Reason)" -ForegroundColor DarkRed
            if ($f.LogPath) {
                Write-Host "        Log    : $($f.LogPath)" -ForegroundColor DarkRed
            }
        }
        Write-Host ""
    }

    Write-Host "  Verifier les logs ci-dessus puis relancer le script" -ForegroundColor Yellow
    Write-Host "  (idempotent : ne reinstalle pas ce qui est OK)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Pour voir un log :  notepad <chemin du log>" -ForegroundColor Yellow
    Write-Host ""

    Exit-Setup 2
}

Write-Section "Termine"
Write-Ok "Toutes les installations ont reussi."
Write-Host ""
Exit-Setup 0

<#
.SYNOPSIS
    Lance mes applis de travail a l'ouverture de session.
.DESCRIPTION
    Pose par setup.ps1 dans %LOCALAPPDATA%\StartupApps\ et lance par un raccourci
    du dossier Demarrage (shell:startup).
    Resolution PAR NOM dans le menu Demarrer, pas par chemin : resiste aux montees
    de version (dossier "IntelliJ IDEA 2026.x") et marche quel que soit
    l'installeur (MSI, Store, winget, scoop, choco).
      1. raccourci .lnk du menu Demarrer (applis Win32) ;
      2. sinon AUMID via Get-StartApps (applis Store : Teams, nouvel Outlook).
    On ne lance pas les Win32 via shell:AppsFolder : leur AppID est un chemin
    ("{GUID}\...\idea64.exe") et explorer ouvre alors le dossier Applications.
    Appli introuvable -> ligne dans launch-apps.log a cote du script.
#>

$apps = @(
    @{ Name = 'IntelliJ IDEA'; Pattern = '^IntelliJ IDEA \d' }
    @{ Name = 'Google Chrome'; Pattern = '^Google Chrome$' }
    @{ Name = 'Outlook'; Pattern = '^Outlook$'; Store = $true }
    @{ Name = 'Microsoft Teams'; Pattern = '^Microsoft Teams$'; Store = $true }
    @{ Name = 'OneNote'; Pattern = '^OneNote$' }
    @{ Name = 'Marvin'; Pattern = '^Marvin$' }
)

$log = Join-Path $PSScriptRoot 'launch-apps.log'

# Tri par numero de version (pas lexical : 2026.10 > 2026.9).
$byVersion = { if ($_.Name -match '\d+(\.\d+)+') { [version]$Matches[0] } else { [version]'0.0' } }

$shortcuts = Get-ChildItem -Recurse -Filter *.lnk -ErrorAction SilentlyContinue -Path @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
) | Select-Object @{ n = 'Name'; e = { $_.BaseName } }, FullName

function Find-Best($items, $pattern) {
    $items | Where-Object { $_.Name -match $pattern } |
        Sort-Object $byVersion -Descending | Select-Object -First 1
}

# Charge a la demande : les .lnk n'ont pas a attendre l'index du menu Demarrer,
# qui peut ne pas etre pret au logon (on lui laisse ~30 s).
$script:startApps = $null
function Get-StartAppsReady {
    if ($null -eq $script:startApps) {
        for ($i = 0; $i -lt 6; $i++) {
            $script:startApps = @(Get-StartApps)
            if ($script:startApps.Count -gt 0) { break }
            Start-Sleep -Seconds 5
        }
    }
    $script:startApps
}

# Store = $true : pas de recherche .lnk, sinon un raccourci "Outlook" d'un Office
# classique serait lance a la place du nouvel Outlook.
foreach ($app in $apps) {
    $lnk = if (-not $app.Store) { Find-Best $shortcuts $app.Pattern }
    if ($lnk) {
        Start-Process $lnk.FullName
        continue
    }
    $store = Find-Best (Get-StartAppsReady) $app.Pattern
    if ($store) {
        Start-Process explorer.exe -ArgumentList "`"shell:AppsFolder\$($store.AppID)`""
    } else {
        Add-Content $log "$(Get-Date -Format s) introuvable : $($app.Name)"
    }
}

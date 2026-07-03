# Provisionnement nouveau PC Windows 11

## Workflow (rapide)

Tout est automatisé via le script `setup.ps1` dans le repo `workstation-setup`.
Le script provisionne **n'importe quel nouveau PC Windows 11** (rien codé en dur).

### Étape 1 — Pré-requis manuel (PowerShell ADMIN)

```powershell
# WSL2 (requis par Docker Desktop ET Antigravity IDE)
wsl --install
```

Redémarrer le PC.

### Étape 2 — Bootstrap (amorçage en une commande, PowerShell USER)

Installe git, clone le repo dans `~\code`, et installe **Claude Code en natif** :

```powershell
irm https://raw.githubusercontent.com/Gdpgt/workstation-setup/main/Notes_changement_pc_WINDOWS_perso/bootstrap.ps1 | iex
```

> ⚠️ **Repo privé** : ce fetch anonyme échoue (404) tant que le repo n'est pas
> public ou sans token GitHub. Le `git clone` interne du bootstrap, lui, passe par
> tes creds git.

> La voie `irm | iex` s'exécute en mémoire → pas besoin de toucher l'ExecutionPolicy.
> (Si tu télécharges le fichier `.ps1` pour le lancer, là il faudrait
> `Set-ExecutionPolicy -Scope Process Bypass`.)
> Voir aussi « Provisionner avec Claude Code » plus bas.

### Étape 3 — Lancer le script (PowerShell USER, pas admin)

```powershell
cd ~\code\workstation-setup
.\setup.ps1
```

Le script logue le run (fil narratif + exit code) dans
`%LOCALAPPDATA%\workstation-setup\last-run.log` (via `Start-Transcript`). Il fait,
dans l'ordre :
1. Check pré-requis (mode user, WSL2 OK, winget dispo)
2. Installe tous les paquets winget
3. Installe Scoop + buckets + paquets dev
4. Configure le `.gitconfig` (options + alias via `git config --global`) —
   n'écrit pas l'identité (`user.name`/`user.email`), qui reste manuelle. Puis
   crée `~/.gitignore_global` (pointé par `core.excludesfile`) **si absent** :
   exclusions OS / IDE / build / `.env` (UTF-8 sans BOM)
5. Installe les CLI IA via npm (`codex`) + Angular CLI (`@angular/cli` → `ng`).
   **Claude Code = natif** (bootstrap), plus via npm ; le script retire l'ancien
   npm orphelin s'il traîne
6. Installe **Antigravity CLI** via l'installer officiel Google (`irm | iex`) —
   remplace Gemini CLI, deadline 18 juin 2026 pour les comptes consumer
7. Installe les modules PowerShell (posh-git…)
8. Pose le **profil PowerShell** partagé (posh-git, wrapper `mvnw`, alias `dc`,
   encodage UTF-8 console) — copie `profile.workstation.ps1` et l'ajoute en
   dot-source dans `$PROFILE` (sans écraser les persos locales)
9. Configure `CLAUDE_CODE_GIT_BASH_PATH`
10. Affiche la checklist des étapes manuelles restantes

Idempotent : on peut le relancer sans casser quoi que ce soit.

> **Opt-in (PowerShell ADMIN, non lancé par le run normal)** : `.\setup.ps1
> -EnrollTpm` active BitLocker TPM+PIN (boot par PIN). Cf. section dédiée plus bas.

> ⚠️ **UAC** : malgré `--silent`, des prompts UAC vont apparaître pour les apps
> qui requièrent admin (Docker Desktop, PostgreSQL, MySQL, MongoDB Server).
> Le flag `--silent` passe au installer, pas à UAC.

### Comment savoir si tout s'est bien passé ?

À la fin du run, le script :

- **Succès complet** → section `Termine` en vert + `[OK] Toutes les
  installations ont reussi.` + exit code `0`.
- **Au moins un échec** → encart rouge `ECHEC(S) D'INSTALLATION : N`
  avec récap groupé par type (winget / scoop / npm / pwsh / curl), incluant pour
  chaque paquet KO :
  - le code de retour
  - le chemin du log conservé dans `%TEMP%` (`setup_<type>_<pkg>_<timestamp>.log`)
  - exit code `2`

Pour voir un log : `notepad <chemin>` (le chemin est affiché dans le récap).

Le script est idempotent : après avoir corrigé la cause, on peut le relancer
et il ne touche pas à ce qui est déjà installé.

> 💡 Les logs des installations **réussies** sont supprimés à la volée (pas
> de pollution dans `%TEMP%`). Seuls les logs d'échec sont conservés.

### Étape 4 — Étapes manuelles

Le script imprime la checklist détaillée à la fin. En résumé :

- [ ] Docker Desktop : activer le backend WSL2
- [ ] PostgreSQL : changer le mot de passe `postgres` par défaut (voir ci-dessous)
- [ ] MySQL : noter le mot de passe root généré pendant l'install (UAC interactif)
- [ ] **Antigravity IDE** : install manuelle (voir note ci-dessous)
- [ ] Marvin, Freedom, Mem.ai (installeurs propriétaires)
- [ ] Authent dans les CLI IA (`claude`, `codex auth`, `agy auth`)
- [ ] Angular (VSCode) : installer l'extension **Angular Language Service**
      (`Angular.ng-template`). Optionnel : extension Chrome **Angular DevTools**.
      `ng` est posé par le script (npm global).
- [ ] Git identité (`user.name` + `user.email`) — options et alias déjà posés par le script
- [ ] Basculer Windows Terminal sur le profil PowerShell 7 (pwsh)

> ℹ️ Le profil PowerShell (posh-git, `mvnw`, `dc`, UTF-8) est désormais **posé
> par le script** (étape 8). Il est dot-sourcé depuis `$PROFILE` ; les ajouts
> locaux non versionnés (ex. fonction `deploy` boulot) sont préservés. Lance
> `setup.ps1` **sous pwsh 7** pour cibler le bon `$PROFILE`.

## ⚠️ Cas particulier : Antigravity (post Google I/O 2026)

**Mise à jour majeure le 19 mai 2026.** À l'origine (novembre 2025),
Antigravity était un IDE AI standalone basé sur VS Code. Depuis Google I/O
2026, la marque **Antigravity** désigne une plateforme à 4 surfaces sur un
seul agent harness partagé :

| Surface | Type | Statut script |
|---|---|---|
| **Antigravity 2.0** | App desktop (orchestrateur d'agents, plus un IDE) | Manuel |
| **Antigravity CLI** | Terminal (binaire `agy`, écrit en Go) | ✅ Automatisé (`irm \| iex`) |
| **Antigravity SDK** | Programmation d'agents custom | Pas concerné |
| **Antigravity IDE** | L'IDE historique de novembre 2025 | Manuel |

**Conséquences pratiques** pour ce script :

- **Antigravity CLI** est installé automatiquement via le script PowerShell
  officiel (`irm https://antigravity.google/cli/install.ps1 | iex`). Il
  **remplace Gemini CLI**, qui s'arrête le 18 juin 2026 pour les comptes
  consumer (Google AI Pro/Ultra + tier gratuit).
- **Antigravity IDE** reste en install manuelle. Le winget package
  `Google.Antigravity` pointe désormais vers l'app desktop v2.0 (orchestrateur
  d'agents, plus un IDE). Un nouveau package pour l'IDE historique est en
  cours de création sur winget-pkgs (issue
  [#376908](https://github.com/microsoft/winget-pkgs/issues/376908)).
- **Tant que le nouveau package ID n'est pas publié** :
  - Le script n'installe PAS l'IDE (ligne commentée dans `$WingetPackages`)
  - DL manuel : <https://antigravity.google/download>
  - Quand le package sera dispo (probablement `Google.AntigravityIDE`),
    décommenter la ligne dans `$WingetPackages`

## Provisionner avec Claude Code (boucle de réparation)

Le bootstrap installe Claude Code pour qu'il **corrige les erreurs du provisioning
à ma place**. Modèle d'exécution (le seul fiable) : **moi je lance le script** (je
gère les UAC / le PIN BitLocker, je vois la sortie en direct), **Claude lit le
résultat sur disque et corrige**. Son outil shell est non-interactif → il ne peut
pas répondre aux prompts UAC.

1. PC vierge → WSL2 (Étape 1) → bootstrap (Étape 2).
2. Nouveau terminal → `cd ~\code\workstation-setup` → `claude` → login (compte
   Pro/Max/Team/Enterprise/Console **requis**, le gratuit ne marche pas).
3. **Moi** : `.\setup.ps1`.
4. Si exit 2, dire à Claude : « lis `%LOCALAPPDATA%\workstation-setup\last-run.log`
   (+ les logs `%TEMP%\setup_*`) et corrige les erreurs, je relance ». Il édite
   `setup.ps1` + cette note.
5. Relancer (idempotent) jusqu'à exit 0.
6. Étape opt-in à lancer **moi-même** en PowerShell ADMIN : `.\setup.ps1 -EnrollTpm`.

> Le transcript `last-run.log` capture le fil narratif (sections, OK/échecs, recap).
> Le **détail** winget/scoop/npm reste dans `%TEMP%\setup_*.log` (il ne passe pas par
> la console). Claude lit les deux.

## ⚠️ Cas particulier : BitLocker TPM + PIN (opt-in)

But : booter **sans** que Windows déverrouille le disque silencieusement — un
**PIN** court est demandé au démarrage. Lance (opt-in, exige l'ADMIN) :

```powershell
# Depuis un PowerShell ADMINISTRATEUR :
.\setup.ps1 -EnrollTpm
```

Ce que ça fait (`Invoke-BitLockerEnroll`, idempotent) :
1. vérifie le TPM (`Get-Tpm`) ;
2. autorise le PIN par policy registre `HKLM\…\FVE` : `UseAdvancedStartup=1`,
   **`UseTPMPIN=2`** (2 = *Allow*, pas 1 = *Require*) ;
3. selon l'état du disque :
   - **clair** : `Enable-BitLocker -EncryptionMethod XtsAes256 -TpmAndPinProtector
     -Pin … -UsedSpaceOnly`, puis ajoute une clé de récupération ;
   - **déjà chiffré (Device Encryption)** : ajoute le protecteur **TpmPin** PUIS
     **retire le protecteur Tpm-seul** (sinon le boot ne demande jamais le PIN) ;
4. **affiche la clé de récupération** à l'écran.

> ⚠️ **NOTE LA CLÉ DE RÉCUPÉRATION** hors machine (gestionnaire de mots de passe /
> papier). Sans elle, une panne TPM ou une **MAJ firmware** = données perdues. Une
> MAJ firmware peut d'ailleurs déclencher l'écran de récupération BitLocker au boot.
> Bonne pratique avant une MAJ firmware connue : `Suspend-BitLocker -RebootCount 1`.
> La clé est **affichée**, jamais écrite en clair sur le disque qu'on chiffre.

## ⚠️ Cas particulier : PostgreSQL

L'install winget unattended utilise les valeurs par défaut, dont le mot de passe
SUPERUSER `postgres`. À changer immédiatement après l'install :

```powershell
# Ouvrir psql en tant que postgres (mot de passe : postgres)
psql -U postgres

# Dans psql :
ALTER USER postgres WITH PASSWORD '<nouveau_mdp>';
\q
```

## Logiciels installés (pour référence)

### Via Winget (script)

| Catégorie | Logiciel | ID Winget |
|---|---|---|
| Shell | PowerShell 7 | `Microsoft.PowerShell` |
| Navigateur | Chrome | `Google.Chrome` |
| Bureautique | Foxit Reader | `Foxit.FoxitReader` |
| Bureautique | LibreOffice | `TheDocumentFoundation.LibreOffice` |
| ~~IDE~~ | ~~Google Antigravity~~ | ~~`Google.Antigravity`~~ (cf. note ci-dessus) |
| BDD | PostgreSQL | `PostgreSQL.PostgreSQL` |
| BDD | MySQL | `Oracle.MySQL` |
| BDD | MongoDB Server | `MongoDB.Server` |
| BDD | MongoDB Shell (mongosh) | `MongoDB.Shell` |
| BDD | MongoDB Compass | `MongoDB.Compass.Full` |
| Conteneurs | Docker Desktop | `Docker.DockerDesktop` |
| Mail | Thunderbird | `Mozilla.Thunderbird` |
| Éditeur | Notepad++ | `Notepad++.Notepad++` |
| Loisirs | Stremio | `Stremio.Stremio` |
| Loisirs | Steam | `Valve.Steam` |
| Cloud | Dropbox | `Dropbox.Dropbox` |

### Via Scoop (script, buckets `extras` + `java`)

| Catégorie | Logiciel | Paquet Scoop |
|---|---|---|
| IDE | VSCode | `vscode` |
| IDE | IntelliJ IDEA Community | `idea` |
| Build | Maven | `maven` |
| JDK | Temurin 17/21/25 | `temurin{17,21,25}-jdk` |
| Runtime | Node.js LTS | `nodejs-lts` |
| Runtime | Python LTS | `python` |
| API | Bruno | `bruno` |
| BDD | DBeaver | `dbeaver` |
| VCS | Git | `git` |

### Via npm global (script)

- `@openai/codex`
- `@angular/cli` (fournit `ng`) — tooling de dev front Angular, pas une CLI IA.
  Installé en latest (non pinné). `ng` est sur le PATH une fois Node/npm en place
  (Scoop `nodejs-lts`), après ouverture d'un nouveau terminal.

> **Claude Code n'est plus installé via npm** (2026-06-19). Il est posé en **natif**
> par `bootstrap.ps1` (`irm https://claude.ai/install.ps1 | iex`) : pas de dépendance
> Node, auto-update. Garder aussi le npm créerait deux binaires `claude` dans le PATH
> → source unique = le natif. Le script retire l'ancien `@anthropic-ai/claude-code`
> npm s'il traîne.

### Via bootstrap (natif)

- **Claude Code** — `irm https://claude.ai/install.ps1 | iex` (binaire dans
  `%USERPROFILE%\.local\bin`, auto-update). Installé par `bootstrap.ps1`.

> ⚠️ **`@google/gemini-cli` a été retiré** suite à Google I/O 2026 (19 mai 2026).
> Gemini CLI est déprécié pour les comptes consumer (Google AI Pro/Ultra +
> tier gratuit) avec arrêt de service le **18 juin 2026**. Il est remplacé par
> Antigravity CLI, installé via `irm | iex` (voir section suivante). Les comptes
> Enterprise Code Assist + utilisateurs API key gardent Gemini CLI indéfiniment.

### Via installer Google officiel (script, `irm | iex`)

- **Antigravity CLI** — `irm https://antigravity.google/cli/install.ps1 | iex`
  - Binaire installé : `agy`
  - Successeur de Gemini CLI (cf. note ci-dessus), écrit en Go
  - Partage le même agent harness que l'app desktop Antigravity 2.0
  - Le script vérifie post-install que `agy` est sur le PATH (parade contre
    le risque "200 OK avec body vide" de `irm | iex`)

### Via PowerShellGet (script)

- `posh-git` (autocomplétion Git dans PowerShell)

### Profil PowerShell (script)

- `Microsoft.PowerShell_profile.ps1` (versionné dans le repo) copié vers
  `<Documents>\PowerShell\profile.workstation.ps1`, dot-sourcé depuis `$PROFILE`.
  Contenu : `Import-Module posh-git`, wrapper `mvnw` (`Invoke-MvnwWrapper`),
  alias `dc` (`docker compose`), encodage UTF-8 console (psql).
  - Une fonction de déploiement propre à un projet pro est **volontairement
    hors repo** (contenu privé) : elle reste dans le `$PROFILE` local, préservée
    par le dot-source.

### Manuel (non scriptable)

- **Antigravity 2.0** (app desktop d'orchestration d'agents — DL sur https://antigravity.google/download)
- **Antigravity IDE** (l'IDE historique, en attendant la stabilisation du nouveau package winget)
- Marvin, Freedom, Mem.ai (auth ou installeurs propriétaires)

## Pourquoi cette répartition ?

- **Winget** par défaut : officiel Microsoft, natif Windows 11, supporte
  export/import, IDs publiés par les éditeurs eux-mêmes.
- **Scoop** réservé au dev CLI multi-versions (JDK, Node, Python) et aux outils
  portables sans besoin admin. Pas d'UAC, install user-space dans `~/scoop/`.
- **Chocolatey** abandonné : tout ce qui était dessus est désormais sur Winget.
  Plus besoin d'un 3ᵉ gestionnaire.
- **npm** pour les CLI IA car c'est leur canal de distribution principal
  (avec une alternative native pour Claude Code, voir plus haut).
- **PowerShellGet** pour les modules PowerShell purs (posh-git).

## Maintenance (1× par mois)

```powershell
winget upgrade --all
scoop update *
npm update -g     # codex ; Claude Code n'est plus ici (natif auto-updaté)
Update-Module     # pour posh-git et autres modules PowerShell

# Antigravity CLI : pas de mise à jour native via npm/winget.
# Relancer simplement l'installer officiel pour avoir la dernière version :
#   irm https://antigravity.google/cli/install.ps1 | iex
# (ou : agy --version, si auto-update intégré, dépend des releases Google)
```

Pour Antigravity 2.0 / Antigravity IDE, Marvin, Freedom, Mem.ai : attendre la
notif d'auto-MAJ de chaque app. **Claude Code** (natif) s'auto-update aussi.

> ⚠️ Avant une MAJ firmware connue, si BitLocker TPM+PIN est actif :
> `Suspend-BitLocker -RebootCount 1` (évite l'écran de récupération au reboot).

## Avant de quitter ce PC (migration future)

À lancer sur l'ancien PC pour identifier des softwares qu'on a oublié d'ajouter
au script :

```powershell
winget export -o winget-current.json
scoop export > scoop-current.json
Get-InstalledModule | Select-Object Name, Version | Export-Csv pwsh-modules.csv

# Antigravity CLI (binaire 'agy', installé hors winget/scoop/npm)
if (Get-Command agy -ErrorAction SilentlyContinue) {
    agy --version > antigravity-cli-current.txt
}
```

Si des paquets sont présents sur la machine mais pas dans `setup.ps1` → décider :
à ajouter au script ou à abandonner. Commit la mise à jour de `setup.ps1` avant
de wipe.

---

## Changelog du script

- **2026-06-20** — Création de `~/.gitignore_global` :
  - **Nouveau** : section ajoutée juste après la config Git (hors du `if (Get-Command
    git)`, c'est un simple fichier texte). Crée le fichier pointé par
    `core.excludesfile`, jusqu'ici jamais posé → l'option pointait dans le vide.
    Contenu : OS, IDE (`.idea/`, `*.iml`, `.vscode/`…), Java/Maven, Node/Angular,
    `.env`/secrets (exceptions `!*.env.example/.exemple/.template`), logs.
  - **Stratégie « créer si absent »** (pas d'écrasement) → préserve d'éventuels ajouts
    manuels ; conséquence : une évolution du contenu de base ne se propage pas sur une
    machine déjà provisionnée. Chemin via `Join-Path $HOME`.
  - **UTF-8 SANS BOM impératif** : écriture via `[System.IO.File]::WriteAllText` +
    `UTF8Encoding($false)` (pas `Out-File -Encoding utf8`, qui pose un BOM sous PS5 →
    BOM collé à la 1re règle, ignorée par git). Le contenu a des accents.
  - **Volontairement EXCLU** : `*.properties` (Spring) et `env*` (`environment.ts` /
    Angular) — trop larges en global. Contenu **dupliqué à l'identique** dans
    `setup.sh` (Linux ; dossiers OS autonomes).

- **2026-06-19** — Généralisation « tout nouveau PC » + BitLocker + bootstrap :
  - **Généralisation (rien en dur)** : retrait d'entrées `safe.directory` et d'un
    alias git spécifiques à des projets pro. La config Git est désormais 100 % portable.
  - **BitLocker TPM+PIN (opt-in)** : `.\setup.ps1 -EnrollTpm` (switch `$EnrollTpm`,
    court-circuit ADMIN placé avant le check « pas d'admin »). Policy FVE
    (`UseAdvancedStartup=1`, `UseTPMPIN=2`), gestion disque clair vs Device
    Encryption (ajout TpmPin + retrait Tpm-seul), clé de récupération affichée.
  - **Bootstrap + Claude Code** : nouveau `bootstrap.ps1` (winget git + clone HTTPS
    dans `~\code` + Claude Code **natif** + `Update-PathFromRegistry`).
    `@anthropic-ai/claude-code` retiré de `$NpmGlobals` (source unique = natif) +
    cleanup du npm orphelin.
  - **Self-logging** : `Start-Transcript -Force` vers
    `%LOCALAPPDATA%\workstation-setup\last-run.log` ; tous les `exit` passent par
    `Exit-Setup` (ferme le transcript + ligne `EXIT=`). C'est ce que Claude Code lit.

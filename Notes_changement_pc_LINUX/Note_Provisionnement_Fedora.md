# Provisionnement nouveau PC Fedora Workstation 44

## Workflow (rapide)

Tout est automatisé via le script `setup.sh` dans le repo `workstation-setup`.
Ces scripts provisionnent **n'importe quel nouveau PC Fedora** (Intel/AMD/NVIDIA,
OLED ou non) — rien n'est codé en dur, tout est détecté au runtime.

### Étape 1 — Bootstrap (amorçage en une commande)

Une fois Fedora 44 installé et connecté, ouvrir un terminal et lancer le
bootstrap, qui installe git, clone le repo dans `~/code`, et installe **Claude
Code en natif** :

```bash
curl -fsSL https://raw.githubusercontent.com/Gdpgt/workstation-setup/main/Notes_changement_pc_LINUX/bootstrap.sh | bash
```

> ⚠️ **Repo privé** : ce fetch anonyme échoue (404) tant que le repo n'est pas
> public ou sans token GitHub. Le `git clone` interne du bootstrap, lui, passe par
> tes creds git.

> Voir aussi la section « Provisionner avec Claude Code » plus bas. Le chiffrement
> LUKS du disque, lui, se choisit **à l'installation de Fedora** (Anaconda, case
> « Chiffrer mes données ») — un script post-install ne peut pas chiffrer après coup.

### Étape 2 — Lancer le script (utilisateur normal, pas root)

```bash
cd ~/code/workstation-setup/Notes_changement_pc_LINUX
./setup.sh
```

Le script va te demander ton mot de passe sudo **une seule fois** au début,
puis garde le ticket actif en arrière-plan tant qu'il tourne. Il logue le run
complet (+ exit code) dans `~/.local/state/workstation-setup/last-run.log`.

Le script fait, dans l'ordre :

1. **Pré-requis** : vérifie qu'on est sur Fedora, pas root, dnf dispo, sudo OK
2. **Mise à jour système** : `dnf upgrade --refresh`
3. **RPM Fusion** (free + nonfree) : pour codecs, Steam, drivers
4. **Repos tiers** : installe `dnf5-plugins` en amont, puis Google Chrome, Microsoft VSCode, MongoDB 8.0
5. **Paquets dnf** : tous les outils dev + apps natifs + `pipx` + biométrie
   (`fprintd`, `fprintd-pam`, `tpm2-tools`)
6. **Paquets hardware (selon GPU détecté)** : Intel / AMD (swap freeworld) /
   NVIDIA (manuel) — cf. `install_hardware_packages()`
7. **Flathub + apps Flatpak** : Bruno, Stremio, MongoDB Compass, DBeaver, GIMP,
   Amberol (lecteur audio minimaliste, boucle une piste)
8. **JetBrains Toolbox** : install native via tarball officiel (gère ensuite IDEA Community, DataGrip, etc.)
9. **SDKMAN + JDKs Temurin** (17, 21, 25) + Maven
10. **npm en user-space** + CLI IA npm (`codex`) + Angular CLI (`@angular/cli` → `ng`).
    Claude Code = **natif** (bootstrap), plus via npm ; le script retire l'ancien npm orphelin s'il traîne.
11. **Antigravity CLI** : install via curl (remplace Gemini CLI, deadline 18 juin 2026)
12. **Services systemd** : init + enable de PostgreSQL, MariaDB, MongoDB ;
    socket Podman rootless + `DOCKER_HOST` dans `.bashrc`
13. **Configuration Git** : ecrit `~/.gitconfig` via `git config --global`
    (options + alias). N'ecrit PAS l'identite (`user.name`/`user.email`),
    qui reste manuelle. `core.editor = idea --wait` (IntelliJ). Puis
    `configure_gitignore_global()` cree `~/.gitignore_global` (pointe par
    `core.excludesfile`) **si absent** : exclusions OS / IDE / build / `.env`.
    Enfin `configure_git_perso_identity()` pose l'identité perso (noreply GitHub)
    pour les repos sous `~/code` via `includeIf` (repo public → jamais d'email réel
    exposé ; les repos pro sous `~/workspace` gardent l'email pro).
14. **Alias shell** : ajoute `dc` (`docker compose` → Podman) et la fonction
    `mvnw` dans `~/.bashrc` (portage minimal du profil PowerShell)
15. **Optims hardware** : `thermald` (si CPU Intel) + extensions Flatpak VAAPI
    selon le vendor (Intel / nvidia ; rien pour AMD)
16. **Configuration clavier** : layout `fr+oss` (French alt.) + shift-lock sur Caps Lock
17. **Biométrie** : active le PAM empreinte (authselect) si capteur détecté
18. **Extensions GNOME** : via `gext` (pipx). Clipboard Indicator (install +
    enable depuis EGO) ; AppIndicator Support (enable seul — l'extension vient
    du paquet dnf `gnome-shell-extension-appindicator`, pas d'EGO, pour rester
    en phase avec GNOME)
19. Affiche la checklist des étapes manuelles restantes
20. **Récap final** : vert si tout OK, rouge avec liste des échecs sinon

> **Opt-in (non lancé par le run normal)** : `./setup.sh --enroll-tpm` lie la clé
> LUKS au TPM (boot par PIN au lieu de la passphrase). Cf. section dédiée plus bas.

Idempotent : on peut le relancer sans casser quoi que ce soit.

### Étape 3 — Reload du shell

```bash
source ~/.bashrc
# OU mieux : ouvrir un nouveau terminal
```

C'est nécessaire pour que les ajouts du script soient pris en compte :

- `PATH` qui inclut `~/.npm-global/bin` (les CLI IA installées via npm)
- `DOCKER_HOST` qui pointe vers le socket Podman rootless
- Init de SDKMAN

### Étape 4 — Étapes manuelles

Le script imprime la checklist détaillée à la fin. En résumé :

- [ ] **PostgreSQL** : définir le mot de passe `postgres` et passer `pg_hba.conf` en `scram-sha-256`
- [ ] **MariaDB** : lancer `sudo mariadb-secure-installation`
- [ ] **MongoDB** : par défaut bind 127.0.0.1 sans auth, à durcir si besoin
- [ ] **Antigravity IDE** : install manuelle (en attendant le nouveau package, cf. section dédiée plus bas)
- [ ] Marvin, Freedom, Mem.ai (Linux : AppImage / Electron / web)
- [ ] Git identité (`user.name` + `user.email`) — options et alias sont déjà posés par le script
- [ ] Authent dans les CLI IA (`claude`, `codex auth`, `agy auth`)
- [ ] Angular (VSCode) : installer l'extension **Angular Language Service**
      (`Angular.ng-template`). Optionnel : extension Chrome **Angular DevTools**.
      Angular CLI lui-même (`ng`) est posé par le script (npm global).
- [ ] Steam : 1er lancement DL ~200 MB de runtimes Proton

### Comment savoir si tout s'est bien passé ?

Pareil que sur Windows :

- **Succès complet** → section `Termine` en vert + exit code `0`.
- **Au moins un échec** → encart rouge `ECHEC(S) D'INSTALLATION : N`
  groupé par type (dnf / dnf-repo / flatpak / sdkman / npm / curl / systemd),
  avec pour chaque paquet KO : raison + chemin du log dans
  `/tmp/setup_<type>_<pkg>_<timestamp>.log`
- Exit code `2`

Pour voir un log : `less /tmp/setup_<type>_<pkg>_<timestamp>.log`

Les logs des installs **réussies** sont supprimés à la volée (pas de pollution
dans `/tmp`). Seuls les logs d'échec sont conservés.

## Provisionner avec Claude Code (boucle de réparation)

Le bootstrap installe Claude Code pour qu'il **corrige les erreurs du provisioning
à ma place**. Modèle d'exécution (le seul fiable) : **moi je lance le script**
(je gère sudo / passphrase LUKS / PIN / swipe empreinte, je vois la sortie en
direct), **Claude lit le résultat sur disque et corrige**. Claude ne peut pas
piloter le script lui-même : son outil shell est non-interactif et bloquerait sur
les prompts `sudo`/empreinte.

1. PC vierge → bootstrap (Étape 1).
2. Nouveau terminal → `cd ~/code/workstation-setup` → `claude` → login (compte
   Pro/Max/Team/Enterprise/Console **requis**, le gratuit ne marche pas).
3. **Moi** : `./setup.sh`.
4. Si exit 2, dire à Claude :
   « lis `~/.local/state/workstation-setup/last-run.log` (et `/tmp/setup_*`) et
   corrige les erreurs, je relance ». Il édite `setup.sh` + cette note.
5. Relancer (idempotent) jusqu'à exit 0.
6. Étapes opt-in / interactives, à lancer **moi-même** (Claude rend la main via le
   préfixe `!`) : `./setup.sh --enroll-tpm`, `fprintd-enroll`.

Le script s'auto-logue via `script(1)` (TTY préservé → couleurs + prompts
interactifs OK) dans `~/.local/state/workstation-setup/last-run.log`, terminé par
une ligne `EXIT=<code>`. C'est ce fichier que Claude lit.

## ⚠️ Cas particulier : Biométrie (empreinte) + déverrouillage TPM (LUKS)

### Empreinte digitale (fprintd + PAM)

`configure_fingerprint()` (run normal) détecte un capteur (générique, via
`fprintd`/`lsusb` — aucun ID en dur), puis active le PAM empreinte de façon
idempotente : `sudo authselect enable-feature with-fingerprint` (login GDM + sudo).

L'**enrôlement** reste manuel (geste physique, non scriptable) :
```bash
fprintd-enroll
```
> ⚠️ **Capteurs ELAN** (vendor `04f3`) : bug `libfprint` qui gère certains capteurs
> *touch* en mode *swipe*. Garder le doigt immobile fait crasher l'enrôlement
> (`enroll-disconnected`). **Glisse lentement** le doigt du haut vers le bas sur le
> bouton d'alimentation. Le script affiche ce warning seulement si un ELAN est
> détecté ; sinon il indique la consigne générique.

### Déverrouillage TPM (LUKS) — opt-in `--enroll-tpm`

But : booter **sans retaper la passphrase LUKS**, juste un **PIN court**. Lance
(opt-in, touche au chiffrement → jamais dans le run normal) :
```bash
./setup.sh --enroll-tpm     # demande la passphrase LUKS existante, puis crée le PIN
```
Ce que ça fait (idempotent, 3 effets de bord = 3 checks indépendants) :
1. `/etc/dracut.conf.d/tpm2.conf` → module dracut `tpm2-tss` (sinon l'initramfs
   ignore le TPM) ;
2. `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 --tpm2-with-pin=yes`
   (le keyslot passphrase d'origine est **conservé** comme fallback) ;
3. `/etc/crypttab` : `tpm2-device=auto,tpm2-pin=yes` (`tpm2-pin=yes` est
   indispensable, sinon déverrouillage silencieux sans prompt PIN) ;
4. `dracut --regenerate-all --force` (tous les kernels, pas que le courant).

> ⚠️ **PCR 0+7** : la clé n'est libérée que si firmware (PCR 0) **et** Secure Boot
> (PCR 7) sont intègres. Donc **toute MAJ BIOS** (`fwupdmgr update`), voire un
> changement de réglage UEFI, casse le déverrouillage auto → re-saisie passphrase
> au boot + ré-enrôlement :
> ```bash
> LUKS=$(lsblk -rno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print "/dev/"$1; exit}')
> sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
>      --tpm2-pcrs=0+7 --tpm2-with-pin=yes "$LUKS"
> sudo dracut --regenerate-all --force
> ```
> ⚠️ **Une seule tentative de PIN** au boot : en cas d'erreur, taper la passphrase
> LUKS d'origine.

## ⚠️ Choix architecturaux Linux vs Windows

Quelques équivalences notables qui changent par rapport au PC Windows :

| Catégorie | Windows | Fedora |
|---|---|---|
| Package manager | winget | **dnf5** (Fedora 44+) |
| Outil portable user-space | Scoop | **Flatpak** (Flathub) + `~/.npm-global` |
| Multi-JDK | Scoop (`temurin*-jdk`) | **SDKMAN** (Temurin) |
| Containers | Docker Desktop | **Podman** (rootless, daemon-less) + `podman-docker` |
| MySQL | Oracle MySQL | **MariaDB** (compat ~95%, default Fedora) |
| PDF | Foxit Reader | **Papers** (default GNOME depuis F43, anciennement Evince) |
| Notepad++ | Notepad++ | **gnome-text-editor** (« Text Editor », default GNOME, pré-installé) |
| Auth git autocompletion | posh-git | **bash-completion** (déjà installé) |
| PowerShell | PS7 | non installé (bash suffit) |

## ⚠️ Cas particulier : Optimisations hardware (GPU détecté au runtime + OLED)

Le script automatise des optims hardware **selon le GPU détecté au runtime**
(`lspci`, par vendor ID PCI) — pas d'hypothèse sur la machine. Intel, AMD et
NVIDIA reçoivent les bons paquets ; `thermald` n'est activé que sur CPU Intel.
Voir `detect_gpu_vendors()` + `install_hardware_packages()` dans `setup.sh`.

### Accélération vidéo (VA-API) — paquets par vendor

Vendor-neutres (toujours installés) : `libva-utils` (`vainfo`),
`libavcodec-freeworld` (codecs patentés H.264/H.265, RPM Fusion nonfree —
**indispensable** : sans lui le décodage HW ne sert à rien sur les fichiers du
monde réel), `powertop`.

Selon le GPU détecté :
- **Intel** : `intel-media-driver` (iHD, Gen8+ : Iris Xe / Tiger Lake+) **+**
  `libva-intel-driver` (i965, couvre les Intel ≤ Gen9) + `intel-gpu-tools`
  (`intel_gpu_top`). HW decode/encode H.264/H.265/VP9/AV1 via Quick Sync.
- **AMD** : **swap** `mesa-va-drivers` → `mesa-va-drivers-freeworld` (+ vdpau)
  via `dnf swap` (PAS `install` : conflit de fichiers avec le paquet stock déjà
  présent) + `radeontop` (monitoring).
- **NVIDIA** : **non automatisé** (branche de driver selon le modèle, `akmod`,
  signature Secure Boot, reboot). Le script affiche l'étape manuelle :
  `sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-vaapi-driver`,
  puis attendre le build akmod + reboot.

**Vérification post-install** :
```bash
vainfo                        # doit lister les profils H.264/H.265/VP9/AV1
LIBVA_DRIVER_NAME=iHD vainfo  # Intel : si l'auto-détection rate
intel_gpu_top  # Intel  (ou:  radeontop  sur AMD)  -> "Video" > 0% en lecture
```

**Firefox + Chrome (rien à faire)** :
- Firefox active VA-API par défaut depuis la 101 sur Fedora pour Intel/AMD.
  Vérifier via `about:support` → ligne `HARDWARE_VIDEO_DECODING`.
- Chrome (et Chromium-based) active HW decode par défaut sur Wayland depuis
  Chrome 143. Vérifier via `chrome://gpu`.

### Accélération vidéo dans les Flatpaks

Les Flatpaks tournent dans un sandbox isolé : ils ne voient pas le driver host.
Solution = extension Flatpak VAAPI, **selon le vendor** :
- **Intel** : `org.freedesktop.Platform.VAAPI.Intel` (versions `24.08` + `25.08`).
- **NVIDIA** : `org.freedesktop.Platform.VAAPI.nvidia`.
- **AMD** : **aucune** extension dédiée — l'accel passe par le runtime
  `org.freedesktop.Platform.GL.default`, présent d'office. Rien à installer.

### Gestion thermique (thermald — Intel uniquement)

Sur Intel Tiger Lake et plus récent, **`thermald` débride les perfs** en plus de
gérer la chauffe (PPCC power table + RAPL pour ajuster les limites P-state). Sans
lui, Fedora applique des limites conservatrices → perf perdue sans gain thermique.
Le script l'installe + l'active **seulement si CPU Intel** (`grep GenuineIntel
/proc/cpuinfo`). Sur **AMD**, rien à installer : `amd_pstate` est géré par le noyau.

> 💡 thermald et power-profiles-daemon sont **complémentaires** (pas en
> conflit) : PPD gère les profils utilisateur (Économie/Équilibré/Perf), thermald
> évite les emballements thermiques. **TLP** par contre serait en conflit avec
> PPD, donc on ne l'installe pas.

### Profilage conso (powertop)

`powertop` est installé mais **pas activé en démon** par défaut. À lancer
manuellement après quelques heures d'usage normal pour profiler ta conso :
```bash
sudo powertop --html=/tmp/pwr.html        # rapport HTML détaillé
sudo powertop --calibrate                 # mode calibration (laptop débranché)
```

### Firmware (LVFS via fwupd)

`fwupd` est pré-installé sur Fedora Workstation. La plupart des constructeurs
(ASUS, Dell, Lenovo…) publient leurs firmware sur LVFS. À lancer une fois après
l'install :
```bash
sudo fwupdmgr refresh
fwupdmgr get-devices      # voir ce qui est detecte
sudo fwupdmgr update      # applique les MAJ
```

⚠️ Peut demander un reboot. Ne pas lancer en plein milieu d'une tâche.
⚠️ Si la liaison LUKS+TPM est active (PCR 0+7), une MAJ firmware invalide le
déverrouillage auto → re-saisie de la passphrase + ré-enrôlement (voir la section
biométrie + TPM plus bas).

### Écran OLED (si applicable)

SI ton PC a un écran **OLED** : pas de "pixel refresh" automatique sur Linux comme
sous Windows. Pour limiter le burn-in :

| Réglage | Où |
|---|---|
| Blank screen 5-10 min | Settings > Privacy > Screen Lock |
| Dark mode (pixels noirs = éteints sur OLED) | Settings > Appearance > Dark |
| Auto-hide top bar (optionnel) | extension `hidetopbar@mathieu.bidon.ca` (ID 545) |
| Animations réduites (limite l'usure) | Settings > Accessibility > Reduce Animations |

> 💡 Pour ajouter Hide Top Bar au script : ajouter `"545:hidetopbar@mathieu.bidon.ca:Hide Top Bar"`
> dans `GNOME_EXTENSIONS` dans `setup.sh`.

## ⚠️ Cas particulier : Gel au réveil de veille (ASUS Zenbook / Intel, i915 GuC)

**Symptômes**

- Mise en veille OK, mais au réveil : voyants allumés, écran noir, aucune touche
  / trackpad / bouton ne réagit. Seul un appui long (~10 s) sur le bouton on/off
  éteint la machine.
- Intermittent : parfois le réveil fonctionne, parfois il gèle.

**Contexte d'apparition**

- ASUS Zenbook UX3402 (CPU Intel Alder Lake / 12ᵉ gen, iGPU Intel `i915`).
- Fedora Workstation 44, noyau 7.0.x.

**Diagnostic**

- Cause : bug du driver `i915` au réveil en veille `s2idle`. Erreur visible dans
  les logs juste après le `PM: suspend exit` :
  ```
  i915 ... GUC: CT: Failed to process CT message (-ENOKEY)
  ```
  Le micro-contrôleur GPU (GuC) casse son canal de communication au resume.
- Les `ACPI BIOS Error (... TPL1, CFSP, AE_NOT_FOUND)` au boot sont du **bruit
  cosmétique** sans rapport — ne pas s'y fier.
- Le S3 « deep » est *déclaré* dans l'ACPI (`supports S0 S3 S4 S5`) mais **cassé**
  (ASUS ne valide que le s2idle / Modern Standby). Forcer `deep` aggrave : gel à
  tous les coups. **Ne pas l'utiliser comme contournement.**

**Commandes de diagnostic**

```bash
# Mode de veille supporté / actif
cat /sys/power/mem_sleep

# Cycles de veille et erreurs au resume sur le boot courant
journalctl -b 0 -k | grep -iE "PM: suspend entry|suspend exit|GUC|i915.*ERROR"

# Logs du boot précédent (utile si gel = pas de log écrit après le resume)
journalctl --list-boots
journalctl -b -1 -k | tail -40
```

**Solution (contournement)**

Désactiver le GuC du GPU Intel (retour au mode execlists, l'ancien chemin stable) :

```bash
sudo grubby --update-kernel=ALL --args="i915.enable_guc=0"
# puis reboot
```

- Impact : on perd GuC submission + SLPC (gestion fine de la conso GPU) + HuC
  (accélération de certains décodages vidéo protégés). **Négligeable** en usage
  dev / bureautique ; au pire quelques % d'autonomie GPU au repos.
- Le message `Setting dangerous option enable_guc - tainting kernel` est **bénin**
  (simple drapeau « paramètre module non-défaut »).

**Vérifier que c'est réglé** — faire 5-6 cycles veille/réveil (le bug est
intermittent), puis :

```bash
journalctl -b 0 -k | grep -iE "GUC|suspend exit"
# Attendu : des "suspend exit" propres, AUCUNE ligne "GUC".
```

**Annuler** (ex. si une future MAJ noyau corrige le bug en amont — à re-tester
après quelques montées de version) :

```bash
sudo grubby --update-kernel=ALL --remove-args="i915.enable_guc=0"
```

**Plan B** si le gel persiste : `i915.enable_dc=0` (désactive les états basse
conso de l'affichage), l'autre suspect classique des resume `s2idle`.

## ⚠️ Cas particulier : WiFi qui se coupe ~5s à intervalle régulier (Intel iwlwifi + multi-BSSID box)

**Symptôme** : la connexion WiFi du PC tombe pendant 4-10 secondes toutes les
15-30 minutes. **Les autres appareils (téléphone, console, etc.) ne sont pas
affectés** — la box émet correctement. Concerne les cartes Intel `iwlwifi` face à
une box exposant plusieurs BSSID pour le même SSID. (Remplace ci-dessous
`<TON_SSID>`, `<BSSID_STABLE>` et l'interface `<TON_IFACE>` — la tienne via
`ip link` ou `nmcli device`, souvent `wlo1`/`wlp*`.)

### Cause racine

Deux problèmes qui s'additionnent :

1. **La box expose plusieurs BSSID pour le même SSID** — typiquement un BSSID
   "principal" (MAC normale) et un BSSID "virtuel" (2e bit du 1er octet à 1 =
   "locally administered"). Selon la box, c'est un résidu de band-steering, un
   mode WPA3 transition, un mesh activé, un réseau invité, etc.
2. **Le driver `iwlwifi` (Intel) tente de roamer** entre ces deux BSSID et
   **rate régulièrement le 4-way handshake WPA** :
   ```
   <TON_IFACE>: deauthenticated from XX:XX:XX:XX:XX:XX (Reason: 15=4WAY_HANDSHAKE_TIMEOUT)
   ```
   → déconnexion le temps de retomber sur l'AP d'origine.

Les autres appareils (Android, iOS, consoles) ont des stacks WiFi qui tolèrent
mieux ces transitions et restent collés à un BSSID, d'où l'asymétrie.

### Diagnostic

```bash
# 1. Voir tous les BSSID du SSID — si plusieurs lignes avec même SSID, c'est le cas
nmcli -f BSSID,SSID,SIGNAL,CHAN,FREQ device wifi list --rescan yes | grep "<TON_SSID>"

# 2. Confirmer dans les logs noyau (remplace <TON_IFACE>)
journalctl -k --since "24 hours ago" | grep -iE "<TON_IFACE>|iwlwifi" | grep -iE "deauth|handshake|reset"

# 3. Logs NetworkManager (chercher "supplicant-timeout", "4way_handshake")
journalctl -u NetworkManager --since "24 hours ago" | grep -iE "disconnect|deauth|handshake"
```

Signes confirmant le diagnostic :
- Plusieurs BSSID pour le même SSID, **un avec MAC normale, un avec bit "locally administered"** (2e digit hexa du 1er octet pair vs impair)
- Logs avec `4WAY_HANDSHAKE_TIMEOUT` ou `supplicant-timeout`
- Power save peut être actif : `iw dev <TON_IFACE> get power_save` → `on`

### Fix (côté PC, le seul efficace dans ce cas)

**Verrouiller le profil de connexion sur le BSSID stable** (celui sur lequel le
PC s'associe avec succès dans les logs — généralement la MAC "normale") :

```bash
# Remplace <TON_SSID> et <BSSID_STABLE> (le BSSID à garder)
sudo nmcli connection modify "<TON_SSID>" 802-11-wireless.bssid <BSSID_STABLE>
sudo nmcli connection down "<TON_SSID>" && sudo nmcli connection up "<TON_SSID>"

# Vérification
nmcli -f 802-11-wireless.bssid connection show "<TON_SSID>"
iw dev <TON_IFACE> link | grep -i bssid
```

**Si ça ne suffit pas**, désactiver en plus le power save (cause secondaire) :
```bash
sudo nmcli connection modify "<TON_SSID>" 802-11-wireless-powersave 2  # 2 = disable
sudo nmcli connection up "<TON_SSID>"
```

**Pour annuler le verrou BSSID** plus tard :
```bash
sudo nmcli connection modify "<TON_SSID>" 802-11-wireless.bssid ""
```

### Pourquoi PAS de fix côté box ?

Sur certaines box (ex. modèles opérateur), le 2e BSSID est généré par le firmware
sans option pour le désactiver dans l'interface admin (l'IP admin de ta box, ex.
`192.168.x.1`). Seul un reset usine (sans garantie) ou un passage en mode bridge +
routeur perso permettrait de l'éliminer — overkill. **Sur d'autres box** (Freebox,
Livebox, etc.) il peut y avoir des options à désactiver : mesh, band steering, WiFi
invité, WPA3 transition. À vérifier d'abord. Mais dans le doute, le fix PC marche
partout et est totalement réversible.

### Si tu changes de carte WiFi / PC

Ce bug est spécifique à `iwlwifi` (Intel). Une carte AX/BE plus récente avec
firmware à jour, ou une carte non-Intel (MediaTek MT79xx, Qualcomm), peut ne
pas avoir le problème. Si après changement de PC tu n'as plus de coupures
sans avoir verrouillé de BSSID, c'est gagné.

## ⚠️ Cas particulier : Configuration clavier (fr+oss + shift-lock)

Le script force deux réglages via `gsettings` :

- **Layout `fr+oss`** : la variante "French (alt.)" / "Français — Variante" de
  l'AZERTY. Apporte les vrais guillemets français « », `œ`/`æ` via AltGr,
  `É`/`Ç` accessibles, plus quelques caractères utiles (espaces insécables,
  tirets cadratin, etc.) que l'AZERTY de base n'a pas.
- **Shift-Lock** (`caps:shiftlock`) : Caps Lock devient un *vrai* verrouillage
  Shift (= Maj permanente), pas juste un mode Majuscules. Très pratique en
  AZERTY pour taper une série de chiffres sans tenir Shift, ou pour taper
  EN MAJUSCULES.

```bash
# Ce que le script applique (avec idempotence) :
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'fr+oss')]"
gsettings set org.gnome.desktop.input-sources xkb-options "['caps:shiftlock']"
```

> ⚠️ Le script **écrase** les `xkb-options` existantes (option B choisie au
> moment de l'écriture du script : "force aussi le layout"). Si tu ajoutes
> d'autres options manuellement (genre `terminate:ctrl_alt_bksp`), le
> prochain run du script les écrasera. À adapter si besoin.

## ⚠️ Cas particulier : Extensions GNOME (Clipboard Indicator + AppIndicator)

Le script installe **`gnome-extensions-cli`** (alias `gext`) via `pipx`, puis
gère deux familles d'extensions :

1. **Clipboard Indicator** — installée *et* activée via gext depuis
   extensions.gnome.org (EGO). Historique du presse-papier dans la barre du
   haut, raccourci par défaut `Super+V`.
2. **AppIndicator Support** — activée *seulement* via gext, car l'extension
   elle-même est fournie par le paquet dnf `gnome-shell-extension-appindicator`
   (voir plus bas le pourquoi). C'est elle qui fournit le systray dont Dropbox
   (et d'autres apps) a besoin pour afficher son icône de statut sous GNOME.

**Points techniques importants** :

- **`pipx install ... --system-site-packages`** : le flag est obligatoire.
  Sans lui, l'env virtuel pipx ne voit pas PyGObject (les bindings GTK
  Python du système) → gext plante au démarrage parce qu'il ne peut pas
  parler à GNOME Shell via DBus.
- **Limitation Wayland (logout/login obligatoire)** : sur Wayland (défaut
  Fedora 44), GNOME Shell ne recharge pas sa liste d'extensions à chaud.
  Donc au 1er run du script sur un PC fresh :
  - `gext install <id>` réussit (l'extension est copiée sur disque)
  - `gext enable <uuid>` échoue silencieusement (le shell ne voit pas
    encore l'extension)
  - Le script log un `[!] WARN` non-bloquant qui te dit la marche à suivre :
    déconnecte/reconnecte ta session, puis relance `./setup.sh` (idempotent,
    il complétera juste l'enable).
  - Vaut pour les **deux** familles (Clipboard Indicator ET AppIndicator).
- **Install (EGO via gext) vs enable seul (paquet dnf)** : deux cas distincts,
  d'où deux tableaux dans `setup.sh`.
  - La plupart des extensions ne sont **pas** packagées par Fedora ; elles
    sont distribuées via [extensions.gnome.org](https://extensions.gnome.org).
    `gext` parle directement à ce service via DBus, pareil que le site web
    mais scriptable. C'est le cas de Clipboard Indicator → `GNOME_EXTENSIONS`
    (install + enable).
  - **MAIS** certaines extensions **sont** packagées par Fedora, dont
    AppIndicator (`gnome-shell-extension-appindicator`). Pour celles-là, on
    préfère le **paquet dnf** : il est maintenu en phase avec la version de
    GNOME du système (GNOME 50 sur F44). Tirer la même extension depuis EGO
    risquerait une version désynchronisée, voire un conflit avec la version
    dnf. On se contente donc de l'**activer** → `GNOME_EXTENSIONS_ENABLE_ONLY`
    (enable seul, pas de `gext install`).
- **Check de présence robuste (piège évité)** : pour les extensions
  `enable_only`, le script vérifie la **présence du dossier sur disque**
  (`/usr/share/gnome-shell/extensions/<uuid>`) et **pas** `gnome-extensions
  info`. Raison : au 1er run pré-logout, le Shell n'a pas encore scanné
  `/usr/share`, donc `gnome-extensions info` échouerait alors que le paquet
  dnf est bel et bien installé → faux négatif "paquet manquant" qui sauterait
  l'activation à tort.

**Pour ajouter d'autres extensions** :
- Depuis EGO : éditer le tableau `GNOME_EXTENSIONS` dans `setup.sh`, au format
  `"id:uuid:nom_affiche"` (id et uuid trouvables dans l'URL et la fiche de
  chaque extension sur extensions.gnome.org).
- Fournie par un paquet dnf : ajouter le paquet `gnome-shell-extension-*` à
  `DNF_PACKAGES`, puis son uuid à `GNOME_EXTENSIONS_ENABLE_ONLY` au format
  `"uuid:nom_affiche"`.

## ⚠️ Cas particulier : JetBrains IDE (Toolbox vs Flatpak)

Le Flatpak `com.jetbrains.IntelliJ-IDEA-Community` est un wrapper non-officiel
maintenu par la communauté. Il fonctionne, **mais** comme tout Flatpak il
tourne dans un sandbox isolé du host :

- ❌ Ne voit pas les JDK Temurin installés via SDKMAN dans `~/.sdkman/candidates/java/`
- ❌ Ne voit pas Maven (lui aussi via SDKMAN)
- ❌ Le terminal intégré n'a pas accès au shell host (`PATH`, alias, fonctions bash)
- ❌ Les processus que tu lances (`mvn`, `java`, etc.) tournent dans le sandbox
- ⚠️ Workarounds possibles (`--talk-name=org.freedesktop.Flatpak`,
  `FLATPAK_ENABLE_SDK_EXT=openjdk25`, `flatpak-spawn --host bash` dans le
  terminal), mais c'est percer des trous dans le sandbox

Pour un workflow Java/Spring Boot avec SDKMAN, c'est rédhibitoire. Le script
installe donc **JetBrains Toolbox** (outil officiel JetBrains) en natif, à la
place du Flatpak :

- ✅ Install user-space dans `~/.local/share/JetBrains/Toolbox/`
- ✅ Pas de sandbox : accès complet au home, donc voit SDKMAN, Maven, shell
- ✅ Gère plusieurs IDE JetBrains côte à côte (IDEA Community/Ultimate,
  DataGrip, PyCharm, WebStorm, etc.)
- ✅ Auto-update intégré (pas de relance du script nécessaire)
- ✅ Toolbox 1.25+ génère par défaut les shell-scripts (commande `idea` dispo
  dans le terminal)

> 💡 **Premier lancement après l'install par le script** : ouvre Toolbox
> depuis GNOME Activities (l'icône est déjà là grâce au `.desktop` créé par
> le script). Login JetBrains, puis "Install" sur IntelliJ IDEA Community
> depuis l'UI. Le binaire est à
> `~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox`.

## ⚠️ Cas particulier : Flathub user vs system scope

Depuis Fedora 38, **Flathub est pré-configuré en `--system`** sur Workstation
(via le paquet `flatpak-flathub-config`). Or les remotes `--user` et `--system`
sont des **espaces de noms séparés** : un remote présent en system n'est pas
visible depuis user.

Comme le script installe ses Flatpaks en `--user` (cohérent avec le reste :
SDKMAN, npm globals, etc. sont aussi en user-space), il **doit** explicitement
ajouter le remote en `--user`. Sinon :

```
flatpak install --user [...] flathub com.usebruno.Bruno
  → error: No remote refs found for 'flathub'
```

Le script appelle donc systématiquement (idempotent grâce à `--if-not-exists`) :

```bash
flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
```

> 💡 **Diagnostic en cas d'échec massif sur tous les Flatpaks** : vérifier la
> sortie de `flatpak remotes --user`. Si elle est vide alors que
> `flatpak remotes --system` montre flathub, c'est ce problème de scope.

## ⚠️ Cas particulier : Podman vs Docker

Podman remplace Docker engine sur Fedora :

- **CLI compat** : le paquet `podman-docker` installe un alias `docker` → `podman`.
  Tu peux taper `docker run hello-world`, c'est en fait Podman qui exécute.
- **Rootless par défaut** : pas besoin d'être root ou dans le groupe docker.
- **Pas de daemon** : Podman lance les containers via `runc` directement,
  pas via un process serveur.
- **Socket Docker-compatible** : `systemctl --user enable --now podman.socket`
  expose un socket à `$XDG_RUNTIME_DIR/podman/podman.sock` que les outils
  type Testcontainers, docker-compose, Maven docker plugin peuvent utiliser
  via `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`.

Les `Dockerfile` du Projet 9 (microservices médicaux) fonctionnent tels quels
avec `podman build`. `docker-compose` fonctionne via `podman-compose` (déjà
dans les paquets dnf) ou via le plugin compose officiel pointé sur le socket
Podman.

> 💡 Si un truc plante mystérieusement, vérifier d'abord : `echo $DOCKER_HOST`
> (doit pointer vers le socket Podman) et `systemctl --user status podman.socket`.

## ⚠️ Cas particulier : MongoDB sur Fedora

MongoDB **n'est pas packagé dans les repos officiels Fedora** (problèmes de
licence SSPL). Le script ajoute le repo MongoDB officiel pour RHEL 9, qui
fonctionne sur Fedora en pratique.

> ⚠️ MongoDB ne **garantit pas** la compatibilité Fedora. Cf. issue
> [MongoDB SERVER-58871](https://jira.mongodb.org/browse/SERVER-58871).
> Si une mise à jour casse quelque chose, la solution officielle est de
> pinner sur une version stable.

Le script installe la **8.0** (version stable actuelle, mai 2026).

## ⚠️ Cas particulier : Antigravity (post Google I/O 2026)

**Mise à jour majeure le 19 mai 2026.** À l'origine (novembre 2025),
Antigravity était un IDE AI standalone basé sur VS Code. Depuis Google I/O
2026, la marque **Antigravity** désigne une plateforme à 4 surfaces sur un
seul agent harness partagé :

| Surface | Type | Statut script |
|---|---|---|
| **Antigravity 2.0** | App desktop (orchestrateur d'agents, plus un IDE) | Manuel |
| **Antigravity CLI** | Terminal (binaire `agy`, écrit en Go) | ✅ Automatisé (curl install) |
| **Antigravity SDK** | Programmation d'agents custom | Pas concerné |
| **Antigravity IDE** | L'IDE historique de novembre 2025 | Manuel |

**Conséquence pratique** pour ce script :

- **Antigravity CLI** est installé automatiquement via le script curl officiel.
  Il **remplace Gemini CLI**, qui s'arrête le 18 juin 2026 pour les comptes
  consumer.
- **Antigravity IDE** (la version "VS Code-like") reste en install manuelle.
  Un repo RPM tiers existe à
  `https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm`
  mais avec `gpgcheck=0` et `dev` dans le chemin → **on attend un canal officiel
  signé** avant de l'intégrer au script. En attendant :
  - DL manuel sur <https://antigravity.google/download>
  - Décompresser dans `~/Apps/` ou `/opt/`
  - Créer un `.desktop` dans `~/.local/share/applications/`

## ⚠️ Cas particulier : npm en user-space (sans sudo)

Sur Linux, `sudo npm install -g <pkg>` est une **mauvaise pratique** (sécurité,
permissions, conflits). Le script configure `npm` pour installer ses globals
dans `~/.npm-global` :

```bash
npm config set prefix ~/.npm-global
# + export PATH="$HOME/.npm-global/bin:$PATH" dans .bashrc
```

Du coup, plus besoin de sudo pour `npm install -g`. Si tu réinitialises ton
home, tu perds ces paquets — pas grave, le script les réinstalle.

## Logiciels installés (pour référence)

### Via dnf (script — repos Fedora + RPM Fusion + tiers)

| Catégorie | Paquet |
|---|---|
| Dev tools | `git`, `make`, `gcc`, `gcc-c++`, `curl`, `wget`, `zip`, `unzip`, `jq`, `ripgrep`, `fd-find`, `tree`, `tmux`, `htop`, `openssl`, `pipx` (pour gnome-extensions-cli) |
| Biométrie | `fprintd`, `fprintd-pam` (PAM empreinte), `tpm2-tools` (diag TPM) |
| Hardware optim (vendor-neutre, statique) | `libva-utils`, `libavcodec-freeworld`, `powertop` |
| Hardware optim (selon GPU, dynamique) | Intel : `intel-media-driver`, `libva-intel-driver`, `intel-gpu-tools`, `thermald` (si CPU Intel) — AMD : swap `mesa-va-drivers-freeworld` + `mesa-vdpau-drivers-freeworld`, `radeontop` — NVIDIA : manuel (`akmod-nvidia`…) |
| Plugin DNF | `dnf5-plugins` (installé en amont par le script, requis pour `dnf config-manager`) |
| Éditeur | VSCode (`code`) — voir note ci-dessous |
| Navigateur | Google Chrome (`google-chrome-stable`) |
| Mail | Thunderbird |
| Office | LibreOffice |
| DB servers | `postgresql-server`, `postgresql-contrib`, `mariadb-server`, `mongodb-org` (tire `mongodb-mongosh` en dépendance) |
| Containers | `podman`, `podman-compose`, `podman-docker`, `buildah`, `skopeo` |
| Node.js | `nodejs`, `npm` |
| Python | `python3`, `python3-pip` |
| Cloud | `nautilus-dropbox` (tire Dropbox proprement, via RPM Fusion nonfree) + `libappindicator-gtk3` (lib requise pour l'icone systray Dropbox) |
| Loisirs | `steam` (via RPM Fusion nonfree) |
| GNOME | `gnome-tweaks`, `gnome-shell-extension-appindicator` (support systray AppIndicator — indispensable pour l'icone Dropbox sous GNOME) |

> 💡 **Éditeur de texte sur F44** : `gnome-text-editor` (« Text Editor ») est
> l'éditeur par défaut de GNOME depuis GNOME 42 (mars 2022) et est déjà
> pré-installé sur Fedora Workstation 44 (GNOME 50). C'est celui que j'utilise,
> donc rien à installer. `gedit` a été retiré du script le 2026-06-11 (je ne
> m'en servais pas).

### Via Flatpak / Flathub (script)

| App | Application ID |
|---|---|
| Bruno | `com.usebruno.Bruno` |
| Stremio | `com.stremio.Stremio` |
| MongoDB Compass | `com.mongodb.Compass` |
| DBeaver Community | `io.dbeaver.DBeaverCommunity` |
| GIMP | `org.gimp.GIMP` |
| Amberol (lecteur audio, boucle une piste) | `io.bassi.Amberol` |
| **Extension VAAPI Intel (runtime 24.08)** | `org.freedesktop.Platform.VAAPI.Intel//24.08` |
| **Extension VAAPI Intel (runtime 25.08)** | `org.freedesktop.Platform.VAAPI.Intel//25.08` |

> ⚠️ **IntelliJ IDEA Community a été retiré de cette liste** (2026-05-23) :
> le Flatpak est sandboxé et ne voit pas les JDK Temurin installés via SDKMAN
> dans `~/.sdkman/`, ni Maven, ni le shell host. Galère pour un workflow
> Java/Spring Boot. Remplacé par JetBrains Toolbox (install native), voir
> section suivante.

### Via tarball officiel JetBrains (script)

- **JetBrains Toolbox** — `https://data.services.jetbrains.com/products/download?platform=linux&code=TBA`
  - Endpoint de redirect officiel, pointe toujours sur la dernière version stable
  - Extraction dans `~/.local/share/JetBrains/Toolbox/`
  - Depuis Toolbox 3.x (mars 2026), le tarball met tout sous `bin/`, donc le
    binaire final est à `~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox`
  - Le script crée aussi un `.desktop` pour l'icône GNOME immédiate
  - Lance Toolbox → login JetBrains → install IDEA Community / DataGrip / etc.
    depuis l'UI Toolbox

### Via SDKMAN (script)

- Java Temurin 17, 21, 25 (dernière version de chaque major, résolu dynamiquement)
- Maven

### Via npm global (script, en user-space)

- `@openai/codex`
- `@angular/cli` (fournit `ng`) — tooling de dev front Angular, pas une CLI IA.
  Installé en latest (non pinné), au même endroit que les autres globals
  (`~/.npm-global/bin`), donc `ng` est sur le PATH après reload du shell.

> **Claude Code n'est plus installé via npm** (2026-06-19). Il est posé en **natif**
> par `bootstrap.sh` (`curl -fsSL https://claude.ai/install.sh | bash`) : pas de
> dépendance Node, auto-update intégré. Garder aussi le npm créerait deux binaires
> `claude` dans le PATH → source unique = le natif. `install_npm_globals()` retire
> l'ancien `@anthropic-ai/claude-code` npm s'il traîne (machines déjà provisionnées).

> ⚠️ **`@google/gemini-cli` a été retiré** suite à Google I/O 2026 (19 mai 2026).
> Gemini CLI est déprécié pour les comptes consumer (Google AI Pro/Ultra +
> tier gratuit) avec arrêt de service le **18 juin 2026**. Il est remplacé par
> Antigravity CLI, installé via curl (voir section suivante). Les comptes
> Enterprise Code Assist + utilisateurs API key gardent Gemini CLI indéfiniment.

### Via installer curl officiel (script)

- **Antigravity CLI** — `curl -fsSL https://antigravity.google/cli/install.sh | bash`
  - Binaire installé : `agy`
  - Successeur de Gemini CLI (cf. note ci-dessus), écrit en Go
  - Partage le même agent harness que l'app desktop Antigravity 2.0

### Via pipx + gnome-extensions-cli (script)

- **`gnome-extensions-cli`** (`gext`) installé via pipx avec `--system-site-packages`
- Extensions GNOME installées :
  - **Clipboard Indicator** (`clipboard-indicator@tudmotu.com`, ID 779)
    — historique du presse-papier, raccourci `Super+V` par défaut

### Manuel (non scriptable)

- **Antigravity IDE** (en attendant le nouveau package stable)
- **Marvin** (https://amazingmarvin.com — AppImage)
- **Freedom** (https://freedom.to)
- **Mem.ai** (https://mem.ai — web ou Electron)

## Pourquoi cette répartition ?

- **dnf** par défaut : natif Fedora, intégration parfaite avec systemd, gestion
  centralisée des updates avec `dnf upgrade`.
- **RPM Fusion** pour les paquets exclus de Fedora pour raisons de licence
  (Steam, certains codecs).
- **Repos tiers** (Google, Microsoft, MongoDB) pour avoir les versions
  officielles à jour, plutôt que les forks Fedora.
- **Flatpak/Flathub** pour les apps qui n'ont pas de RPM officiel propre,
  ou dont la version Flathub est mieux maintenue (Bruno, DBeaver, Compass).
  Sandbox bonus — mais c'est aussi son point faible (cf. cas IntelliJ qui a
  basculé vers JetBrains Toolbox).
- **JetBrains Toolbox** pour les IDE JetBrains (IDEA, DataGrip, etc.) :
  install native, accès au home complet (donc visibilité sur les JDK SDKMAN,
  Maven, le shell host), auto-update intégré. Le tarball est récupéré via
  l'endpoint de redirect officiel JetBrains.
- **SDKMAN** pour le multi-JDK Temurin (équivalent fonctionnel de Scoop sur
  Windows). Permet aussi `sdk install gradle`, `sdk install springboot`,
  `sdk env` pour des configs par projet, etc.
- **npm user-space** (`~/.npm-global`) pour éviter `sudo npm` (anti-pattern).
- **Podman** : Fedora pousse Podman depuis Fedora 35+. Mêmes capacités que
  Docker engine pour 99% des cas, plus sûr (rootless), plus simple
  (daemon-less). `podman-docker` rend la transition transparente.

## Maintenance (1× par mois)

```bash
# Système + repos tiers
sudo dnf upgrade --refresh

# Flatpak (incluant runtimes)
flatpak update

# SDKMAN (lui-meme + candidats)
sdk selfupdate
sdk update                  # met a jour la liste des versions dispo
# Pour passer a une nouvelle Temurin :
#   sdk list java | grep tem
#   sdk install java <nouvelle>
#   sdk default java <nouvelle>

# npm (codex ; Claude Code n'est plus ici -> natif auto-updaté)
npm update -g

# pipx (gnome-extensions-cli)
pipx upgrade-all

# Extensions GNOME (toutes celles installées via gext)
gext update

# Firmware (BIOS, microcode, etc. — sources LVFS)
sudo fwupdmgr refresh && sudo fwupdmgr update
```

Pour Antigravity IDE, Marvin, Freedom, Mem.ai : MAJ via l'app elle-même
(auto-update intégré). **Claude Code** (natif) s'auto-update aussi en arrière-plan.

> ⚠️ **Après une MAJ firmware**, si la liaison LUKS+TPM est active (PCR 0+7), le
> boot redemandera la passphrase → ré-enrôler le TPM (cf. section « Biométrie +
> déverrouillage TPM »).

## Avant de quitter ce PC (migration future)

Capturer l'état pour mettre à jour `setup.sh` avant de wipe :

```bash
# Paquets dnf installes explicitement (pas les deps)
dnf repoquery --userinstalled --queryformat '%{name}\n' > dnf-current.txt

# Flatpak
flatpak list --app --columns=application > flatpak-current.txt

# SDKMAN
sdk current > sdkman-current.txt
ls ~/.sdkman/candidates/java/ > sdkman-jdks.txt

# Antigravity CLI (binaire 'agy', installé hors npm)
command -v agy && agy --version > antigravity-cli-current.txt 2>&1 || true

# npm globals
npm list -g --depth=0 > npm-current.txt

# Extensions GNOME (UUIDs + état activé/désactivé)
gext list -a > gnome-extensions-current.txt

# Settings clavier GNOME (au cas où tu en ajoutes manuellement)
{
    echo "sources: $(gsettings get org.gnome.desktop.input-sources sources)"
    echo "xkb-options: $(gsettings get org.gnome.desktop.input-sources xkb-options)"
} > gnome-keyboard-current.txt
```

Diff avec ce qui est dans `setup.sh` → décider quoi ajouter / abandonner.

## Compatibilité

Testé sur **Fedora Workstation 44** (avril 2026, dnf5, GNOME 50).

Devrait fonctionner sur :
- Fedora 43 (dnf5 par défaut depuis F41)
- Fedora 41+ (avec ajustements mineurs)

Pour Fedora 40 et antérieur (dnf4) : `dnf config-manager` a une syntaxe
différente (`--add-repo` au lieu de `addrepo`). À adapter si besoin.

---

## Changelog du script

- **2026-06-20** — Création de `~/.gitignore_global` :
  - **Nouveau** : `configure_gitignore_global()` (appelée dans `main()` juste après
    `configure_git`) crée le fichier pointé par `core.excludesfile`, jusqu'ici jamais
    posé → l'option pointait dans le vide. Contenu de base : OS (`.DS_Store`…), IDE
    (`.idea/`, `*.iml`, `.vscode/`…), Java/Maven (`target/`, `*.class`), Node/Angular
    (`node_modules/`, `.angular/cache/`), `.env`/secrets (avec exceptions
    `!*.env.example/.exemple/.template`), logs.
  - **Stratégie « créer si absent »** (pas d'écrasement) → préserve d'éventuels ajouts
    manuels ; conséquence : une évolution du contenu de base ne se propage pas sur une
    machine déjà provisionnée. Heredoc à délimiteur quoté, chemin `"$HOME/..."` (le
    `~` ne s'étend pas entre guillemets), appel **hors** garde git (simple fichier).
  - **Volontairement EXCLU** : `*.properties` (casserait `application.properties` /
    Spring) et `env*` (casserait `environment.ts` / Angular) — trop larges en global.
  - Contenu **dupliqué à l'identique** dans `setup.ps1` (dossiers OS autonomes).

- **2026-06-19** — Généralisation « tout nouveau PC » + biométrie/TPM + bootstrap :
  - **Généralisation (rien en dur)** : retrait d'un alias git spécifique à un
    projet pro ; détection GPU au runtime (`detect_gpu_vendors()` par vendor
    ID PCI) → `install_hardware_packages()` pose les bons paquets VA-API (Intel iHD +
    i965 / AMD `dnf swap` freeworld + radeontop / NVIDIA manuel) ; `thermald`
    conditionné au CPU Intel ; extensions Flatpak VAAPI par vendor (Intel/nvidia ;
    rien pour AMD). Paquets GPU Intel sortis de `DNF_PACKAGES` statique. Doc
    anonymisée (WiFi : SSID/BSSID/box/interface en placeholders ; OLED « si OLED » ;
    LVFS multi-constructeurs).
  - **Biométrie** : `configure_fingerprint()` (run normal) — détection capteur
    générique + `authselect enable-feature with-fingerprint` (idempotent). Enrôlement
    manuel `fprintd-enroll` avec warning ELAN conditionnel. Paquets `fprintd`,
    `fprintd-pam`, `tpm2-tools` ajoutés.
  - **Déverrouillage TPM (opt-in)** : `enroll_luks_tpm()` via `./setup.sh
    --enroll-tpm` — `systemd-cryptenroll` PCR 0+7 + PIN, module dracut `tpm2-tss`,
    `/etc/crypttab` (`tpm2-device=auto,tpm2-pin=yes`), `dracut --regenerate-all`.
    Keyslot passphrase conservé en fallback. PCR 0 → ré-enrôlement après MAJ BIOS.
  - **Bootstrap + Claude Code** : nouveau `bootstrap.sh` (git + clone HTTPS dans
    `~/code` + Claude Code **natif**). `@anthropic-ai/claude-code` retiré de
    `NPM_GLOBALS` (source unique = natif auto-updaté) + cleanup du npm orphelin.
  - **Self-logging** : le run est capturé via `script(1)` (TTY préservé) dans
    `~/.local/state/workstation-setup/last-run.log` (+ ligne `EXIT=`) — c'est ce que
    Claude Code lit pour réparer les erreurs.

- **2026-06-15** — Alias shell (`dc` + `mvnw`) dans `~/.bashrc` :
  - **Nouveau** : `configure_shell_aliases()` ajoute l'alias `dc='docker
    compose'` et une fonction `mvnw()` (message clair si `./mvnw` absent du
    projet). Appelée dans `main()` après `configure_git`. Append idempotent
    comme les autres écritures `.bashrc` (PATH npm, `DOCKER_HOST`), mais gardé
    par un **marqueur-commentaire unique** (`# workstation-setup: shell aliases`)
    plutôt que par `grep -qxF` sur une ligne exacte : ça protège le **bloc
    entier** (alias + fonction multi-lignes) d'une réinsertion.
  - **Origine** : portage du profil PowerShell Windows. **Volontairement NON
    porté** car déjà natif sur Fedora : `posh-git` (→ `bash-completion` déjà
    installé), l'encodage UTF-8 console (déjà le défaut), et l'alias `mvnw` pur
    (`./mvnw` est exécutable nativement — on garde quand même la fonction pour le
    message d'erreur). Une fonction de déploiement propre à un projet pro n'est
    pas portée (contenu privé, hors repo).

- **2026-06-15** — Ajout d'Angular CLI :
  - **Nouveau** : `@angular/cli` ajouté à `NPM_GLOBALS` (fournit `ng`). Installé en
    user-space dans `~/.npm-global/bin` comme les autres globals, donc `ng` est sur
    le PATH après reload du shell. Aucune nouvelle fonction : la boucle
    `install_npm_globals()` gère install + skip-si-présent + log d'échec.
  - **Choix `latest` (non pinné)** : cohérent avec les autres npm globals
    (claude-code, codex) ; `npm update -g` suffit à suivre les majors.
  - **Éditeur** : on reste sur **VSCode** (déjà installé, excellent pour Angular).
    IDEA Community ne gère pas Angular/TS (feature Ultimate/WebStorm) → pas de
    changement d'IDE. Étape manuelle ajoutée : extension VSCode *Angular Language
    Service*.

- **2026-06-14** — Ajout de GIMP (via Flatpak) :
  - **Nouveau** : `org.gimp.GIMP` ajouté à `FLATPAK_APPS`. Aucune nouvelle
    fonction : la boucle idempotente de `install_flatpak_apps()` gère install +
    skip-si-présent + log d'échec.
  - **Choix Flatpak (vs RPM dnf `gimp`)** : le paquet Flathub est maintenu par
    l'équipe GIMP et suit la dernière version, là où le RPM Fedora peut être en
    retard. Le sandbox est sans impact pour un éditeur d'images (accès fichiers
    via portals). Note : ce choix n'est PAS ajouté à la section « Pourquoi cette
    répartition ? » car celle-ci justifie Flatpak par l'absence de RPM propre —
    or GIMP a un bon RPM natif ; ici le motif est la fraîcheur de version.

- **2026-06-11** — Automatisation du `.gitconfig` + retrait de gedit :
  - **Nouveau** : `configure_git()` ecrit mes options + alias Git via
    `git config --global` (une commande par cle, idempotent par ecrasement).
    N'ecrit PAS l'identite (`user.name`/`user.email`) -> reste manuelle, et la
    fonction est non destructive (ne touche qu'aux cles gerees).
  - **Adaptations vs config Windows** :
    - `core.editor = "idea --wait"` (IntelliJ via launcher Toolbox ; `--wait`
      bloque jusqu'a fermeture de l'onglet). NB : `idea` n'est dispo qu'apres
      1er lancement Toolbox + install IDEA, mais l'editeur n'est invoque qu'au
      moment d'un commit -> sans impact a l'install.
    - **Pas de `safe.directory`** : les entrees Windows (`C:/Users/...`) sont des
      chemins invalides sur Linux (et du contexte boulot).
  - **Retrait de `gedit`** de `DNF_PACKAGES` : je n'utilise que
    `gnome-text-editor` (« Text Editor »), deja pre-installe sur F44.
  - Checklist manuelle « Git config » -> ne reste que l'identite a definir.

- **2026-05-31** — Fix icone systray Dropbox sous GNOME (AppIndicator) :
  - **Symptome** : au lancement de Dropbox, message "votre environnement de
    bureau ne permet pas d'afficher l'icone". Dropbox synchronisait
    correctement, mais aucune icone de statut dans la barre du haut.
  - **Cause** : GNOME ne fournit pas de systray nativement ; l'icone Dropbox
    repose sur AppIndicator (cf. doc Dropbox Linux). L'extension
    `gnome-shell-extension-appindicator` etait bien presente (tiree en dep)
    mais jamais ACTIVEE (`Enabled: No`, `State: INITIALIZED`).
  - **Fix** :
    - Ajout de `libappindicator-gtk3` + `gnome-shell-extension-appindicator`
      a `DNF_PACKAGES` (presence garantie, plus de dependance implicite).
    - Nouvelle liste `GNOME_EXTENSIONS_ENABLE_ONLY` + boucle "enable seul"
      (2bis) dans `install_gnome_extensions()`. On NE fait PAS `gext install`
      sur cette extension : le paquet dnf suit deja la version GNOME du
      systeme, alors qu'EGO pourrait servir une version desynchronisee de
      GNOME 50.
    - Check de presence base sur le DOSSIER disque (`/usr/share/gnome-shell/
      extensions/<uuid>`), pas sur `gnome-extensions info` : ce dernier
      echoue au 1er run pre-logout (Shell pas encore rescanne) -> faux negatif
      "paquet manquant" qui aurait saute l'activation a tort.
  - **Gotcha Wayland** (identique a Clipboard Indicator) : `gext enable` echoue
    tant que la session n'a pas ete relancee. Logout/login puis relance du
    script (idempotent) -> activation completee.

- **2026-05-24** — Ajout optimisations hardware (Intel Iris Xe + Zenbook OLED) :
  - **Nouveau** : `configure_hardware_optimization()` enable `thermald.service`
    (débridage perf + gestion thermique sur Tiger Lake+) et installe les
    extensions Flatpak `org.freedesktop.Platform.VAAPI.Intel//24.08` et
    `//25.08` (pour que Stremio et autres apps Flatpak vidéo puissent décoder
    en HW).
  - **Ajouts paquets dnf** :
    - `intel-media-driver` : driver iHD VA-API pour Iris Xe (Broadwell+).
    - `libavcodec-freeworld` + `mesa-va-drivers-freeworld` (RPM Fusion
      nonfree) : codecs H.264/H.265 patentés, indispensables pour exploiter
      le HW decode sur les fichiers du monde réel.
    - `libva-utils` (`vainfo`), `intel-gpu-tools` (`intel_gpu_top`),
      `powertop` : outils de vérification et profilage.
    - `thermald` : daemon thermique Intel (complémentaire de PPD).
  - **Nouvelle section** "Cas particulier : Optimisations hardware (Iris Xe +
    Zenbook OLED)" qui documente : VA-API, thermald, powertop, fwupd, et
    les recommandations OLED (dark mode, blank screen, Hide Top Bar).
  - **Décisions** : on garde `power-profiles-daemon` (défaut Fedora) et on
    n'installe **pas** TLP (conflit avec PPD). Pas non plus de gestion
    `tuned` (idem). Firefox & Chrome HW decode sont déjà activés par défaut
    sur Fedora 44 → rien à faire côté browsers.

- **2026-05-24** — Ajout config clavier (fr+oss + shift-lock) + extensions GNOME :
  - **Nouveau** : `configure_keyboard()` force le layout `fr+oss` (French alt.)
    et active `caps:shiftlock` (Caps Lock = vrai verrouillage Shift). Très
    pratique en AZERTY pour taper des séries de chiffres.
  - **Nouveau** : `install_gnome_extensions()` installe `gnome-extensions-cli`
    (`gext`) via pipx avec `--system-site-packages` (flag obligatoire sinon
    PyGObject inaccessible → gext plante). Puis installe Clipboard Indicator
    (`clipboard-indicator@tudmotu.com`, ID 779).
  - **Wayland gotcha** : `gext enable` échoue tant que la session GNOME n'a
    pas été redémarrée (Wayland ne recharge pas les extensions à chaud). Le
    script `log_warn` non-bloquant et indique de relancer `./setup.sh` après
    logout/login. Idempotent : le 2ème run complétera l'enable.
  - **Ajouts paquets** : `pipx` ajouté à `DNF_PACKAGES`. Nouvelle commande
    de maintenance : `pipx upgrade-all` + `gext update`.

- **2026-05-23** — Bugfix idempotence `.desktop` Toolbox :
  - **Symptôme** : sur 2ème run, icône JetBrains Toolbox absente de GNOME
    Activities alors que le script reportait "Toolbox déjà installé / tout OK".
  - **Cause** : la fonction `install_jetbrains_toolbox()` avait un early
    `return` dès que le binaire existait, ce qui shuntait aussi la création
    du `.desktop`. Sur le 1er run post-bugfix tarball 3.x, le binaire était
    déjà extrait par l'exécution précédente mais sans `.desktop` (car le
    1er run avait échoué avant cette étape) → état permanent incomplet.
  - **Fix** : séparer les deux étapes en 2 blocs idempotents indépendants.
    Le `.desktop` est désormais (re-)écrit à chaque run même quand le binaire
    est déjà là. Bonus : ajout d'un appel à `update-desktop-database` pour
    que l'icône apparaisse sans devoir se déconnecter/reconnecter.
  - **Leçon** : un early-return dans une fonction "install" est suspect dès
    que la fonction a plusieurs effets de bord. Mieux vaut un check par
    effet de bord.

- **2026-05-23** — Bugfixes idempotence : PostgreSQL permissions + Toolbox 3.x :
  - **Bug 1 (PostgreSQL)** : `[[ -f /var/lib/pgsql/data/PG_VERSION ]]` exécuté
    en user normal renvoyait FALSE par **permission denied** (le dossier
    `/var/lib/pgsql/data/` est en mode 700 owned by postgres). Conséquence :
    sur tout 2ème run du script, l'idempotence était cassée, postgresql-setup
    tentait de réinitialiser un cluster déjà initialisé → erreur
    "Data directory not empty".
    - **Fix** : utiliser `sudo test -f` pour traverser le dossier.
    - **Bonus** : sortie de `postgresql-setup --initdb` capturée dans un log
      file (au lieu de `>/dev/null`), pour qu'un futur échec soit débuggable.
  - **Bug 2 (Toolbox)** : depuis Toolbox 3.x (mars 2026, ajout de `jetbrainsd`
    daemon), le tarball place tout sous `bin/`. Avec `--strip-components=1`,
    le binaire se retrouve à `$install_dir/bin/jetbrains-toolbox`, pas
    `$install_dir/jetbrains-toolbox`. Mon check d'existence cherchait à
    l'ancienne place → faux échec "binary missing after extract".
    - **Fix** : check + `.desktop` mis à jour vers `bin/jetbrains-toolbox`.
    - **Bonus** : `.desktop` pointe maintenant sur `bin/toolbox-tray-color.png`
      comme icône (fourni par le tarball) au lieu du nom générique
      "jetbrains-toolbox" qui n'était jamais résolu par GNOME.

- **2026-05-23** — Remplacement Flatpak IntelliJ → JetBrains Toolbox :
  - **Symptôme** : au 1er lancement du Flatpak IntelliJ, écran de bienvenue
    "running inside a container... not able to access SDKs on your host
    system". IDEA ne voit pas les JDK Temurin de SDKMAN, ni Maven, ni le
    shell host.
  - **Cause** : Flatpak sandboxe par design, et le wrapper IntelliJ Flathub
    est non-officiel.
  - **Fix** : retrait de `com.jetbrains.IntelliJ-IDEA-Community` de
    `FLATPAK_APPS`, ajout d'une nouvelle fonction `install_jetbrains_toolbox()`
    qui DL le tarball via l'endpoint redirect officiel
    (`?platform=linux&code=TBA`), extraction dans
    `~/.local/share/JetBrains/Toolbox/`, création d'un `.desktop` pour
    l'icône GNOME. Toolbox bootstrap lui-même au 1er lancement.
  - **Note** : ajout d'une section "Cas particulier : JetBrains IDE
    (Toolbox vs Flatpak)" qui documente la décision.
  - **Action manuelle** sur un PC déjà provisionné :
    ```bash
    flatpak uninstall --user -y com.jetbrains.IntelliJ-IDEA-Community
    flatpak uninstall --user --unused -y
    ./setup.sh    # idempotent : installera juste Toolbox
    ```

- **2026-05-23** — Bugfix Flathub user/system scope :
  - **Bug rencontré** : sur un PC fraîchement provisionné Fedora Workstation 44,
    les 5 installs Flatpak (Bruno, Stremio, IntelliJ, Compass, DBeaver) ont
    toutes échoué avec `error: No remote refs found for 'flathub'`.
  - **Cause** : Fedora 38+ pré-configure Flathub en `--system`. Le check du
    script acceptait `--user OR --system` mais les installs sont en `--user`
    (espaces de noms séparés) → flatpak ne trouvait pas le remote.
  - **Fix** : suppression du check conditionnel, appel systématique de
    `flatpak remote-add --user --if-not-exists` (déjà idempotent par design).
  - **Note** : ajout d'une section "Cas particulier : Flathub user vs system
    scope" qui documente le piège.

- **2026-05-20** — Corrections post-review :
  - **Bug** : `dnf5-plugins` est maintenant installé explicitement en début
    d'`add_third_party_repos` (avant l'appel `dnf config-manager`). Sur F44
    Workstation il est *normalement* préinstallé mais ce n'est pas garanti.
  - **Piège silencieux** : `find_latest_temurin` exécute maintenant
    `sdk list java` sous `set +u` (SDKMAN référence des variables non
    initialisées en interne ; sous `set -u` la fonction renvoyait du vide
    et le script déclarait à tort "aucune version Temurin trouvée").
  - **Piège silencieux** : installeur SDKMAN appelé avec `ci=true&rcupdate=true`
    au lieu de juste `rcupdate=true`, évite les prompts interactifs (Y/N
    pour set-as-default, etc.).
  - **Post-I/O 2026** : `@google/gemini-cli` retiré (deadline consumer
    18 juin 2026), remplacé par Antigravity CLI installé via le script curl
    officiel (`https://antigravity.google/cli/install.sh`). Binaire : `agy`.
  - **Nettoyage** : `mongodb-mongosh` retiré de la liste dnf (déjà tiré comme
    dépendance de `mongodb-org`).
  - **Cohérence** : sanitization des noms de logs unifiée
    (`${pkg//[^a-zA-Z0-9]/_}` partout, plus `${pkg//\//_}` qui laissait
    passer `:` et d'autres caractères pénibles).
  - **Note** : PDF viewer corrigé (Evince → Papers, changement Fedora 43+) ;
    commentaire gedit corrigé (le défaut GNOME est `gnome-text-editor` depuis
    GNOME 42, gedit gardé pour ses features avancées) ; section Antigravity
    réécrite pour refléter les 4 surfaces post-I/O 2026.

- **2026-05-20** — Version initiale Fedora, dérivée du script Windows.
  - Choix Podman (vs docker-ce / Docker Desktop)
  - Choix SDKMAN pour multi-JDK Temurin (vs dnf openjdk)
  - Choix MariaDB (vs MySQL Oracle)
  - GUI apps : dnf + repos officiels pour ce qui s'intègre bien, Flathub pour le reste
  - PDF reader : Evince (default GNOME) plutôt que Foxit
  - Notepad++ → Gedit
  - Antigravity IDE : skip pour l'instant (même raison que sur Windows)
  - PowerShell : non installé (bash suffit)
  - npm en user-space avec `~/.npm-global` (pas de `sudo npm`)
  - Podman socket rootless + `DOCKER_HOST` configuré
  - Récap final des échecs (rouge) + exit code 2 + logs conservés dans `/tmp`
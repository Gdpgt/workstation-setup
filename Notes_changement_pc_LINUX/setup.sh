#!/usr/bin/env bash
#
# setup.sh — Provisionne un nouveau PC Fedora Workstation 44
# (env dev fullstack Java/Spring + outils perso)
#
# Idempotent : peut etre relance sans risque.
# Lancer en UTILISATEUR NORMAL (sudo demande quand necessaire).
#
# En cas d'echec, le script affiche un RECAP rouge a la fin avec tous les
# paquets qui ont foire, leurs codes de retour et le chemin du log conserve.
# Exit code 0 = tout OK, exit code 2 = au moins un echec.
#
# Pas de "set -e" : on veut continuer apres l'echec d'un paquet individuel.

# shellcheck disable=SC2024
# Justification SC2024 : les logs vont dans /tmp (world-writable).
# Le pattern "sudo cmd > /tmp/file" fonctionne car le redirect est ouvert
# par le shell utilisateur (qui a write sur /tmp), avant que sudo prenne la
# main. Pas besoin de "sudo cmd 2>&1 | sudo tee" plus complexe.

set -uo pipefail

# ============================================================
# Configuration
# ============================================================

# ---- Paquets dnf -----------------------------------------------------------
DNF_PACKAGES=(
    # --- Outils dev de base ---
    'git'
    'make'
    'gcc'
    'gcc-c++'
    'curl'
    'wget'
    'zip'
    'unzip'              # requis par SDKMAN
    'jq'
    'ripgrep'
    'fd-find'
    'tree'
    'tmux'
    'htop'
    'openssl'
    'ca-certificates'
    'pipx'               # requis pour install user-space de gnome-extensions-cli

    # --- Hardware optimization (vendor-neutre) ---
    # NB: les paquets GPU specifiques au vendor (Intel / AMD) et thermald (Intel
    # only) ne sont PAS ici : ils sont poses par install_hardware_packages() apres
    # detection runtime du GPU/CPU (cf. detect_gpu_vendors()). Ici on ne garde que
    # ce qui est vendor-neutre.
    'libva-utils'                # 'vainfo' : verifier l'etat VA-API (tous vendors)
    'libavcodec-freeworld'       # Codecs H.264/H.265 patentes (RPM Fusion nonfree).
                                 #   Requis pour le decode HW de la plupart des
                                 #   fichiers video du monde reel. Tous vendors.
    'powertop'                   # Profilage conso + recommendations d'optimisation.

    # --- Biometrie (empreinte digitale) ---
    'fprintd'                    # Daemon d'empreintes (DBus) + 'fprintd-enroll/list'.
    'fprintd-pam'                # Module PAM : login GDM + sudo par empreinte.
    'tpm2-tools'                 # Diagnostic TPM2 ('tpm2_pcrread', etc.) pour la
                                 #   liaison LUKS+TPM (cf. enroll_luks_tpm()).

    # --- DNF plugins ---
    'dnf5-plugins'       # fournit "dnf config-manager"

    # --- Editeurs ---
    'code'               # VSCode (repo Microsoft)
    # Note: sur F44 (GNOME 50), gnome-text-editor ("Text Editor") est l'editeur
    # par defaut et est deja pre-installe. C'est celui que j'utilise -> rien a
    # ajouter. (gedit a ete retire le 2026-06-11 : je ne m'en sers pas.)

    # --- Navigateur ---
    'google-chrome-stable'

    # --- Mail ---
    'thunderbird'

    # --- Office (souvent deja installe sur Workstation) ---
    'libreoffice'

    # --- DB servers ---
    'postgresql-server'
    'postgresql-contrib'
    'mariadb-server'

    # --- MongoDB (via repo officiel MongoDB) ---
    # NB: mongodb-org est un meta-paquet qui tire deja mongodb-mongosh
    # en dependance, donc pas besoin de le lister explicitement.
    'mongodb-org'

    # --- Conteneurs : Podman (Fedora-native) ---
    'podman'
    'podman-compose'
    'podman-docker'      # alias 'docker' = podman (CLI compat)
    'buildah'
    'skopeo'

    # --- Node.js (LTS via dnf) ---
    'nodejs'
    'npm'

    # --- Python (deja la par defaut, on s'assure) ---
    'python3'
    'python3-pip'

    # --- Cloud ---
    'nautilus-dropbox'
    # libappindicator-gtk3 : lib requise par Dropbox pour afficher son icone de
    #   statut dans le systray (cf. doc Dropbox Linux). Souvent deja tiree en
    #   dependance, listee explicitement pour ne pas en dependre.
    'libappindicator-gtk3'
    # gnome-shell-extension-appindicator : sans elle, GNOME n'a pas de systray
    #   -> pas d'icone Dropbox. Paquet dnf (PAS gext/EGO) car il suit la version
    #   de GNOME du systeme. L'ACTIVATION se fait dans install_gnome_extensions().
    'gnome-shell-extension-appindicator'

    # --- Steam (necessite RPM Fusion nonfree) ---
    'steam'

    # --- Traitement image / PDF (CLI) ---
    'ImageMagick'                # binaire 'magick' (v7) / 'convert' : manipulation d'images
    'ghostscript'                # binaire 'gs' : rendu et conversion PostScript / PDF

    # --- GNOME utils ---
    'gnome-tweaks'

    # --- Media / telechargement ---
    'yt-dlp'             # CLI de telechargement media (repos Fedora officiels).
    'ffmpeg-free'        # Requis par yt-dlp (muxing/remux audio/video). Version
                         #   Fedora officielle, coexiste avec libavcodec-freeworld.
)

# ---- Flatpak apps (Flathub) ------------------------------------------------
FLATPAK_APPS=(
    'com.usebruno.Bruno'                          # Bruno - API client
    'com.stremio.Stremio'                         # Stremio
    # IntelliJ IDEA Community a ete RETIRE (2026-05-23) : le Flatpak est
    # sandboxe et ne voit pas les JDK Temurin installes via SDKMAN, ni Maven,
    # ni le shell host. Galere pour un workflow Java/Spring Boot. Remplace
    # par JetBrains Toolbox (install native), voir install_jetbrains_toolbox().
    'com.mongodb.Compass'                         # MongoDB Compass
    'io.dbeaver.DBeaverCommunity'                 # DBeaver Community
    'org.gimp.GIMP'                               # GIMP - editeur d'images
    'io.bassi.Amberol'                            # Amberol - lecteur audio minimaliste ;
                                                  #   repete une piste en boucle (repeat one),
                                                  #   ce que le "Audio Player" de GNOME ne fait pas
)

# ---- SDKMAN candidates (Java, Maven, etc.) ---------------------------------
# Les versions Temurin exactes sont resolues dynamiquement (derniere de chaque
# major). Voir install_jdks_via_sdkman().
SDKMAN_JDK_MAJORS=(17 21 25)
SDKMAN_OTHER_CANDIDATES=(
    'maven'
    # 'gradle'
    # 'springboot'
)

# ---- npm globals -----------------------------------------------------------
# NB: @anthropic-ai/claude-code a ete RETIRE de cette liste (2026-06-19).
# Claude Code est desormais installe en NATIF par bootstrap.sh
#   (curl -fsSL https://claude.ai/install.sh | bash)
# qui n'exige pas Node et s'auto-update. Garder AUSSI la version npm creerait
# deux binaires 'claude' dans le PATH (~/.npm-global/bin ET ~/.local/bin) ->
# ambiguite de version. On veut une source unique : le natif. La fonction
# install_npm_globals() retire au passage tout binaire npm orphelin.
#
# NB: @google/gemini-cli a ete RETIRE apres Google I/O 2026 (19 mai 2026).
# Gemini CLI est deprecie pour les comptes consumer (Google AI Pro/Ultra +
# free tier) avec arret de service le 18 juin 2026, remplace par Antigravity
# CLI. Voir install_antigravity_cli() plus bas.
NPM_GLOBALS=(
    '@openai/codex'
    # Tooling dev front (pas une CLI IA) : fournit la commande 'ng' pour
    # scaffolder/builder/servir les projets Angular. Latest (non pinne) pour
    # rester coherent avec les autres globals ; 'npm update -g' suffit a suivre.
    '@angular/cli'
)

# ============================================================
# Couleurs et helpers de log
# ============================================================

if [[ -t 1 ]]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_DIM='' C_RESET=''
fi

section() {
    echo
    echo "${C_CYAN}===============================================${C_RESET}"
    echo "${C_CYAN}  $1${C_RESET}"
    echo "${C_CYAN}===============================================${C_RESET}"
}

log_info() { echo "${C_DIM}  --> $*${C_RESET}"; }
log_ok()   { echo "${C_GREEN}  [OK] $*${C_RESET}"; }
log_warn() { echo "${C_YELLOW}  [!]  $*${C_RESET}"; }
log_err()  { echo "${C_RED}  [X]  $*${C_RESET}"; }

# ============================================================
# Collecteur d'echecs (recap a la fin)
# ============================================================

# Tableau de chaines au format "type|paquet|raison|log_path"
FAILURES=()

register_failure() {
    local type=$1 pkg=$2 reason=$3 log=${4:-}
    FAILURES+=("${type}|${pkg}|${reason}|${log}")
}

new_log_file() {
    local prefix=$1
    local stamp
    stamp=$(date +'%Y%m%d-%H%M%S-%N')
    echo "/tmp/setup_${prefix}_${stamp}.log"
}

# ============================================================
# Pre-requis
# ============================================================

check_prerequisites() {
    section "Verification des pre-requis"

    if [[ $EUID -eq 0 ]]; then
        log_err "Ce script ne doit PAS etre lance en root."
        log_err "Lance-le en utilisateur normal ; il utilisera sudo quand necessaire."
        exit 1
    fi
    log_ok "Mode utilisateur (non-root)"

    if ! command -v dnf >/dev/null 2>&1; then
        log_err "dnf introuvable. Ce script est specifique a Fedora."
        exit 1
    fi
    log_ok "dnf detecte"

    if [[ ! -f /etc/fedora-release ]]; then
        log_err "Distribution non-Fedora detectee."
        exit 1
    fi
    local version
    version=$(rpm -E %fedora)
    log_ok "Fedora ${version} detectee"

    if [[ "$version" -lt 41 ]]; then
        log_warn "Fedora ${version} < 41. dnf5 n'est peut-etre pas dispo."
        log_warn "Le script suppose dnf5 (Fedora 41+). Continue avec precaution."
    fi

    # Cache sudo des le debut pour eviter les prompts dispersees
    log_info "Cache du mot de passe sudo (demande une seule fois)..."
    if ! sudo -v; then
        log_err "sudo refuse. Verifie que tu es dans le groupe wheel."
        exit 1
    fi

    # Renouvelle le ticket sudo en arriere-plan tant que le script tourne
    (while true; do sudo -n true; sleep 50; done 2>/dev/null) &
    SUDO_KEEPALIVE_PID=$!
    # NB: single quotes pour que $SUDO_KEEPALIVE_PID soit expanded a l'exit,
    # pas au trap-setup (SC2064)
    # shellcheck disable=SC2064  # variable disponible globalement, OK ici
    trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT
    log_ok "sudo cache"
}

# ============================================================
# Mise a jour systeme
# ============================================================

update_system() {
    section "Mise a jour du systeme"
    local log
    log=$(new_log_file "dnf_upgrade")
    log_info "dnf upgrade --refresh (peut prendre quelques minutes)..."
    if sudo dnf upgrade --refresh -y >"$log" 2>&1; then
        log_ok "Systeme a jour"
        rm -f "$log"
    else
        log_err "Echec de la mise a jour (log : $log)"
        register_failure "dnf" "system upgrade" "exit $?" "$log"
    fi
}

# ============================================================
# RPM Fusion (free + nonfree)
# ============================================================

install_rpmfusion() {
    section "RPM Fusion (free + nonfree)"
    local fedora_ver
    fedora_ver=$(rpm -E %fedora)

    for repo_kind in free nonfree; do
        local pkg="rpmfusion-${repo_kind}-release"
        if rpm -q "$pkg" >/dev/null 2>&1; then
            log_ok "RPM Fusion ${repo_kind} deja installe"
            continue
        fi
        log_info "Installation : RPM Fusion ${repo_kind}..."
        local log
        log=$(new_log_file "rpmfusion_${repo_kind}")
        local url="https://download1.rpmfusion.org/${repo_kind}/fedora/rpmfusion-${repo_kind}-release-${fedora_ver}.noarch.rpm"
        if sudo dnf install -y "$url" >"$log" 2>&1; then
            log_ok "RPM Fusion ${repo_kind}"
            rm -f "$log"
        else
            log_err "RPM Fusion ${repo_kind} : echec (log : $log)"
            register_failure "dnf-repo" "rpmfusion-${repo_kind}" "install failed" "$log"
        fi
    done
}

# ============================================================
# Repos tiers (Chrome, VSCode, MongoDB)
# ============================================================

add_third_party_repos() {
    section "Repos tiers (Chrome, VSCode, MongoDB)"

    # IMPORTANT : 'dnf config-manager' est fourni par le paquet dnf5-plugins,
    # qui est *normalement* pre-installe sur Fedora Workstation 44 mais
    # ce n'est pas garanti. On l'installe explicitement avant utilisation
    # pour eviter un echec silencieux sur l'enable de google-chrome.
    if ! rpm -q dnf5-plugins >/dev/null 2>&1; then
        log_info "Installation de dnf5-plugins (pour dnf config-manager)..."
        local log; log=$(new_log_file "dnf_dnf5_plugins")
        if sudo dnf install -y dnf5-plugins >"$log" 2>&1; then
            log_ok "dnf5-plugins"
            rm -f "$log"
        else
            log_err "dnf5-plugins : echec (log : $log)"
            register_failure "dnf" "dnf5-plugins" "install failed" "$log"
            return 1
        fi
    else
        log_ok "dnf5-plugins deja installe"
    fi

    # --- Google Chrome ---
    if [[ -f /etc/yum.repos.d/google-chrome.repo ]]; then
        log_ok "Repo Google Chrome deja present"
    else
        log_info "Ajout du repo Google Chrome..."
        # fedora-workstation-repositories fournit le repo Chrome desactive
        # par defaut. On l'installe + on l'active.
        local log; log=$(new_log_file "repo_chrome")
        if sudo dnf install -y fedora-workstation-repositories >"$log" 2>&1 \
            && sudo dnf config-manager setopt google-chrome.enabled=1 >>"$log" 2>&1; then
            log_ok "Repo Google Chrome ajoute et active"
            rm -f "$log"
        else
            log_err "Repo Google Chrome : echec (log : $log)"
            register_failure "dnf-repo" "google-chrome" "config failed" "$log"
        fi
    fi

    # --- Microsoft VSCode ---
    if [[ -f /etc/yum.repos.d/vscode.repo ]]; then
        log_ok "Repo VSCode deja present"
    else
        log_info "Ajout du repo Microsoft VSCode..."
        local log; log=$(new_log_file "repo_vscode")
        if sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc >"$log" 2>&1; then
            cat <<'EOF' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            log_ok "Repo VSCode"
            rm -f "$log"
        else
            log_err "Repo VSCode : echec (log : $log)"
            register_failure "dnf-repo" "vscode" "key import failed" "$log"
        fi
    fi

    # --- MongoDB Community 8.0 ---
    if [[ -f /etc/yum.repos.d/mongodb-org-8.0.repo ]]; then
        log_ok "Repo MongoDB deja present"
    else
        log_info "Ajout du repo MongoDB 8.0..."
        # NB: pas de repo Fedora officiel, on utilise le repo RHEL 9 qui marche
        # sur Fedora. MongoDB ne garantit pas la compat Fedora mais en pratique OK.
        cat <<'EOF' | sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo >/dev/null
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF
        log_ok "Repo MongoDB 8.0"
    fi

    log_info "Refresh des metadonnees..."
    sudo dnf makecache >/dev/null 2>&1 || log_warn "dnf makecache a echoue (non critique)"
}

# ============================================================
# Paquets dnf
# ============================================================

install_dnf_packages() {
    section "Paquets dnf"

    for pkg in "${DNF_PACKAGES[@]}"; do
        # Skip si deja installe (idempotence + lisibilite)
        if rpm -q "$pkg" >/dev/null 2>&1; then
            log_ok "${pkg} (deja installe)"
            continue
        fi

        log_info "Installation : ${pkg}"
        local log; log=$(new_log_file "dnf_${pkg//[^a-zA-Z0-9]/_}")
        if sudo dnf install -y "$pkg" >"$log" 2>&1; then
            log_ok "$pkg"
            rm -f "$log"
        else
            log_err "${pkg} : echec (log : $log)"
            register_failure "dnf" "$pkg" "install failed" "$log"
        fi
    done
}

# ============================================================
# Flathub + Flatpak apps
# ============================================================

setup_flathub() {
    section "Flathub"

    if ! command -v flatpak >/dev/null 2>&1; then
        log_info "Installation de flatpak..."
        local log; log=$(new_log_file "dnf_flatpak")
        if sudo dnf install -y flatpak >"$log" 2>&1; then
            log_ok "flatpak"
            rm -f "$log"
        else
            log_err "flatpak : echec (log : $log)"
            register_failure "dnf" "flatpak" "install failed" "$log"
            return
        fi
    else
        log_ok "flatpak deja present"
    fi

    # Toujours s'assurer que Flathub existe au scope --user.
    # NB: sur Fedora Workstation 44, Flathub est pre-configure en --system
    # (paquet flatpak-flathub-config). Mais les remotes --user et --system
    # sont des espaces de noms SEPARES. Comme on installe en --user (cf.
    # install_flatpak_apps), il FAUT que le remote existe en --user, sinon
    # 'flatpak install --user [...] flathub <app>' echoue avec :
    #   error: No remote refs found for 'flathub'
    # --if-not-exists rend la commande idempotente : aucun risque a la lancer
    # systematiquement.
    log_info "Configuration du remote Flathub (user-level)..."
    if flatpak remote-add --user --if-not-exists flathub \
          https://dl.flathub.org/repo/flathub.flatpakrepo; then
        log_ok "Flathub (user)"
    else
        log_err "Echec ajout Flathub --user"
        register_failure "flatpak" "flathub remote" "remote-add --user failed"
    fi
}

install_flatpak_apps() {
    section "Paquets Flatpak"

    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
            log_ok "${app} (deja installe)"
            continue
        fi

        log_info "Installation : ${app}"
        local log; log=$(new_log_file "flatpak_${app//[^a-zA-Z0-9]/_}")
        if flatpak install --user --noninteractive --assumeyes \
              flathub "$app" >"$log" 2>&1; then
            log_ok "$app"
            rm -f "$log"
        else
            log_err "${app} : echec (log : $log)"
            register_failure "flatpak" "$app" "install failed" "$log"
        fi
    done
}

# ============================================================
# SDKMAN + JDKs Temurin + Maven
# ============================================================

install_sdkman() {
    section "SDKMAN"

    if [[ -d "$HOME/.sdkman" ]]; then
        log_ok "SDKMAN deja installe"
    else
        log_info "Installation de SDKMAN..."
        local log; log=$(new_log_file "sdkman_install")
        # ci=true        : mode non-interactif (auto-answer, pas de prompt Y/N)
        # rcupdate=true  : autoriser SDKMAN a ajouter son snippet d'init dans .bashrc (defaut)
        if curl -s "https://get.sdkman.io?ci=true&rcupdate=true" | bash >"$log" 2>&1; then
            log_ok "SDKMAN"
            rm -f "$log"
        else
            log_err "SDKMAN : echec (log : $log)"
            register_failure "sdkman" "sdkman itself" "install failed" "$log"
            return 1
        fi
    fi

    # Source l'init pour pouvoir l'utiliser dans CE script
    # shellcheck source=/dev/null
    if [[ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
        set +u  # SDKMAN's script does not tolerate -u
        source "$HOME/.sdkman/bin/sdkman-init.sh"
        set -u
    else
        log_err "sdkman-init.sh introuvable apres install"
        register_failure "sdkman" "sdkman init" "init script missing"
        return 1
    fi
}

# Trouve la derniere version Temurin disponible pour un major donne
find_latest_temurin() {
    local major=$1
    # sdk list java affiche un tableau ; on grep les lignes contenant "-tem"
    # et on filtre par major version, puis on prend la 1ere (la plus recente).
    #
    # set +u indispensable : les fonctions SDKMAN referencent en interne des
    # variables non-initialisees ; sous "set -u" la sortie serait vide et on
    # signalerait a tort "Aucune version Temurin trouvee".
    set +u
    sdk list java 2>/dev/null \
        | grep -oE "${major}\.[0-9.]+(\.[0-9]+)?(-LTS)?-tem" \
        | sort -Vr \
        | head -1
    set -u
}

install_jdks_via_sdkman() {
    section "JDKs Temurin via SDKMAN"

    if ! command -v sdk >/dev/null 2>&1; then
        log_err "sdk introuvable -- SDKMAN non installe"
        return
    fi

    for major in "${SDKMAN_JDK_MAJORS[@]}"; do
        local version
        version=$(find_latest_temurin "$major")

        if [[ -z "$version" ]]; then
            log_err "Aucune version Temurin ${major} trouvee dans SDKMAN"
            register_failure "sdkman" "java-${major}" "no Temurin version found"
            continue
        fi

        if [[ -d "$HOME/.sdkman/candidates/java/$version" ]]; then
            log_ok "Java $version (deja installe)"
            continue
        fi

        log_info "Installation : Java ${version}"
        local log; log=$(new_log_file "sdkman_java_${major}")
        set +u
        if sdk install java "$version" < /dev/null >"$log" 2>&1; then
            log_ok "Java ${version}"
            rm -f "$log"
        else
            log_err "Java ${version} : echec (log : $log)"
            register_failure "sdkman" "java-${version}" "install failed" "$log"
        fi
        set -u
    done

    # Autres candidates : maven, etc.
    for candidate in "${SDKMAN_OTHER_CANDIDATES[@]}"; do
        if [[ -d "$HOME/.sdkman/candidates/$candidate" ]] \
           && [[ -n "$(ls -A "$HOME/.sdkman/candidates/$candidate" 2>/dev/null)" ]]; then
            log_ok "${candidate} (deja installe)"
            continue
        fi

        log_info "Installation : ${candidate}"
        local log; log=$(new_log_file "sdkman_${candidate}")
        set +u
        if sdk install "$candidate" < /dev/null >"$log" 2>&1; then
            log_ok "$candidate"
            rm -f "$log"
        else
            log_err "${candidate} : echec (log : $log)"
            register_failure "sdkman" "$candidate" "install failed" "$log"
        fi
        set -u
    done
}

# ============================================================
# Node.js setup + npm globals
# ============================================================

setup_npm_userspace() {
    section "npm en user-space (sans sudo)"

    if ! command -v npm >/dev/null 2>&1; then
        log_err "npm introuvable -- nodejs aurait du etre installe via dnf"
        register_failure "npm" "(npm itself)" "command not found"
        return 1
    fi

    # Configure npm pour installer les globals dans ~/.npm-global (pas /usr)
    local prefix="$HOME/.npm-global"
    mkdir -p "$prefix"
    local current_prefix
    current_prefix=$(npm config get prefix 2>/dev/null || echo '')

    if [[ "$current_prefix" != "$prefix" ]]; then
        log_info "Config npm prefix -> ${prefix}"
        npm config set prefix "$prefix"
    fi

    # Ajoute au PATH dans .bashrc si pas deja la
    local bashrc="$HOME/.bashrc"
    # Single quotes voulu : on veut $HOME litteral dans .bashrc, pas son expansion
    # shellcheck disable=SC2016
    local export_line='export PATH="$HOME/.npm-global/bin:$PATH"'
    if ! grep -qxF "$export_line" "$bashrc" 2>/dev/null; then
        log_info "Ajout du PATH npm dans ~/.bashrc"
        {
            echo ''
            echo '# npm globals user-space (ajout par setup.sh)'
            echo "$export_line"
        } >> "$bashrc"
    fi

    # Met a jour le PATH pour la session courante
    export PATH="$HOME/.npm-global/bin:$PATH"
    log_ok "npm configure en user-space"
}

install_npm_globals() {
    section "CLI IA (npm globals)"

    if ! command -v npm >/dev/null 2>&1; then
        log_err "npm introuvable. Verifie que nodejs est installe via dnf."
        register_failure "npm" "(npm itself)" "command not found"
        return
    fi

    # Nettoyage : retire l'ancien claude-code npm s'il traine (machines deja
    # provisionnees avant le 2026-06-19). Claude Code vient maintenant du natif
    # (bootstrap.sh) -> on evite le double binaire 'claude' dans le PATH.
    # Idempotent : no-op si absent.
    if npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
        log_info "Retrait de l'ancien @anthropic-ai/claude-code (npm) -> natif"
        npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 \
            && log_ok "claude-code npm retire (le natif prend le relais)" \
            || log_warn "Echec retrait claude-code npm (non bloquant)"
    fi

    for pkg in "${NPM_GLOBALS[@]}"; do
        log_info "Installation : ${pkg}"
        local log; log=$(new_log_file "npm_${pkg//[^a-zA-Z0-9]/_}")
        if npm install -g "$pkg" >"$log" 2>&1; then
            log_ok "$pkg"
            rm -f "$log"
        else
            log_err "${pkg} : echec (log : $log)"
            register_failure "npm" "$pkg" "install failed" "$log"
        fi
    done
}

# ============================================================
# JetBrains Toolbox (gestionnaire d'IDE JetBrains)
# ============================================================
#
# Remplace le Flatpak IntelliJ Community (sandbox -> ne voit pas SDKMAN JDKs).
# Toolbox est l'outil officiel JetBrains, install native user-space, gere
# IDEA Community/Ultimate, DataGrip, PyCharm, WebStorm... avec auto-update.
#
# Strategie : on telecharge le tarball via l'endpoint de redirect officiel
# JetBrains (?platform=linux&code=TBA), qui pointe toujours sur la derniere
# version stable. Pas besoin de l'API + jq.

install_jetbrains_toolbox() {
    section "JetBrains Toolbox"

    local install_dir="$HOME/.local/share/JetBrains/Toolbox"
    # Depuis Toolbox 3.x (mars 2026, ajout de jetbrainsd), le tarball contient
    # tout sous bin/ (jetbrains-toolbox, jetbrainsd, jre, libs...). Avec
    # --strip-components=1 on obtient donc $install_dir/bin/jetbrains-toolbox.
    local binary="$install_dir/bin/jetbrains-toolbox"
    local desktop_dir="$HOME/.local/share/applications"
    local desktop_file="$desktop_dir/jetbrains-toolbox.desktop"

    # ---- 1. Install du binaire (idempotent) ----
    if [[ -x "$binary" ]]; then
        log_ok "Binaire JetBrains Toolbox deja present"
    else
        log_info "Telechargement de JetBrains Toolbox (derniere version)..."
        local log; log=$(new_log_file "jetbrains_toolbox")
        local tmp_tarball
        tmp_tarball=$(mktemp --suffix=.tar.gz)

        # NB : --location pour suivre la redirection 302 vers le vrai tarball
        if ! curl -fsSL \
            "https://data.services.jetbrains.com/products/download?platform=linux&code=TBA" \
            -o "$tmp_tarball" >"$log" 2>&1; then
            log_err "JetBrains Toolbox : echec telechargement (log : $log)"
            register_failure "curl" "jetbrains-toolbox" "download failed" "$log"
            rm -f "$tmp_tarball"
            return
        fi

        log_info "Extraction dans $install_dir..."
        mkdir -p "$install_dir"
        if ! tar -xzf "$tmp_tarball" -C "$install_dir" --strip-components=1 \
                >>"$log" 2>&1; then
            log_err "JetBrains Toolbox : echec extraction (log : $log)"
            register_failure "curl" "jetbrains-toolbox" "extract failed" "$log"
            rm -f "$tmp_tarball"
            return
        fi
        rm -f "$tmp_tarball"

        if [[ ! -x "$binary" ]]; then
            log_err "JetBrains Toolbox : binaire introuvable a $binary (log : $log)"
            register_failure "curl" "jetbrains-toolbox" \
                "binary missing after extract (structure tarball changee ?)" "$log"
            return
        fi
        log_ok "JetBrains Toolbox installe ($binary)"
        rm -f "$log"
    fi

    # ---- 2. .desktop pour l'icone GNOME (idempotent et SEPARE de l'install) ----
    # NB: cette etape DOIT etre hors de l'early-return du check binaire, sinon
    # un run precedent qui a installe le binaire mais foire avant le .desktop
    # ne sera jamais "repare" par un run suivant (regression rencontree
    # 2026-05-23 apres bugfix structure tarball 3.x).
    mkdir -p "$desktop_dir"
    # On (re-)ecrit toujours le .desktop : si le binaire bouge (futur Toolbox
    # 4.x ?), le contenu doit suivre. Et c'est tres rapide.
    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Manage your JetBrains tools
Exec=$binary
Icon=$install_dir/bin/toolbox-tray-color.png
Terminal=false
Categories=Development;IDE;
StartupWMClass=jetbrains-toolbox
StartupNotify=true
EOF

    # Rafraichir le cache desktop GNOME pour que l'icone apparaisse sans
    # devoir se deconnecter/reconnecter
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
    fi

    log_ok ".desktop GNOME ($desktop_file)"
    log_info "Lance Toolbox depuis GNOME Activities (touche Super, tape 'Toolbox')"
}

# ============================================================
# Antigravity CLI (Google) - remplace Gemini CLI depuis I/O 2026
# ============================================================
#
# Annonce Google I/O 2026 (19 mai 2026) : Gemini CLI est remplace par
# Antigravity CLI. Pour les comptes consumer (Google AI Pro/Ultra +
# tier gratuit), Gemini CLI cesse de fonctionner le 18 juin 2026.
# Antigravity CLI est ecrit en Go, partage le meme agent harness que
# l'app desktop Antigravity 2.0. Binaire : 'agy'.

install_antigravity_cli() {
    section "Antigravity CLI (Google)"

    if command -v agy >/dev/null 2>&1; then
        log_ok "Antigravity CLI (agy) deja installe"
        return
    fi

    log_info "Installation : Antigravity CLI via l'installer officiel..."
    local log; log=$(new_log_file "antigravity_cli")
    # Installer officiel Google (curl|bash). Recupere le binaire 'agy' et
    # ajoute son repertoire au PATH via .bashrc (gere par l'installer).
    if curl -fsSL https://antigravity.google/cli/install.sh | bash >"$log" 2>&1; then
        log_ok "Antigravity CLI (agy)"
        rm -f "$log"
    else
        log_err "Antigravity CLI : echec (log : $log)"
        register_failure "curl" "antigravity-cli" "install failed" "$log"
    fi
}

# ============================================================
# Services systemd (PostgreSQL, MariaDB, MongoDB) + Podman socket
# ============================================================

configure_services() {
    section "Services systemd"

    # --- PostgreSQL ---
    if rpm -q postgresql-server >/dev/null 2>&1; then
        # NB: /var/lib/pgsql/data/ est en mode 700 owned by postgres, donc
        # un '[[ -f ... ]]' executes en tant que user normal renvoie FALSE
        # par permission denied (et PAS par fichier absent). Sans sudo, on
        # tenterait l'initdb meme sur un cluster deja initialise -> echec
        # avec "Data directory not empty". D'ou 'sudo test -f'.
        if sudo test -f /var/lib/pgsql/data/PG_VERSION; then
            log_ok "Cluster PostgreSQL deja initialise"
        else
            log_info "Init du cluster PostgreSQL (postgresql-setup --initdb)..."
            local pglog; pglog=$(new_log_file "postgresql_initdb")
            if sudo postgresql-setup --initdb >"$pglog" 2>&1; then
                log_ok "PostgreSQL cluster initialise"
                rm -f "$pglog"
            else
                log_err "postgresql-setup --initdb a echoue (log : $pglog)"
                register_failure "systemd" "postgresql-setup" \
                    "initdb failed" "$pglog"
            fi
        fi

        if systemctl is-enabled --quiet postgresql 2>/dev/null; then
            log_ok "Service postgresql deja active"
        else
            log_info "Activation + start de postgresql..."
            if sudo systemctl enable --now postgresql >/dev/null 2>&1; then
                log_ok "Service postgresql"
            else
                log_err "systemctl enable postgresql a echoue"
                register_failure "systemd" "postgresql.service" "enable failed"
            fi
        fi
    fi

    # --- MariaDB ---
    if rpm -q mariadb-server >/dev/null 2>&1; then
        if systemctl is-enabled --quiet mariadb 2>/dev/null; then
            log_ok "Service mariadb deja active"
        else
            log_info "Activation + start de mariadb..."
            if sudo systemctl enable --now mariadb >/dev/null 2>&1; then
                log_ok "Service mariadb"
            else
                log_err "systemctl enable mariadb a echoue"
                register_failure "systemd" "mariadb.service" "enable failed"
            fi
        fi
    fi

    # --- MongoDB ---
    if rpm -q mongodb-org >/dev/null 2>&1; then
        if systemctl is-enabled --quiet mongod 2>/dev/null; then
            log_ok "Service mongod deja active"
        else
            log_info "Activation + start de mongod..."
            if sudo systemctl enable --now mongod >/dev/null 2>&1; then
                log_ok "Service mongod"
            else
                log_err "systemctl enable mongod a echoue"
                register_failure "systemd" "mongod.service" "enable failed"
            fi
        fi
    fi

    # --- Podman rootless socket (compat docker) ---
    if command -v podman >/dev/null 2>&1; then
        if systemctl --user is-enabled --quiet podman.socket 2>/dev/null; then
            log_ok "Podman socket (user) deja active"
        else
            log_info "Activation du socket Podman rootless (user)..."
            if systemctl --user enable --now podman.socket >/dev/null 2>&1; then
                log_ok "Podman socket"
            else
                log_warn "systemctl --user enable podman.socket a echoue (non bloquant)"
            fi
        fi

        # Ajoute DOCKER_HOST dans .bashrc si pas deja la
        local bashrc="$HOME/.bashrc"
        # Single quotes voulu : on veut $XDG_RUNTIME_DIR litteral dans .bashrc
        # shellcheck disable=SC2016
        local docker_host_line='export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"'
        if ! grep -qxF "$docker_host_line" "$bashrc" 2>/dev/null; then
            log_info "Ajout de DOCKER_HOST dans ~/.bashrc (pointe vers podman.sock)"
            {
                echo ''
                echo '# Podman compat: DOCKER_HOST pour Testcontainers, docker-compose, etc.'
                echo "$docker_host_line"
            } >> "$bashrc"
        fi
    fi
}

# ============================================================
# Configuration Git (~/.gitconfig)
# ============================================================
#
# Ecrit mes options + alias Git via 'git config --global' (une commande par
# cle). Non destructif : ne touche pas a l'identite (user.name / user.email),
# qui reste une etape manuelle. Idempotent : 'git config' ecrase la valeur
# existante a chaque run, sans dupliquer.
#
# Differences vs config Windows :
#  - core.editor = "idea --wait" (IntelliJ via launcher Toolbox ; --wait bloque
#    jusqu'a fermeture de l'onglet). NB : 'idea' n'est dispo qu'apres 1er
#    lancement Toolbox + install IDEA, mais l'editeur n'est invoque qu'au
#    moment d'un commit, donc sans impact a l'install.
#  - pas de safe.directory : les entrees Windows (C:/Users/...) sont des chemins
#    invalides sur Linux.

configure_git() {
    section "Configuration Git (~/.gitconfig)"

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git absent du PATH : configuration Git sautee (devrait etre dans DNF_PACKAGES)"
        return
    fi

    # cle <valeur> : une entree par ligne (la valeur peut contenir des espaces)
    local -a git_settings=(
        "pull.rebase|true"
        "color.status|auto"
        "color.diff|auto"
        "color.branch|auto"
        "core.editor|idea --wait"
        "core.excludesfile|~/.gitignore_global"
        "alias.ca|commit --amend"
        "alias.can|commit --amend --no-edit"
        "alias.frm|!git fetch && git reset --hard origin/main"
        "alias.ac|!git add . && git commit -m"
        "alias.acan|!git add . && git commit --amend --no-edit"
        "alias.fsc|!git fetch && git switch -c"
        "alias.p|push"
        "alias.pf|push --force-with-lease"
    )

    local failed=0
    for entry in "${git_settings[@]}"; do
        local key="${entry%%|*}"
        local value="${entry#*|}"
        if git config --global "$key" "$value"; then
            log_ok "${key} = ${value}"
        else
            log_err "Echec git config --global ${key}"
            register_failure "git" "$key" "git config set failed"
            failed=1
        fi
    done

    if [[ "$failed" -eq 0 ]]; then
        log_ok "Git configure (alias + options)"
    fi
    log_info "Identite Git (user.name / user.email) : a definir manuellement"
}

# ============================================================
# gitignore global (~/.gitignore_global)
# ============================================================
#
# Pose le fichier pointe par core.excludesfile (configure_git). Sans lui,
# l'option pointe vers un fichier inexistant => aucun effet.
#
# Strategie : CREER SI ABSENT (on ne touche pas a un fichier existant, pour
# preserver d'eventuels ajouts manuels). Consequence : une evolution future de
# ce contenu de base ne se propage pas sur une machine deja provisionnee.
#
# NB : contenu duplique a l'identique dans setup.ps1 (Windows). Les deux dossiers
# OS sont autonomes (pas de fichier partage) : toute evolution se fait aux deux
# endroits. Volontairement EXCLU : *.properties (casse application.properties /
# Spring) et env* (casse environment.ts / Angular) — trop larges en global.

configure_gitignore_global() {
    section "gitignore global (~/.gitignore_global)"

    # Chemin construit en dur : "$HOME/..." (le '~' ne s'etend pas entre
    # guillemets). C'est git qui developpe le '~' de core.excludesfile, pas nous.
    local target="$HOME/.gitignore_global"

    if [[ -f "$target" ]]; then
        log_ok "~/.gitignore_global deja present : laisse tel quel"
        return
    fi

    log_info "Creation de ~/.gitignore_global (contenu de base)"
    # Delimiteur quote ('EOF') => pas d'expansion de $ ni interpretation des '!'.
    if cat > "$target" <<'EOF'
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
EOF
    then
        log_ok "~/.gitignore_global cree"
    else
        log_err "Echec ecriture ~/.gitignore_global"
        register_failure "git" ".gitignore_global" "write failed"
    fi
}

# ============================================================
# Identite git perso (noreply) pour les repos sous ~/code
# ============================================================
#
# Ce repo est PUBLIC : un commit expose l'email git de la machine. Pour ne jamais
# fuiter d'email reel (gmail perso, ou email pro sur un PC de travail), on route
# tous mes repos PERSO (ranges sous ~/code) vers l'adresse noreply GitHub, via un
# 'includeIf' conditionnel. Ca ne touche PAS l'identite globale par defaut : sur
# un PC pro, les repos sous ~/workspace gardent l'email pro.
#
# includeIf couvre TOUS mes projets perso (pas seulement ce repo), sur chaque
# machine provisionnee. Idempotent : 'git config' reecrit la meme valeur.

configure_git_perso_identity() {
    section "Identite git perso (noreply pour ~/code)"

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git absent : identite perso non configuree (non bloquant)"
        return
    fi

    local perso_file="$HOME/.gitconfig-perso"
    # Fichier d'identite perso, inclus conditionnellement ci-dessous. 'git config
    # --file' cree/met a jour ces 2 cles sans toucher au reste du fichier.
    git config --file "$perso_file" user.name  "Guillaume de Puget"
    git config --file "$perso_file" user.email "142890016+Gdpgt@users.noreply.github.com"

    # includeIf : tout repo dont le .git est sous ~/code/ utilise l'identite perso.
    git config --global "includeIf.gitdir:~/code/.path" "~/.gitconfig-perso"

    log_ok "Repos sous ~/code -> noreply (includeIf)"
}

# ============================================================
# Alias shell (~/.bashrc)
# ============================================================
#
# Portage minimal du profil PowerShell Windows. On ne porte QUE ce qui n'est pas
# deja natif sous Fedora :
#  - 'dc'   : raccourci 'docker compose' (route vers Podman via podman-docker).
#  - 'mvnw' : wrapper Maven Wrapper avec message clair si absent du projet.
# Volontairement NON porte : posh-git (bash-completion deja installe), encodage
# UTF-8 (deja le defaut sur Fedora), './mvnw' natif executable.
#
# Idempotent : un marqueur unique garde l'ajout ; relancable sans dupliquer.

configure_shell_aliases() {
    section "Alias shell (~/.bashrc)"

    local bashrc="$HOME/.bashrc"
    local marker='# workstation-setup: shell aliases'

    if grep -qF "$marker" "$bashrc" 2>/dev/null; then
        log_ok "Alias shell deja presents dans ~/.bashrc"
        return
    fi

    log_info "Ajout des alias shell (dc, mvnw) dans ~/.bashrc"
    cat >> "$bashrc" <<'EOF'

# workstation-setup: shell aliases
# 'dc' : sous Fedora, 'docker' est un alias vers podman (paquet podman-docker),
#        donc 'docker compose' route vers podman compose.
alias dc='docker compose'

# Wrapper Maven Wrapper : message clair si ./mvnw absent du projet courant.
mvnw() {
    if [[ ! -x ./mvnw ]]; then
        echo "Maven Wrapper (./mvnw) manquant dans '$(pwd)'" >&2
        echo "Sans wrapper -> mvn clean compile" >&2
        return 1
    fi
    ./mvnw "$@"
}
EOF
    log_ok "Alias shell ajoutes (reload : source ~/.bashrc)"
}

# ============================================================
# Detection GPU/CPU (vendor) + paquets hardware adaptes
# ============================================================
#
# Ces scripts provisionnent N'IMPORTE QUEL PC (Intel / AMD / NVIDIA), pas une
# machine precise. On detecte le vendor GPU au runtime par vendor ID PCI (plus
# robuste que matcher la chaine "Intel"/"AMD"), en FLAGS INDEPENDANTS (pas de
# elif exclusif) pour gerer les laptops hybrides Intel iGPU + NVIDIA dGPU.

HAS_INTEL=0
HAS_AMD=0
HAS_NVIDIA=0

detect_gpu_vendors() {
    local gpus
    gpus=$(lspci -nn 2>/dev/null | grep -iE 'VGA|3D|Display')
    grep -q '\[8086:' <<<"$gpus" && HAS_INTEL=1
    grep -qE '\[1002:|\[1022:' <<<"$gpus" && HAS_AMD=1
    grep -q '\[10de:' <<<"$gpus" && HAS_NVIDIA=1
    return 0
}

# Install dnf simple (log + idempotence rpm -q) pour les paquets HORS de la
# boucle statique DNF_PACKAGES. Usage : dnf_install_one <paquet>
dnf_install_one() {
    local pkg=$1
    if rpm -q "$pkg" >/dev/null 2>&1; then
        log_ok "${pkg} (deja installe)"
        return 0
    fi
    log_info "Installation : ${pkg}"
    local log; log=$(new_log_file "dnf_${pkg//[^a-zA-Z0-9]/_}")
    if sudo dnf install -y "$pkg" >"$log" 2>&1; then
        log_ok "$pkg"; rm -f "$log"
    else
        log_err "${pkg} : echec (log : $log)"
        register_failure "dnf" "$pkg" "install failed" "$log"
    fi
}

install_hardware_packages() {
    section "Paquets hardware (selon GPU detecte)"

    detect_gpu_vendors
    log_info "GPU detecte : Intel=${HAS_INTEL} AMD=${HAS_AMD} NVIDIA=${HAS_NVIDIA}"

    # --- Intel : iHD (Gen8+) + i965 (vieux Intel <= Gen9) + outils ---
    if [[ "$HAS_INTEL" -eq 1 ]]; then
        dnf_install_one intel-media-driver   # iHD (Iris Xe / Tiger Lake+, Gen8+)
        dnf_install_one libva-intel-driver   # i965, couvre les Intel <= Gen9
        dnf_install_one intel-gpu-tools      # 'intel_gpu_top'
    fi

    # --- AMD : swap vers les drivers freeworld (codecs H.264/H.265 patentes) ---
    # mesa-va-drivers est deja installe (tire par Mesa) mais ampute des codecs
    # brevetes -> 'dnf swap' (PAS 'install' qui ferait un conflit de fichiers).
    if [[ "$HAS_AMD" -eq 1 ]]; then
        if rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
            log_ok "mesa-va-drivers-freeworld (deja la)"
        else
            log_info "Swap mesa-va/vdpau-drivers -> freeworld (codecs AMD)..."
            local log; log=$(new_log_file "dnf_swap_mesa_amd")
            if sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld >"$log" 2>&1 \
               && sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld >>"$log" 2>&1; then
                log_ok "Drivers Mesa freeworld (AMD)"; rm -f "$log"
            else
                log_err "Echec swap Mesa freeworld (log : $log)"
                register_failure "dnf" "mesa-*-freeworld" "swap failed" "$log"
            fi
        fi
        dnf_install_one radeontop            # monitoring GPU AMD
    fi

    # --- NVIDIA : NON automatise (branche driver selon modele, akmod, signature
    # Secure Boot, reboot). On previent + on pointe l'etape manuelle. ---
    if [[ "$HAS_NVIDIA" -eq 1 ]]; then
        log_warn "GPU NVIDIA detecte : install driver NON automatisee."
        log_warn "  Manuel : sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-vaapi-driver"
        log_warn "  Puis attendre le build akmod ('akmods --rebuild') + reboot."
    fi

    if [[ "$HAS_INTEL" -eq 0 && "$HAS_AMD" -eq 0 && "$HAS_NVIDIA" -eq 0 ]]; then
        log_warn "Aucun GPU Intel/AMD/NVIDIA detecte (VM ? lspci absent ?) : skip"
    fi
}

# ============================================================
# Optimisations hardware (thermald Intel-only + Flatpak VA-API par vendor)
# ============================================================
#
# Se charge de :
# - thermald : pose + active SEULEMENT si CPU Intel (sur AMD c'est amd_pstate,
#   gere par le noyau -> rien a installer).
# - extensions Flatpak VAAPI selon le vendor (Intel / nvidia ; rien pour AMD).
#
# S'appuie sur les flags HAS_* poses par detect_gpu_vendors(). Idempotent.

configure_hardware_optimization() {
    section "Optimisations hardware (thermald + Flatpak VA-API)"

    # --- thermald (Intel uniquement) ---
    if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then
        dnf_install_one thermald
        if rpm -q thermald >/dev/null 2>&1; then
            if systemctl is-enabled --quiet thermald 2>/dev/null \
                && systemctl is-active --quiet thermald 2>/dev/null; then
                log_ok "thermald deja active et demarre"
            else
                log_info "Enable + start de thermald..."
                local log; log=$(new_log_file "systemd_thermald")
                if sudo systemctl enable --now thermald >"$log" 2>&1; then
                    log_ok "thermald enable + active"
                    rm -f "$log"
                else
                    log_err "Echec enable thermald (log : $log)"
                    register_failure "systemd" "thermald" "enable failed" "$log"
                fi
            fi
        fi
    else
        log_ok "CPU non-Intel : thermald non requis (amd_pstate gere par le noyau)"
    fi

    # --- Extensions Flatpak VAAPI (selon vendor) ---
    #  Intel  -> org.freedesktop.Platform.VAAPI.Intel
    #  NVIDIA -> org.freedesktop.Platform.VAAPI.nvidia
    #  AMD    -> AUCUNE (l'accel passe par le runtime GL.default, present d'office)
    if command -v flatpak >/dev/null 2>&1; then
        local vaapi_ext=""
        [[ "$HAS_INTEL" -eq 1 ]] && vaapi_ext="org.freedesktop.Platform.VAAPI.Intel"
        [[ "$HAS_NVIDIA" -eq 1 && "$HAS_INTEL" -eq 0 ]] && vaapi_ext="org.freedesktop.Platform.VAAPI.nvidia"

        if [[ -n "$vaapi_ext" ]]; then
            local vaapi_versions=("24.08" "25.08")
            for ver in "${vaapi_versions[@]}"; do
                if flatpak list --user --columns=application,branch 2>/dev/null \
                    | awk -v e="$vaapi_ext" -v v="$ver" '$1==e && $2==v {found=1} END{exit !found}'; then
                    log_ok "${vaapi_ext} ${ver} (user) deja installe"
                else
                    log_info "Installation ${vaapi_ext} ${ver}..."
                    local log; log=$(new_log_file "flatpak_vaapi_${ver}")
                    if flatpak install --user -y --noninteractive flathub \
                            "${vaapi_ext}//${ver}" >"$log" 2>&1; then
                        log_ok "${vaapi_ext} ${ver}"
                        rm -f "$log"
                    else
                        log_warn "Pas reussi a installer ${vaapi_ext} ${ver} (version peut-etre EOL)"
                        rm -f "$log"
                    fi
                fi
            done
        elif [[ "$HAS_AMD" -eq 1 ]]; then
            log_ok "AMD : pas d'extension VAAPI Flatpak (runtime GL.default suffit)"
        fi
    else
        log_warn "flatpak absent : skip extensions VAAPI"
    fi

    # Messages de verif conditionnes au vendor
    if [[ "$HAS_INTEL" -eq 1 ]]; then
        log_info "Verifier VA-API : 'vainfo' (ou 'LIBVA_DRIVER_NAME=iHD vainfo')"
        log_info "Monitorer GPU : 'intel_gpu_top'"
    elif [[ "$HAS_AMD" -eq 1 ]]; then
        log_info "Verifier VA-API : 'vainfo' ; monitorer GPU : 'radeontop'"
    else
        log_info "Verifier VA-API : 'vainfo'"
    fi
    log_info "Profiler conso : 'sudo powertop'"
}

# ============================================================
# Biometrie (empreinte digitale) : PAM + enrolement
# ============================================================
#
# Active la prise en charge de l'empreinte pour GDM (login) et sudo, de facon
# idempotente. L'ENROLEMENT lui-meme (fprintd-enroll) est interactif (swipe
# physique) -> non automatisable : on affiche juste la consigne.
#
# Warning ELAN conditionnel : certains capteurs ELAN *touch* sont geres a tort
# en mode *swipe* par libfprint -> doigt immobile = crash 'enroll-disconnected'.

configure_fingerprint() {
    section "Biometrie (empreinte digitale)"

    # Detection generique du capteur (aucun ID en dur). lsusb : on repere une
    # ligne "fingerprint" ou un vendor connu de capteurs.
    local fp_line
    fp_line=$(lsusb 2>/dev/null | grep -iE 'fingerprint|fpc|elan|goodix|synaptics|validity')
    if [[ -z "$fp_line" ]]; then
        log_warn "Aucun capteur d'empreinte detecte : etape sautee."
        return 0
    fi
    log_ok "Capteur d'empreinte detecte"

    # 1. Activer le PAM biometrie via authselect (idempotent).
    if authselect current 2>/dev/null | grep -q with-fingerprint; then
        log_ok "PAM empreinte (with-fingerprint) deja active"
    else
        log_info "Activation du PAM empreinte (authselect)..."
        local log; log=$(new_log_file "authselect_fingerprint")
        if sudo authselect enable-feature with-fingerprint >"$log" 2>&1; then
            log_ok "PAM empreinte active (GDM + sudo)"
            rm -f "$log"
        else
            log_err "Echec authselect enable-feature with-fingerprint (log : $log)"
            register_failure "authselect" "with-fingerprint" "enable failed" "$log"
        fi
    fi

    # 2. Enrolement : interactif, non automatisable. On guide seulement.
    if fprintd-list "$USER" 2>/dev/null | grep -q 'Fingerprints'; then
        log_ok "Empreinte deja enrolee pour ${USER}"
    else
        log_warn "Aucune empreinte enrolee. Pour enroler (interactif) :"
        log_warn "    fprintd-enroll"
        if grep -qi '04f3' <<<"$fp_line"; then
            log_warn "  /!\\ Capteur ELAN : bug libfprint 'swipe'. NE garde PAS le doigt"
            log_warn "      immobile (crash 'enroll-disconnected'). GLISSE lentement le"
            log_warn "      doigt du haut vers le bas sur le bouton d'alimentation."
        else
            log_warn "  Pose/releve le doigt plusieurs fois comme demande a l'ecran."
        fi
    fi
}

# ============================================================
# Liaison LUKS2 + TPM2 (boot sans passphrase, avec PIN) -- OPT-IN
# ============================================================
#
# Lance UNIQUEMENT avec './setup.sh --enroll-tpm' (touche au chiffrement disque,
# exige la passphrase LUKS en interactif). Lie la cle LUKS au TPM2 sur PCR 0+7
# avec un PIN -> au boot, on tape juste le PIN (plus la passphrase). Le keyslot
# passphrase d'origine est CONSERVE comme fallback de secours.
#
# 3 effets de bord = 3 idempotences independantes (cf. lecon bug .desktop Toolbox
# du 2026-05-23) : module dracut / keyslot TPM / options crypttab.
#
# /!\ PCR 0 (firmware) : une MAJ BIOS invalide le deverrouillage auto -> il faut
# re-enroler (cf. print_manual_steps). Une seule tentative de PIN au boot : en
# cas d'erreur, taper la passphrase LUKS d'origine.

enroll_luks_tpm() {
    section "Liaison LUKS2 + TPM2 (boot par PIN) [opt-in]"

    # Detection partition LUKS (aucun chemin en dur).
    local luks_part
    luks_part=$(lsblk -rno NAME,FSTYPE 2>/dev/null \
        | awk '$2=="crypto_LUKS"{print "/dev/"$1; exit}')
    if [[ -z "$luks_part" ]]; then
        log_warn "Pas de partition LUKS detectee : active le chiffrement a"
        log_warn "l'installation de Fedora (Anaconda). Etape sautee (pas un echec)."
        return 0
    fi
    log_ok "Partition LUKS : ${luks_part}"

    if [[ ! -e /dev/tpmrm0 ]]; then
        log_warn "Pas de TPM (/dev/tpmrm0 absent) : etape sautee."
        return 0
    fi

    # --- Etape A : module dracut tpm2-tss (AVANT dracut), idempotent ---
    local dracut_conf=/etc/dracut.conf.d/tpm2.conf
    if sudo test -f "$dracut_conf" && sudo grep -q 'tpm2-tss' "$dracut_conf" 2>/dev/null; then
        log_ok "Module dracut tpm2-tss deja configure"
    else
        log_info "Ajout du module dracut tpm2-tss..."
        if echo 'add_dracutmodules+=" tpm2-tss "' | sudo tee "$dracut_conf" >/dev/null; then
            log_ok "Module dracut tpm2-tss configure"
        else
            log_err "Echec ecriture ${dracut_conf}"
            register_failure "tpm" "dracut tpm2-tss" "write failed"
            return 1
        fi
    fi

    # --- Etape B : enrolement keyslot TPM (idempotent via luksDump) ---
    if sudo cryptsetup luksDump "$luks_part" 2>/dev/null | grep -q systemd-tpm2; then
        log_ok "Keyslot TPM2 deja present dans ${luks_part}"
    else
        log_info "Enrolement TPM2 (PCR 0+7 + PIN). Tape ta passphrase LUKS puis cree le PIN :"
        if sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 \
                --tpm2-with-pin=yes "$luks_part"; then
            log_ok "Keyslot TPM2 enrole (passphrase conservee en fallback)"
        else
            log_err "Echec systemd-cryptenroll"
            register_failure "tpm" "systemd-cryptenroll" "enroll failed"
            return 1
        fi
    fi

    # --- Etape C : /etc/crypttab (tpm2-device + tpm2-pin), idempotent ---
    local uuid map_name
    uuid=$(blkid -s UUID -o value "$luks_part" 2>/dev/null)
    map_name="luks-${uuid}"
    if sudo grep -qE "^[[:space:]]*${map_name}\b.*tpm2-pin=yes" /etc/crypttab 2>/dev/null; then
        log_ok "/etc/crypttab deja configure (tpm2-device + tpm2-pin)"
    else
        log_info "Mise a jour de /etc/crypttab (tpm2-device=auto,tpm2-pin=yes)..."
        # Ajoute aux options existantes de la ligne du mapping. Le 4e champ peut
        # valoir 'none' (remplace) ou contenir des options (append).
        if sudo awk -v m="$map_name" '
            $1==m {
                if (NF<4 || $4=="none" || $4=="") { $4="tpm2-device=auto,tpm2-pin=yes" }
                else if ($4 !~ /tpm2-device/) { $4=$4",tpm2-device=auto,tpm2-pin=yes" }
            }
            { print }
        ' /etc/crypttab | sudo tee /etc/crypttab.tmp >/dev/null \
           && sudo mv /etc/crypttab.tmp /etc/crypttab; then
            log_ok "/etc/crypttab mis a jour"
        else
            log_err "Echec mise a jour /etc/crypttab"
            register_failure "tpm" "crypttab" "update failed"
            return 1
        fi
    fi

    # --- Etape D : regenerer TOUS les initramfs (pas seulement le courant) ---
    log_info "Regeneration des initramfs (dracut --regenerate-all)..."
    local log; log=$(new_log_file "dracut_tpm2")
    if sudo dracut --regenerate-all --force >"$log" 2>&1; then
        log_ok "Initramfs regeneres"
        rm -f "$log"
    else
        log_err "Echec dracut --regenerate-all (log : $log)"
        register_failure "tpm" "dracut" "regenerate failed" "$log"
        return 1
    fi

    log_info "Reboot pour tester : le boot doit demander le PIN (pas la passphrase)."
    log_warn "Une seule tentative de PIN : en cas d'erreur, tape ta passphrase LUKS."
}

# ============================================================
# Configuration clavier (layout French alt + shift-lock)
# ============================================================
#
# - Layout : fr+oss = "French (alt.)" / "Francais - Variante" (chiffres directs
#   sur la rangee haute en mode Shift, vrais caracteres « » œ æ accessibles
#   via AltGr, vrais guillemets, etc.)
# - Shift-Lock : Caps Lock devient un vrai verrouillage Shift (= Maj
#   permanente). Tres pratique en azerty pour taper une serie de chiffres
#   sans tenir Shift, ou pour taper EN MAJUSCULES.
#
# Idempotent : gsettings set est sans effet si la valeur est deja celle voulue.

configure_keyboard() {
    section "Configuration clavier (fr+oss + shift-lock)"

    if ! command -v gsettings >/dev/null 2>&1; then
        log_warn "gsettings absent : configuration clavier sautee (pas GNOME ?)"
        return
    fi

    # 1. Layout : fr+oss
    local desired_sources="[('xkb', 'fr+oss')]"
    local current_sources
    current_sources=$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || echo "")

    if [[ "$current_sources" == "$desired_sources" ]]; then
        log_ok "Layout clavier deja fr+oss"
    else
        if gsettings set org.gnome.desktop.input-sources sources "$desired_sources" 2>/dev/null; then
            log_ok "Layout clavier -> fr+oss (French alt.)"
        else
            log_err "Echec gsettings set sources"
            register_failure "gsettings" "input-sources/sources" "set failed"
        fi
    fi

    # 2. Shift-Lock sur Caps Lock
    local desired_options="['caps:shiftlock']"
    local current_options
    current_options=$(gsettings get org.gnome.desktop.input-sources xkb-options 2>/dev/null || echo "")

    # NB : on accepte la presence de caps:shiftlock parmi d'autres options
    # (au cas ou l'utilisateur en a ajoute manuellement)
    if [[ "$current_options" == *"caps:shiftlock"* ]]; then
        log_ok "Shift-lock (caps:shiftlock) deja active"
    else
        if gsettings set org.gnome.desktop.input-sources xkb-options "$desired_options" 2>/dev/null; then
            log_ok "Shift-lock active (Caps Lock = verrouillage Shift)"
        else
            log_err "Echec gsettings set xkb-options"
            register_failure "gsettings" "input-sources/xkb-options" "set failed"
        fi
    fi
}

# ============================================================
# Extensions GNOME via gnome-extensions-cli (gext)
# ============================================================
#
# Installe gext via pipx, puis chaque extension listee.
# IMPORTANT : --system-site-packages obligatoire (sinon gext ne peut pas
# acceder a PyGObject pour parler a GNOME Shell via DBus -> plante).
#
# Limitation Wayland : 'gext enable' echoue tant que la session GNOME n'a
# pas ete redemarree (logout/login) entre l'install et l'enable, parce que
# GNOME Shell ne recharge pas a chaud sa liste d'extensions. Donc sur le
# 1er run d'un PC fresh : install OK mais enable -> log_warn. Apres logout/
# login, relancer le script -> il completera l'enable (idempotent).
#
# Format de chaque entree : "id:uuid:nom_affiche"

GNOME_EXTENSIONS=(
    "779:clipboard-indicator@tudmotu.com:Clipboard Indicator"
)

# Extensions fournies par un paquet dnf (gnome-shell-extension-*), PAS par
# extensions.gnome.org. On ne fait donc PAS 'gext install' dessus : ca tirerait
# d'EGO une version potentiellement desynchronisee de GNOME 50, alors que le
# paquet dnf est deja maintenu en phase avec la version de GNOME du systeme.
# On se contente de les ACTIVER (gext enable).
# Format de chaque entree : "uuid:nom_affiche"
GNOME_EXTENSIONS_ENABLE_ONLY=(
    "appindicatorsupport@rgcjonas.gmail.com:AppIndicator Support (icone systray Dropbox, etc.)"
)

install_gnome_extensions() {
    section "Extensions GNOME (Clipboard Indicator, AppIndicator, ...)"

    if ! command -v pipx >/dev/null 2>&1; then
        log_warn "pipx absent (devrait etre dans DNF_PACKAGES) : etape sautee"
        return
    fi

    # ---- 1. Installer gext via pipx (idempotent) ----
    if command -v gext >/dev/null 2>&1; then
        log_ok "gnome-extensions-cli deja installe"
    else
        log_info "Installation de gnome-extensions-cli via pipx..."
        local log; log=$(new_log_file "pipx_gext")
        # --system-site-packages : indispensable pour acceder aux bindings
        # PyGObject installes au niveau systeme (com DBus avec GNOME Shell).
        if pipx install gnome-extensions-cli --system-site-packages >"$log" 2>&1; then
            log_ok "gnome-extensions-cli installe"
            rm -f "$log"
            # Refresh du PATH pour cette session (pipx ensurepath modifie
            # .bashrc mais le shell courant n'est pas reloade)
            export PATH="$HOME/.local/bin:$PATH"
        else
            log_err "gnome-extensions-cli : echec install (log : $log)"
            register_failure "pipx" "gnome-extensions-cli" "install failed" "$log"
            return
        fi
    fi

    # Verifier qu'on peut bien appeler gext maintenant
    if ! command -v gext >/dev/null 2>&1; then
        log_err "gext introuvable dans PATH apres install pipx"
        register_failure "pipx" "gnome-extensions-cli" "not in PATH after install"
        return
    fi

    # ---- 2. Installer + activer chaque extension ----
    local enable_failed=0
    for entry in "${GNOME_EXTENSIONS[@]}"; do
        local id="${entry%%:*}"
        local rest="${entry#*:}"
        local uuid="${rest%%:*}"
        local name="${rest#*:}"

        # 2a. Install (idempotent : gext install verifie juste les MAJ)
        local log; log=$(new_log_file "gext_install_${id}")
        if gext install "$id" >"$log" 2>&1; then
            log_ok "Extension installee : ${name}"
            rm -f "$log"
        else
            log_err "Echec install extension ${name} (log : $log)"
            register_failure "gext" "${uuid}" "install failed" "$log"
            continue
        fi

        # 2b. Tente d'enable. Sur Wayland + 1er run = echec attendu.
        local enable_log; enable_log=$(new_log_file "gext_enable_${id}")
        if gext enable "$uuid" >"$enable_log" 2>&1; then
            log_ok "Extension activee : ${name}"
            rm -f "$enable_log"
        else
            log_warn "Activation de ${name} impossible pour l'instant (cf. note ci-dessous)"
            enable_failed=1
            rm -f "$enable_log"
        fi
    done

    # ---- 2bis. Activer les extensions fournies par dnf (enable seul) ----
    # On ne fait PAS 'gext install' (cf. note sur GNOME_EXTENSIONS_ENABLE_ONLY).
    # Check de presence : on teste le DOSSIER sur disque, pas 'gnome-extensions
    # info' qui echoue au 1er run tant que le Shell n'a pas rescanne /usr/share
    # (faux negatif "paquet manquant" alors que le paquet dnf est bien la).
    for entry in "${GNOME_EXTENSIONS_ENABLE_ONLY[@]}"; do
        local uuid="${entry%%:*}"
        local name="${entry#*:}"

        if [[ ! -d "/usr/share/gnome-shell/extensions/$uuid" \
           && ! -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]]; then
            log_warn "Extension ${name} absente du disque (paquet dnf manquant ?) : skip"
            continue
        fi

        # Tente d'enable. Sur Wayland + session non rescannee = echec attendu,
        # traite comme les autres (logout/login puis relance du script).
        local enable_log; enable_log=$(new_log_file "gext_enable_${uuid//[^a-zA-Z0-9]/_}")
        if gext enable "$uuid" >"$enable_log" 2>&1; then
            log_ok "Extension activee : ${name}"
            rm -f "$enable_log"
        else
            log_warn "Activation de ${name} impossible pour l'instant (cf. note ci-dessous)"
            enable_failed=1
            rm -f "$enable_log"
        fi
    done

    if [[ "$enable_failed" -eq 1 ]]; then
        log_warn ""
        log_warn "  Limitation Wayland : GNOME Shell ne recharge pas a chaud la liste"
        log_warn "  des extensions. Deconnecte/reconnecte ta session, puis :"
        log_warn "    ./setup.sh       # idempotent, completera l'activation"
        log_warn "  (ou active manuellement : gext enable <UUID>)"
    fi
}

# ============================================================
# Etapes manuelles (affichage)
# ============================================================

print_manual_steps() {
    section "Etapes manuelles restantes"

    cat <<'EOF'

  [ ] Reload du shell : "source ~/.bashrc" ou nouvelle session
                        (pour PATH npm-global + DOCKER_HOST + SDKMAN)

  [ ] PostgreSQL      : mot de passe SUPERUSER non defini par defaut.
                        - sudo -iu postgres psql
                        - ALTER USER postgres WITH PASSWORD '<nouveau>';
                        - Editer /var/lib/pgsql/data/pg_hba.conf pour passer
                          'ident' -> 'scram-sha-256' sur les lignes locales,
                          puis : sudo systemctl restart postgresql

  [ ] MariaDB         : lancer sudo mariadb-secure-installation (interactif)
                        pour definir le password root + retirer test DB.

  [ ] MongoDB         : par defaut bind 127.0.0.1, sans auth. Pour activer
                        l'auth : editer /etc/mongod.conf + redemarrer.
                        Verifier : systemctl status mongod

  [ ] Podman          : socket actif a $XDG_RUNTIME_DIR/podman/podman.sock
                        DOCKER_HOST exporte dans ~/.bashrc.
                        Test : docker run hello-world  (alias podman-docker)

  [ ] Antigravity IDE : DL manuel sur https://antigravity.google/download
                        Post-Google I/O 2026 (19 mai 2026), la marque
                        Antigravity regroupe 4 surfaces :
                          - Antigravity 2.0 : app desktop d'orchestration d'agents
                          - Antigravity CLI : terminal (deja installe via curl)
                          - Antigravity SDK : programmation d'agents custom
                          - Antigravity IDE : l'IDE historique (Nov 2025)
                        Un repo RPM tiers existe (us-central1-yum.pkg.dev) mais
                        avec gpgcheck=0 et 'dev' dans l'URL -> on attend un
                        canal officiel signe par Google avant de l'integrer.

  [ ] Marvin          -> https://amazingmarvin.com (AppImage)
  [ ] Freedom         -> https://freedom.to
  [ ] Mem.ai          -> https://mem.ai (web ou Electron)

  [ ] Git identite    : options + alias deja configures par le script.
                        Reste a definir l'identite :
                          git config --global user.name "..."
                          git config --global user.email "..."

  [ ] Authent CLI IA  : claude (login interactif)
                        codex auth
                        agy auth     (Antigravity CLI - successeur Gemini CLI)

  [ ] JetBrains Toolbox: lance-le depuis GNOME Activities (icone "JetBrains
                        Toolbox") ou avec :
                          ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox
                        Login JetBrains + install IDEA Community depuis l'UI.
                        Toolbox 1.25+ active "shell scripts" par defaut, donc
                        la commande 'idea' sera dispo dans le terminal apres
                        ouverture d'un nouveau shell.

  [ ] Empreinte       : si capteur present, enroler (interactif) :
                          fprintd-enroll
                        /!\ Capteur ELAN : bug libfprint 'swipe' -> GLISSE lentement
                            le doigt (haut->bas) sur le bouton d'alim, ne le laisse
                            PAS immobile (crash 'enroll-disconnected').

  [ ] Deverr. TPM     : (opt-in) boot par PIN au lieu de la passphrase LUKS :
                          ./setup.sh --enroll-tpm        (demande passphrase + PIN)
                        PCR 0+7 : apres une MAJ BIOS (fwupdmgr), re-enroler :
                          LUKS=$(lsblk -rno NAME,FSTYPE | awk '$2=="crypto_LUKS"{print "/dev/"$1; exit}')
                          sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
                               --tpm2-pcrs=0+7 --tpm2-with-pin=yes "$LUKS"
                          sudo dracut --regenerate-all --force

  [ ] Hardware verif  : verifier que les optims sont bien en place :
                          - vainfo                         (HW video decode OK ?)
                          - intel_gpu_top / radeontop      (GPU detecte, selon vendor)
                          - systemctl status thermald      (Intel : daemon thermique up ?)
                          - powertop --html=/tmp/pwr.html  (profilage conso initial)
                        Firefox : about:support -> chercher 'HARDWARE_VIDEO_DECODING'
                                  -> doit dire 'available by default'
                        Chrome  : chrome://gpu -> 'Video Decode' = 'Hardware accelerated'

  [ ] Firmware (BIOS) : la plupart des constructeurs (ASUS, Dell, Lenovo...) publient
                        sur LVFS. Lance une fois :
                          sudo fwupdmgr refresh
                          fwupdmgr get-devices       (voir ce qui est detecte)
                          sudo fwupdmgr update       (applique les MAJ dispo)
                        NB : peut demander un reboot, ne pas lancer en plein boulot.

  [ ] OLED screen care: SI ecran OLED (anti-burn-in) :
                          - Settings > Privacy > Screen Lock : blank apres 5-10 min
                          - Settings > Appearance : Dark mode (pixels noirs = eteints)
                          - Eventuellement installer l'extension 'Hide Top Bar'
                            (gext install 545 ; UUID hidetopbar@mathieu.bidon.ca)

  [ ] Steam           : 1er lancement va DL ~200 MB de runtimes Proton.

  [ ] Extensions GNOME: si Clipboard Indicator n'apparait pas dans la barre
                        du haut (icone presse-papier) apres un peu d'attente :
                          - Deconnecte/reconnecte ta session GNOME
                          - Relance ./setup.sh (idempotent : completera l'enable)
                        Raccourci par defaut : Super+V pour afficher l'historique.
                        Configurable dans Settings > Extensions > Clipboard
                        Indicator > Settings.

EOF
}

# ============================================================
# Recap des echecs
# ============================================================

print_recap_and_exit() {
    if [[ ${#FAILURES[@]} -eq 0 ]]; then
        section "Termine"
        log_ok "Toutes les installations ont reussi."
        echo
        exit 0
    fi

    echo
    echo "${C_RED}###############################################${C_RESET}"
    echo "${C_RED}#                                             #${C_RESET}"
    printf "${C_RED}#   ECHEC(S) D'INSTALLATION : %-15s #${C_RESET}\n" "${#FAILURES[@]}"
    echo "${C_RED}#                                             #${C_RESET}"
    echo "${C_RED}###############################################${C_RESET}"
    echo

    # Regroupe par type pour lisibilite
    declare -A by_type
    for entry in "${FAILURES[@]}"; do
        local type=${entry%%|*}
        by_type[$type]+="${entry}"$'\n'
    done

    for type in "${!by_type[@]}"; do
        local count
        count=$(echo -n "${by_type[$type]}" | grep -c .)
        echo "${C_RED}  --- ${type^^} (${count}) ---${C_RESET}"
        while IFS='|' read -r _ pkg reason log; do
            [[ -z "$pkg" ]] && continue
            echo "${C_RED}    * ${pkg}${C_RESET}"
            echo "${C_DIM}        Raison : ${reason}${C_RESET}"
            if [[ -n "$log" ]]; then
                echo "${C_DIM}        Log    : ${log}${C_RESET}"
            fi
        done <<< "${by_type[$type]}"
        echo
    done

    echo "${C_YELLOW}  Verifier les logs ci-dessus puis relancer le script${C_RESET}"
    echo "${C_YELLOW}  (idempotent : ne reinstalle pas ce qui est OK).${C_RESET}"
    echo
    echo "${C_YELLOW}  Pour voir un log :  less <chemin du log>${C_RESET}"
    echo

    exit 2
}

# ============================================================
# Main
# ============================================================

main() {
    check_prerequisites
    update_system
    install_rpmfusion
    add_third_party_repos
    install_dnf_packages
    install_hardware_packages
    setup_flathub
    install_flatpak_apps
    install_jetbrains_toolbox
    install_sdkman
    install_jdks_via_sdkman
    setup_npm_userspace
    install_npm_globals
    install_antigravity_cli
    configure_services
    configure_git
    configure_gitignore_global
    configure_git_perso_identity
    configure_shell_aliases
    configure_hardware_optimization
    configure_keyboard
    configure_fingerprint
    install_gnome_extensions
    print_manual_steps
    print_recap_and_exit
}

# Mode opt-in : liaison LUKS+TPM uniquement (rien d'autre). Lance avec
# './setup.sh --enroll-tpm'. check_prerequisites cache le sudo + verifie Fedora.
enroll_tpm_mode() {
    check_prerequisites
    enroll_luks_tpm
    print_recap_and_exit
}

# ============================================================
# Self-logging + dispatch
# ============================================================
#
# Re-exec sous script(1) (util-linux) pour capturer TOUT le run dans un fichier
# d'etat fixe, exit code inclus, SANS perdre le TTY (couleurs + prompts sudo/PIN
# interactifs preserves). La garde WS_LOGGING evite la boucle infinie. C'est ce
# fichier que Claude Code lit pour diagnostiquer les erreurs.

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation-setup"
mkdir -p "$LOG_DIR" 2>/dev/null
LOGFILE="$LOG_DIR/last-run.log"

if [[ -z "${WS_LOGGING:-}" ]]; then
    if command -v script >/dev/null 2>&1; then
        export WS_LOGGING=1
        script -q -e -c "$0 $*" "$LOGFILE"
        rc=$?
        printf 'EXIT=%s\n' "$rc" | tee -a "$LOGFILE"
        exit "$rc"
    fi
    # Fallback (script absent) : run direct, sans log fichier.
    echo "[!] 'script' (util-linux) absent : pas de last-run.log ce run." >&2
fi

case "${1:-}" in
    --enroll-tpm) enroll_tpm_mode ;;
    *)            main "$@" ;;
esac
#!/usr/bin/env bash
#
# bootstrap.sh — Amorcage d'un PC Fedora vierge.
#
# A lancer EN PREMIER sur une machine fraiche, avant setup.sh. Il :
#   1. installe git (si absent)
#   2. clone le repo workstation-setup dans ~/code (idempotent)
#   3. installe Claude Code en NATIF (curl officiel, sans Node, auto-update)
#   4. affiche les etapes suivantes
#
# Recuperation sur PC vierge (le seul fetch manuel) :
#   curl -fsSL https://raw.githubusercontent.com/Gdpgt/workstation-setup/main/Notes_changement_pc_LINUX/bootstrap.sh | bash
#
# Contrairement a setup.sh (qui evite 'set -e' pour continuer apres un echec de
# paquet), bootstrap est court et chaque etape est un pre-requis de la suivante :
# on s'arrete au premier echec.

set -euo pipefail

REPO_URL="https://github.com/Gdpgt/workstation-setup.git"
REPO_DIR="$HOME/code/workstation-setup"

if [[ -t 1 ]]; then
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
    C_GREEN='' C_YELLOW='' C_CYAN='' C_RESET=''
fi
info() { echo "${C_CYAN}--> $*${C_RESET}"; }
ok()   { echo "${C_GREEN}[OK] $*${C_RESET}"; }
warn() { echo "${C_YELLOW}[!]  $*${C_RESET}"; }

# --- Pre-requis minimal : curl (normalement present sur Workstation) ---
if ! command -v curl >/dev/null 2>&1; then
    warn "curl absent : installation..."
    sudo dnf install -y curl
fi

# --- 1. git ---
if command -v git >/dev/null 2>&1; then
    ok "git deja installe"
else
    info "Installation de git (sudo demande)..."
    sudo dnf install -y git
    ok "git installe"
fi

# --- 2. Clone idempotent (jamais de pull aveugle : Claude edite setup.sh) ---
if [[ -d "$REPO_DIR/.git" ]]; then
    info "Repo deja present : tentative de mise a jour (fast-forward only)..."
    git -C "$REPO_DIR" pull --ff-only || warn "pull impossible (modifs locales ?) — on garde l'existant"
    ok "Repo a jour : $REPO_DIR"
else
    info "Clone du repo dans $REPO_DIR ..."
    mkdir -p "$HOME/code"
    git clone "$REPO_URL" "$REPO_DIR"
    ok "Repo clone : $REPO_DIR"
fi

# --- 3. Claude Code natif (sans Node, auto-update) ---
if command -v claude >/dev/null 2>&1; then
    ok "Claude Code deja installe ($(command -v claude))"
else
    info "Installation de Claude Code (natif)..."
    curl -fsSL https://claude.ai/install.sh | bash
    # L'installer pose le binaire dans ~/.local/bin (pas dans le PATH du shell
    # courant tant qu'on n'a pas relance une session de login).
    export PATH="$HOME/.local/bin:$PATH"
    if command -v claude >/dev/null 2>&1; then
        ok "Claude Code installe ($(command -v claude))"
    else
        warn "claude pas encore dans le PATH de cette session (normal)."
    fi
fi

# --- 4. Etapes suivantes ---
echo
echo "${C_GREEN}===============================================${C_RESET}"
echo "${C_GREEN}  Bootstrap termine.${C_RESET}"
echo "${C_GREEN}===============================================${C_RESET}"
cat <<EOF

  Etapes suivantes :

  1. Ouvre un NOUVEAU terminal (pour que 'claude' soit dans le PATH),
     ou : exec bash

  2. cd $REPO_DIR

  3. claude
       -> login (compte Claude Pro / Max / Team / Enterprise / Console REQUIS ;
          le plan gratuit ne donne PAS acces a Claude Code)

  4. Provisionne le PC. Modele recommande : TOI tu lances le script, Claude
     repare les erreurs.
       ./setup.sh
     Si exit 2, demande a Claude :
       "lis ~/.local/state/workstation-setup/last-run.log (et /tmp/setup_*)
        et corrige les erreurs, je relance"

  5. Etapes opt-in / interactives (a lancer toi-meme) :
       ./setup.sh --enroll-tpm     # boot LUKS par PIN (passphrase + PIN demandes)
       fprintd-enroll              # empreinte digitale

EOF

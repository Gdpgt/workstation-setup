#!/usr/bin/env bash
#
# update-java.sh — maintenance des JDK Temurin installes via SDKMAN.
#
# Pour CHAQUE version majeure deja installee, passe au dernier "update release"
# de cette meme majeure (ex. 25.0.3 -> 25.0.4), puis supprime les versions
# obsoletes de cette majeure. Ne change JAMAIS de majeure tout seul : 21 -> 25
# est une decision projet, pas de la maintenance.
#
# Si aucun JDK Temurin n'est installe : pose la derniere LTS disponible.
#
# Maintient aussi des ALIAS STABLES par majeure dans ~/.local/share/jdks/ :
#   17 -> ~/.sdkman/candidates/java/17.0.20-tem
#   21 -> ~/.sdkman/candidates/java/21.0.12+1.1-tem
#   25 -> ~/.sdkman/candidates/java/25.0.4-tem
# A declarer une fois dans IntelliJ (Project Structure > SDKs) et LibreOffice :
# ces chemins survivent a toutes les mises a jour de patch.
#
# Sans argument : DRY-RUN, n'ecrit rien, affiche seulement ce qui serait fait.
# Avec --apply   : applique reellement.
#
# Rappel versioning (JEP 322) : FEATURE.INTERIM.UPDATE.PATCH. Entre deux
# updates d'une meme majeure il n'y a que du correctif de securite/bug, jamais
# de rupture d'API -> rester au dernier update est toujours le bon choix.
#
# ---------------------------------------------------------------------------
# DEUX PIEGES SDKMAN que ce script neutralise (vus le 2026-09-08) :
#
# 1. 'sdk' est une fonction shell, pas un binaire, et elle lit des variables
#    non definies ($USE dans sdkman-install.sh:39-43, $ZSH_VERSION dans
#    sdkman-init.sh). Sous 'set -u' cela tue le processus ENTIER, meme depuis
#    l'interieur d'un 'if ! sdk install ...'. -> tous les appels passent par
#    sdk_safe(), qui desactive 'set -u' le temps de la commande.
#
# 2. Avec 'sdkman_auto_answer=true' (le cas ici, cf. ~/.sdkman/etc/config),
#    TOUT 'sdk install java <X>' repointe silencieusement le lien 'current'
#    sur <X>, sans poser de question -- y compris a travers un changement de
#    majeure. On ne peut donc pas se fier a un snapshot du defaut pris avant
#    la boucle. -> le defaut est explicitement repositionne a la fin, sur la
#    MAJEURE d'origine.
# ---------------------------------------------------------------------------

set -uo pipefail

LTS_MAJORS=(8 11 17 21 25 29 33)
API_URL="https://api.sdkman.io/2/candidates/java/linuxx64/versions/list?installed="
JDK_DIR="${JDK_DIR:-}"   # vide -> derive de SDKMAN_DIR apres init
# Alias stables par majeure : ~/.local/share/jdks/{17,21,25} -> version concrete.
# C'est CES chemins qu'il faut declarer dans IntelliJ / LibreOffice : ils ne
# changent jamais, alors que ".../java/25.0.4-tem" devient invalide a chaque MAJ.
ALIAS_DIR="${ALIAS_DIR:-$HOME/.local/share/jdks}"

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1
changed=0

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
info() { printf '%s\n' "$*"; }
ok()   { printf '%s[OK]%s   %s\n' "$c_ok"   "$c_off" "$*"; }
warn() { printf '%s[!]%s    %s\n' "$c_warn" "$c_off" "$*"; }
err()  { printf '%s[ERR]%s  %s\n' "$c_err"  "$c_off" "$*"; }
act()  { if (( APPLY )); then printf '  -> %s\n' "$*"; else printf '  -> %s(dry-run)%s %s\n' "$c_dim" "$c_off" "$*"; fi; }

# --- Init SDKMAN (piege 1 : 'set -u' incompatible avec les scripts SDKMAN) ---
export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] || { err "SDKMAN introuvable dans $SDKMAN_DIR"; exit 1; }
set +u
# shellcheck disable=SC1091
source "$SDKMAN_DIR/bin/sdkman-init.sh"
set -u
command -v sdk >/dev/null 2>&1 || { err "la fonction 'sdk' n'est pas disponible"; exit 1; }
[[ -z "$JDK_DIR" ]] && JDK_DIR="$SDKMAN_DIR/candidates/java"

sdk_safe() {   # cf. piege 1 : jamais d'appel 'sdk' direct sous 'set -u'
    local rc
    set +u
    sdk "$@"; rc=$?
    set -u
    return $rc
}

# --- Dernieres versions Temurin dispo, une par majeure ---
AVAIL=$(curl -fsS --max-time 20 "$API_URL" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ |]*-tem' | sort -u)
[[ -n "$AVAIL" ]] || { err "liste des versions indisponible (reseau ? API SDKMAN ?)"; exit 1; }

latest_for_major() {   # $1 = majeure -> identifiant le plus recent, ou vide
    grep -E "^$1\." <<<"$AVAIL" | sed 's/-tem$//' | sort -V | tail -1 \
        | sed 's/$/-tem/' | grep . || true
}
target_for_major() {   # $1 = majeure -> version qu'on veut au final pour cette majeure
    local m=$1 mine newest
    mine=$(printf '%s\n' "${INSTALLED[@]}" | grep -E "^$m\." | sed 's/-tem$//' | sort -V | tail -1)
    [[ -z "$mine" ]] && return
    mine="${mine}-tem"
    newest=$(latest_for_major "$m")
    if [[ -n "$newest" && "$mine" != "$newest" \
       && "$(printf '%s\n%s\n' "${mine%-tem}" "${newest%-tem}" | sort -V | tail -1)" == "${newest%-tem}" ]]; then
        printf '%s\n' "$newest"
    else
        printf '%s\n' "$mine"
    fi
}

sync_alias() {   # $1 = majeure, $2 = version cible (ex. 25.0.4-tem)
    local major=$1 target=$2 link="$ALIAS_DIR/$1" want="$JDK_DIR/$2" cur=""
    [[ -L "$link" ]] && cur=$(readlink "$link")
    [[ "$cur" == "$want" ]] && return 0
    changed=1
    act "alias  $link  ->  $target"
    if (( APPLY )); then
        mkdir -p "$ALIAS_DIR" && ln -sfn "$want" "$link" || warn "echec creation alias $link"
    fi
}

# --- Etat installe. Filtre '^<chiffres>.' : ecarte les repertoires sans point
#     (ex. '21-tem' pose a la main) qui feraient planter l'extraction de majeure,
#     et tous les non-Temurin (graal, zulu...) qui n'ont pas le suffixe -tem.
mapfile -t INSTALLED < <(find "$JDK_DIR" -maxdepth 1 -mindepth 1 -type d -name '*-tem' -printf '%f\n' 2>/dev/null \
                         | grep -E '^[0-9]+\.' | sort -V)
mapfile -t SKIPPED   < <(find "$JDK_DIR" -maxdepth 1 -mindepth 1 -type d -name '*-tem' -printf '%f\n' 2>/dev/null \
                         | grep -vE '^[0-9]+\.' || true)
# basename obligatoire : selon les versions, "sdk default" ecrit un lien
# RELATIF (25.0.4-tem) ou ABSOLU (/home/.../java/25.0.4-tem). Sans basename,
# l'extraction de majeure renvoie du chemin et le garde-fou du defaut saute.
ORIG_DEFAULT=$(readlink "$JDK_DIR/current" 2>/dev/null || true)
[[ -n "$ORIG_DEFAULT" ]] && ORIG_DEFAULT=$(basename "$ORIG_DEFAULT")

(( ${#SKIPPED[@]} )) && warn "Repertoires au format inattendu, ignores : ${SKIPPED[*]}"

# --- Cas 1 : aucun JDK Temurin -> derniere LTS ---
if (( ${#INSTALLED[@]} == 0 )); then
    warn "Aucun JDK Temurin installe."
    best=""
    for m in $(printf '%s\n' "${LTS_MAJORS[@]}" | sort -rn); do
        best=$(latest_for_major "$m"); [[ -n "$best" ]] && break
    done
    [[ -n "$best" ]] || { err "aucune LTS trouvee dans la liste amont"; exit 1; }
    info "Derniere LTS disponible : $best"
    act "sdk install java $best  +  sdk default java $best"
    if (( APPLY )); then
        sdk_safe install java "$best" && sdk_safe default java "$best" \
            && ok "$best installe et defini par defaut" || err "echec de l'installation"
    fi
    sync_alias "$(cut -d. -f1 <<<"$best")" "$best"
    exit 0
fi

# --- Cas 2 : mise a jour majeure par majeure ---
info "JDK Temurin installes : ${INSTALLED[*]}"
info "Defaut actuel         : ${ORIG_DEFAULT:-<aucun>}"
info ""

ORIG_MAJOR=""
[[ -n "$ORIG_DEFAULT" ]] && ORIG_MAJOR=$(cut -d. -f1 <<<"$ORIG_DEFAULT")

mapfile -t MAJORS < <(printf '%s\n' "${INSTALLED[@]}" | cut -d. -f1 | sort -un)
declare -A TARGETS=()   # majeure -> version retenue, sert a poser les alias

for major in "${MAJORS[@]}"; do
    mapfile -t mine_all < <(printf '%s\n' "${INSTALLED[@]}" | grep -E "^$major\." | sed 's/-tem$//' | sort -V)
    (( ${#mine_all[@]} )) || continue          # garde : jamais d'indexation sur tableau vide
    mine="${mine_all[-1]}-tem"
    newest=$(latest_for_major "$major")
    target="$mine"

    if [[ -z "$newest" ]]; then
        warn "Java $major : plus propose en amont, on garde $mine"
    elif [[ "$mine" == "$newest" ]]; then
        ok "Java $major : deja a jour ($mine)"
    elif [[ "$(printf '%s\n%s\n' "${mine%-tem}" "${newest%-tem}" | sort -V | tail -1)" != "${newest%-tem}" ]]; then
        warn "Java $major : l'installe ($mine) est plus recent que l'amont ($newest), ignore"
    else
        target="$newest"
        changed=1
        info "Java $major : $mine  ->  $newest"
        act "sdk install java $newest"
        if (( APPLY )); then
            if ! sdk_safe install java "$newest"; then
                err "echec install $newest -> on conserve $mine"; target="$mine"
            fi
        fi
    fi

    TARGETS[$major]="$target"

    # Purge des autres versions de cette majeure (residus d'installs passees).
    # Toujours APRES l'install du remplacant, jamais avant.
    for v in "${mine_all[@]}"; do
        [[ "${v}-tem" == "$target" ]] && continue
        changed=1
        act "sdk uninstall java ${v}-tem  (obsolete)"
        (( APPLY )) && { sdk_safe uninstall java "${v}-tem" || warn "echec desinstallation de ${v}-tem"; }
    done
done

# --- Alias stables : ~/.local/share/jdks/<majeure> -> version retenue.
#     Poses APRES la boucle, donc apres installs et purges.
for major in "${!TARGETS[@]}"; do
    sync_alias "$major" "${TARGETS[$major]}"
done
# Nettoyage des alias dont la majeure n'est plus installee
if [[ -d "$ALIAS_DIR" ]]; then
    while IFS= read -r link; do
        m=$(basename "$link")
        [[ -v "TARGETS[$m]" ]] && continue
        act "alias obsolete supprime : $link"
        (( APPLY )) && rm -f "$link"
    done < <(find "$ALIAS_DIR" -maxdepth 1 -type l -printf '%p\n' 2>/dev/null | sort)
fi

# --- Defaut : repositionne explicitement sur la majeure d'origine (piege 2).
#     'sdk install' a pu detourner 'current' en silence pendant la boucle.
if [[ -n "$ORIG_MAJOR" ]]; then
    want=$(target_for_major "$ORIG_MAJOR")
    now=$(readlink "$JDK_DIR/current" 2>/dev/null || true)
    [[ -n "$now" ]] && now=$(basename "$now")
    if [[ -n "$want" && "$now" != "$want" ]]; then
        info ""
        act "sdk default java $want  (defaut d'origine : majeure $ORIG_MAJOR)"
        (( APPLY )) && { sdk_safe default java "$want" && ok "defaut -> $want" \
                         || warn "echec 'sdk default' vers $want"; }
    fi
fi

info ""
if (( changed == 0 )); then
    ok "Rien a faire, tout est a jour."
elif (( APPLY == 0 )); then
    warn "DRY-RUN : rien n'a ete modifie. Relance avec --apply pour appliquer."
else
    ok "Termine. Verifie : java -version"
    info ""
    info "Alias stables (a declarer dans IntelliJ / LibreOffice, une fois pour toutes) :"
    for major in $(printf '%s\n' "${!TARGETS[@]}" | sort -n); do
        info "  $ALIAS_DIR/$major  ->  ${TARGETS[$major]}"
    done
fi

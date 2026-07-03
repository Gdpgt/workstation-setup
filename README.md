# workstation-setup

Scripts et notes pour provisionner mes postes de travail après un changement de PC.
Idempotents, rien codé en dur : côté Linux, le hardware (GPU/CPU) est détecté au runtime.

## Deux cibles

| OS | Dossier | Doc d'entrée |
|---|---|---|
| Fedora Workstation 44 | [`Notes_changement_pc_LINUX/`](Notes_changement_pc_LINUX/) | [Note_Provisionnement_Fedora.md](Notes_changement_pc_LINUX/Note_Provisionnement_Fedora.md) |
| Windows 11 | [`Notes_changement_pc_WINDOWS_perso/`](Notes_changement_pc_WINDOWS_perso/) | [Note_Provisionnement_nouveau_PC_Window.md](Notes_changement_pc_WINDOWS_perso/Note_Provisionnement_nouveau_PC_Window.md) |

## Comment ça marche

Sur un PC vierge : le `bootstrap` installe git, clone le repo dans `~/code` et pose Claude
Code en natif ; le `setup` (`setup.sh` / `setup.ps1`, idempotent) provisionne tout le reste ;
Claude Code lit le log de run et corrige les erreurs. **Les commandes exactes d'amorçage sont
dans l'étape bootstrap de chaque Note** (liens ci-dessus).

## Où lire quoi

- **Procédure Linux** → [Note_Provisionnement_Fedora.md](Notes_changement_pc_LINUX/Note_Provisionnement_Fedora.md)
- **Procédure Windows** → [Note_Provisionnement_nouveau_PC_Window.md](Notes_changement_pc_WINDOWS_perso/Note_Provisionnement_nouveau_PC_Window.md)
- **Dépannage matériel Linux** (gel de veille, WiFi, OLED…) → sections « ⚠️ Cas particulier »
  de la Note Fedora.

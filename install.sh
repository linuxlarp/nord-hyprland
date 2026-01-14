#!/bin/sh

set -eu

###############################################################################
# DISCLAIMER
###############################################################################
cat <<'EOF'
============================================================
WARNING / DISCLAIMER
============================================================
This script installs packages and overwrites configuration
files in your home directory.

Use this script at your own risk.
The author is not liable for data loss,
system breakage, or any other damages.

Read and review this script before running it.
If you do not agree, type N to exit.
============================================================
EOF

printf '%s' "Do you understand and accept these terms? [y/N]: "
IFS= read -r AGREE || AGREE=""
[ -z "${AGREE}" ] && AGREE="N"

case "$AGREE" in
    y|Y) ;;
    *)
        echo "Aborting. No changes were made."
        exit 1
        ;;
esac

###############################################################################
# ARCH-BASED CHECK (os-release)
###############################################################################
OS_RELEASE=""

if [ -r /etc/os-release ]; then
    OS_RELEASE=/etc/os-release
elif [ -r /usr/lib/os-release ]; then
    OS_RELEASE=/usr/lib/os-release
fi

if [ -z "$OS_RELEASE" ]; then
    echo "Cannot find os-release file; this script only supports Arch-based systems."
    exit 1
fi

# shellcheck disable=SC1090
. "$OS_RELEASE"

ARCH_OK=0
case "${ID-}" in
    arch|endeavouros|manjaro|garuda|cachy|omarchy|artix|blackarch|archcraft|reborn)
        ARCH_OK=1
        ;;
esac

# Some derivatives only set ID_LIKE
if [ "$ARCH_OK" -eq 0 ] && [ "${ID_LIKE-}" != "${ID_LIKE#*arch*}" ]; then
    ARCH_OK=1
fi

if [ "$ARCH_OK" -ne 1 ]; then
    echo "This script only supports Arch-based systems. Detected: ${PRETTY_NAME-${ID-unknown}}"
    exit 1
fi

echo "Arch-based system detected: ${PRETTY_NAME-${ID-Arch Linux}}"

###############################################################################
# PATHS AND CONFIG
###############################################################################
REPO_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
SRC_CONFIG_DIR="$REPO_DIR"
DEST_CONFIG_DIR="$HOME/.config"


CONFIG_FOLDERS='
hypr
waybar
rofi
swaync
cava
fastfetch
ghostty
'

PACMAN_LIST="$REPO_DIR/needed_packages/pacman.txt"
AUR_LIST="$REPO_DIR/needed_packages/aur.txt"

###############################################################################
# INSTALL REPO PACKAGES (pacman.txt)
###############################################################################
if [ -f "$PACMAN_LIST" ]; then
    echo
    echo "Repo packages in pacman.txt:"
    grep -Ev '^[[:space:]]*(#|$)' "$PACMAN_LIST" || true

    printf '%s' "Install these packages with pacman? [y/N]: "
    IFS= read -r INSTALL_PACMAN || INSTALL_PACMAN=""
    [ -z "$INSTALL_PACMAN" ] && INSTALL_PACMAN="N"

    case "$INSTALL_PACMAN" in
        y|Y)
            # Build list safely
            PKGS=""
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in
                    ''|\#*) continue ;;
                    *)
                        if [ -z "$PKGS" ]; then
                            PKGS=$line
                        else
                            PKGS="$PKGS $line"
                        fi
                        ;;
                esac
            done <"$PACMAN_LIST"

            if [ -n "$PKGS" ]; then
                echo "Running pacman -S --needed $PKGS"
                # --noconfirm is intentionally omitted for safety; user will see pacman prompts
                sudo pacman -S --needed $PKGS
            else
                echo "No valid pacman packages found in pacman.txt."
            fi
            ;;
        *)
            echo "Skipping pacman package installation."
            ;;
    esac
else
    echo "pacman.txt not found at $PACMAN_LIST; skipping repo package installation."
fi

###############################################################################
# INSTALL AUR PACKAGES (aur.txt via paru/yay)
###############################################################################
if [ -f "$AUR_LIST" ]; then
    AUR_HELPER=""

    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    fi

    if [ -z "$AUR_HELPER" ]; then
        echo
        echo "No AUR helper (paru or yay) found in PATH."
        echo "Install one if AUR packages are needed, then re-run this script."
    else
        echo
        echo "Using AUR helper: $AUR_HELPER"
        echo "AUR packages in aur.txt:"
        grep -Ev '^[[:space:]]*(#|$)' "$AUR_LIST" || true

        printf '%s' "Install these AUR packages with $AUR_HELPER? [y/N]: "
        IFS= read -r INSTALL_AUR || INSTALL_AUR=""
        [ -z "$INSTALL_AUR" ] && INSTALL_AUR="N"

        case "$INSTALL_AUR" in
            y|Y)
                PKGS=""
                while IFS= read -r line || [ -n "$line" ]; do
                    case "$line" in
                        ''|\#*) continue ;;
                        *)
                            if [ -z "$PKGS" ]; then
                                PKGS=$line
                            else
                                PKGS="$PKGS $line"
                            fi
                            ;;
                    esac
                done <"$AUR_LIST"

                if [ -n "$PKGS" ]; then
                    echo "Running $AUR_HELPER -S --needed $PKGS"
                    "$AUR_HELPER" -S --needed $PKGS
                else
                    echo "No valid AUR packages found in aur.txt."
                fi
                ;;
            *)
                echo "Skipping AUR package installation."
                ;;
        esac
    fi
else
    echo "aur.txt not found at $AUR_LIST; skipping AUR package installation."
fi

###############################################################################
# WARN ABOUT CONFIG OVERWRITE
###############################################################################
echo
echo "The following directories will be copied into:"
echo "  $DEST_CONFIG_DIR"
echo "Existing directories with the same name will be backed up, then replaced."

for folder in $CONFIG_FOLDERS; do
    echo " - $folder -> $DEST_CONFIG_DIR/$folder"
done

printf '%s' "Proceed with config backup and overwrite? [y/N]: "
IFS= read -r CONFIRM || CONFIRM=""
[ -z "$CONFIRM" ] && CONFIRM="N"

case "$CONFIRM" in
    y|Y) ;;
    *)
        echo "Aborting before touching configuration files."
        exit 0
        ;;
esac

###############################################################################
# BACKUP AND COPY CONFIG
###############################################################################
timestamp=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="$HOME/.config-backup-$timestamp"

mkdir -p "$BACKUP_DIR"
mkdir -p "$DEST_CONFIG_DIR"

echo
echo "Backing up existing configs to: $BACKUP_DIR"
echo "Copying new configs from: $SRC_CONFIG_DIR"

for folder in $CONFIG_FOLDERS; do
    src="$SRC_CONFIG_DIR/$folder"
    dest="$DEST_CONFIG_DIR/$folder"

    if [ ! -d "$src" ]; then
        echo " [SKIP] $folder (not found in repo)"
        continue
    fi

    if [ -e "$dest" ]; then
        echo " [BACKUP] $dest -> $BACKUP_DIR/$folder"
        # If backup target exists, remove it to avoid mv failure
        if [ -e "$BACKUP_DIR/$folder" ]; then
            rm -rf "$BACKUP_DIR/$folder"
        fi
        mv "$dest" "$BACKUP_DIR/$folder"
    fi

    echo " [COPY]   $src -> $dest"
    cp -R "$src" "$dest"
done

###############################################################################
# MAKE SCRIPTS EXECUTABLE
###############################################################################
if [ -d "$DEST_CONFIG_DIR/hypr/scripts" ]; then
    # Ignore errors if no regular files
    for f in "$DEST_CONFIG_DIR"/hypr/scripts/*; do
        if [ -f "$f" ]; then
            chmod +x "$f" || true
        fi
    done
fi

echo
echo "Done."
echo "Previous configs (if any) are stored in: $BACKUP_DIR"
echo "Log out and back in, or restart Hyprland, to apply changes."

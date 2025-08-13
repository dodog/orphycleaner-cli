#!/bin/bash
##
#     Project: OrphyCleaner - Orphaned Config Folder Cleaner
# Description: Scans your home directory for orphaned config folders
#      Author: Jozef Gaal (dodog) <preklady@mayday.sk>
#   Copyright: 2025 Jozef Gaal
#     License: GPL-3+
#         Web: https://github.com/dodog/orphycleaner
#
# Scans your home directory for config folders that may belong to uninstalled or unused applications.
# Matches against installed packages (pacman), Flatpak apps, desktop files, AppImages, and executables.
# Categorizes folders as Installed, Maybe Installed, or Orphaned.
#
# WARNING: Not 100% guaranteed — backup and verify before deleting folders.
#
# Usage:
#   chmod +x check_config_orphans.sh
#   ./check_config_orphans.sh
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
##

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

declare -A results

normalize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' _.-' '-'
}

# Alias map: folder basename → known app name (normalized)
declare -A alias_map=(
  [".audacity-data"]="audacity"
  [".SynologyDrive"]="synology-drive"
  ["Code - OSS"]="code-oss"
  [".eID_klient"]="eidklient"
  [".mozilla"]="mozilla"
)

ignored_folders=(
  "$HOME/.local/share/applications"
  "$HOME/.local/share/backgrounds"
  "$HOME/.local/share/keyrings"
  "$HOME/.local/share/sounds"
  "$HOME/.local/share/Trash"
  "$HOME/.cache"
  "$HOME/.mozilla/cache"
  "$HOME/.thumbnails"
  "$HOME/.npm"
  "$HOME/.config/pulse"
  "$HOME/.local/share/flatpak/runtime"
)

is_ignored_folder() {
  local folder="$1"
  for ignored in "${ignored_folders[@]}"; do
    if [[ "$folder" == "$ignored" || "$folder" == "$ignored/"* ]]; then
      return 0
    fi
  done
  return 1
}

# Installed pacman packages
mapfile -t installed_pkgs < <(pacman -Qq)
installed_pkgs_normalized=()
for pkg in "${installed_pkgs[@]}"; do
  installed_pkgs_normalized+=( "$(normalize "$pkg")" )
done

# Flatpak
if command -v flatpak >/dev/null 2>&1; then
  mapfile -t installed_flatpaks < <(flatpak list --app --columns=application)
  installed_flatpaks_normalized=()
  for app in "${installed_flatpaks[@]}"; do
    installed_flatpaks_normalized+=( "$(normalize "$app")" )
  done
else
  installed_flatpaks_normalized=()
fi

# Desktop files
desktop_dir="/usr/share/applications"
desktop_apps_normalized=()
if [ -d "$desktop_dir" ]; then
  while IFS= read -r -d '' desktop_file; do
    base=$(basename "$desktop_file" .desktop)
    desktop_apps_normalized+=( "$(normalize "$base")" )
  done < <(find "$desktop_dir" -maxdepth 1 -type f -name "*.desktop" -print0)
fi

# AppImages
appimage_dir="$HOME/Applications"
appimages_normalized=()
if [ -d "$appimage_dir" ]; then
  while IFS= read -r -d '' appimage_file; do
    base=$(basename "$appimage_file")
    base="${base%.*}"
    appimages_normalized+=( "$(normalize "$base")" )
  done < <(find "$appimage_dir" -maxdepth 1 -type f \( -iname '*.AppImage' -o -iname '*.appimage' \) -print0)
fi

check_folder() {
  folder=$1
  base=$(basename "$folder")

  if [[ -n "${alias_map[$base]}" ]]; then
    name="${alias_map[$base]}"
  else
    raw_name=$(echo "$base" | sed 's/^\.//')
    name=$(normalize "$raw_name")
  fi

  for pkg in "${installed_pkgs_normalized[@]}"; do
    [[ "$pkg" == "$name" ]] && { results["Installed (package match)"]+="$folder\n"; return; }
  done

  if command -v "$name" >/dev/null 2>&1; then
    results["Installed (executable found)"]+="$folder\n"
    return
  fi

  for pkg in "${installed_pkgs_normalized[@]}"; do
    if [[ "$pkg" == *"$name"* ]]; then
      results["Maybe Installed (partial package name match)"]+="$folder\n"
      return
    fi
  done

  for app in "${installed_flatpaks_normalized[@]}"; do
    if [[ "$app" == *"$name"* ]]; then
      results["Installed (Flatpak)"]+="$folder\n"
      return
    fi
  done

  for desktop_app in "${desktop_apps_normalized[@]}"; do
    if [[ "$desktop_app" == *"$name"* ]]; then
      results["Installed (desktop file match)"]+="$folder\n"
      return
    fi
  done

  for appimage in "${appimages_normalized[@]}"; do
    if [[ "$appimage" == *"$name"* ]]; then
      results["Installed (AppImage)"]+="$folder\n"
      return
    fi
  done

  results["Orphaned"]+="$folder\n"
}

echo -e "${CYAN}Scanning folders, please wait...${NC}"
counter=0

scan_folders() {
  for folder in "$@"; do
    [ -d "$folder" ] || continue
    if is_ignored_folder "$folder"; then
      continue
    fi
    ((counter++))
    echo -ne "${YELLOW}Processing folder #$counter:${NC} $folder\r"
    check_folder "$folder"
  done
}

scan_folders ~/.config/* ~/.local/share/*

hidden_folders=()
for folder in ~/.*; do
  base=$(basename "$folder")
  [[ "$base" == "." || "$base" == ".." ]] && continue
  [ -d "$folder" ] || continue
  if [[ "$base" == ".config" || "$base" == ".local" ]]; then
    continue
  fi
  hidden_folders+=("$folder")
done
scan_folders "${hidden_folders[@]}"

echo -e "\n${BOLD}===== RESULTS =====${NC}"
for label in "Installed (package match)" "Installed (executable found)" "Installed (Flatpak)" "Installed (desktop file match)" "Installed (AppImage)" "Maybe Installed (partial package name match)" "Orphaned"; do
  echo
  echo -e "${BOLD}== $label ==${NC}"
  if [[ -n "${results[$label]}" ]]; then
    echo -e "${results[$label]}" | sort
  else
    echo -e "${GREEN}None found.${NC}"
  fi
done

# Interactive cleanup
if [[ -n "${results["Orphaned"]}" ]]; then
  echo -e "\n${CYAN}Interactive cleanup of orphaned folders.${NC}"
  echo -e "You can choose to ${GREEN}[K]eep${NC}, ${RED}[D]elete${NC}, ${YELLOW}[S]kip${NC}, or ${BOLD}[Q]uit${NC}."

  mapfile -t orphaned_folders <<< "$(printf '%b' "${results["Orphaned"]}")"

  for folder in "${orphaned_folders[@]}"; do
    [[ -z "$folder" ]] && continue
    while true; do
      read -rp "$(echo -e "${BOLD}Action for:${NC} $folder [${GREEN}K${NC}/${RED}D${NC}/${YELLOW}S${NC}/${CYAN}Q${NC}]: ")" action
      case "$action" in
        [Kk])
          echo -e "${GREEN}Keeping${NC} $folder."
          break
          ;;
        [Dd])
          rm -rf -- "$folder"
          echo -e "${RED}Deleted${NC} $folder."
          break
          ;;
        [Ss])
          echo -e "${YELLOW}Skipped${NC} $folder."
          break
          ;;
        [Qq])
          echo -e "${CYAN}Quitting.${NC}"
          exit 0
          ;;
        *)
          echo -e "${RED}Invalid option.${NC} Please choose K, D, S, or Q."
          ;;
      esac
    done
  done
fi

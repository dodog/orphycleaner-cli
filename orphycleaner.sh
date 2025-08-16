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
#   chmod +x orphycleaner.sh
#   ./orphycleaner.sh
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

# =========================
# COLORS
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Expanded ignored folders
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
  "$HOME/.config/autostart"   # added
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

# =========================
# START MESSAGE + DATA GATHERING
# =========================
echo -e "${BOLD}Script started.${NC} Gathering package and application information..."

# Get all installed pacman packages (official + AUR)
mapfile -t installed_pkgs < <(pacman -Qq)
installed_pkgs_normalized=()
for pkg in "${installed_pkgs[@]}"; do
  installed_pkgs_normalized+=( "$(normalize "$pkg")" )
done

# Get installed Flatpak apps
if command -v flatpak >/dev/null 2>&1; then
  mapfile -t installed_flatpaks < <(flatpak list --app --columns=application)
  installed_flatpaks_normalized=()
  for app in "${installed_flatpaks[@]}"; do
    installed_flatpaks_normalized+=( "$(normalize "$app")" )
  done
else
  installed_flatpaks_normalized=()
fi

# Get installed .desktop apps (system-wide only)
desktop_dir="/usr/share/applications"
desktop_apps_normalized=()
if [ -d "$desktop_dir" ]; then
  while IFS= read -r -d '' desktop_file; do
    base=$(basename "$desktop_file" .desktop)
    desktop_apps_normalized+=( "$(normalize "$base")" )
  done < <(find "$desktop_dir" -maxdepth 1 -type f -name "*.desktop" -print0)
fi

# Get installed AppImages in ~/Applications/
appimage_dir="$HOME/Applications"
appimages_normalized=()
if [ -d "$appimage_dir" ]; then
  while IFS= read -r -d '' appimage_file; do
    base=$(basename "$appimage_file")
    base="${base%.*}"  # strip extension
    appimages_normalized+=( "$(normalize "$base")" )
  done < <(find "$appimage_dir" -maxdepth 1 -type f \( -iname '*.AppImage' -o -iname '*.appimage' \) -print0)
fi

check_folder() {
  folder=$1
  base=$(basename "$folder")

  # Use alias if exists
  if [[ -n "${alias_map[$base]}" ]]; then
    name="${alias_map[$base]}"
  else
    raw_name=$(echo "$base" | sed 's/^\.//')
    name=$(normalize "$raw_name")
  fi

  # Package exact match
  for pkg in "${installed_pkgs_normalized[@]}"; do
    [[ "$pkg" == "$name" ]] && { results["Installed (package match)"]+="$folder\n"; return; }
  done

  # Executable in PATH (by normalized config folder name or alias)
  if command -v "$name" >/dev/null 2>&1; then
    results["Installed (executable found)"]+="$folder\n"
    return
  fi

  # Partial package name match
  for pkg in "${installed_pkgs_normalized[@]}"; do
    if [[ "$pkg" == *"$name"* ]]; then
      results["Maybe Installed (partial package name match)"]+="$folder\n"
      return
    fi
  done

  # Flatpak app match
  for app in "${installed_flatpaks_normalized[@]}"; do
    if [[ "$app" == *"$name"* ]]; then
      results["Installed (Flatpak)"]+="$folder\n"
      return
    fi
  done

  # Desktop file match
  for desktop_app in "${desktop_apps_normalized[@]}"; do
    if [[ "$desktop_app" == *"$name"* ]]; then
      results["Installed (desktop file match)"]+="$folder\n"
      return
    fi
  done

  # AppImage match
  for appimage in "${appimages_normalized[@]}"; do
    if [[ "$appimage" == *"$name"* ]]; then
      results["Installed (AppImage)"]+="$folder\n"
      return
    fi
  done

  # Otherwise orphaned
  results["Orphaned"]+="$folder\n"
}

echo -e "${BLUE}Scanning folders, please wait...${NC}"
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

# Scan ~/.config and ~/.local/share
scan_folders ~/.config/* ~/.local/share/*

# Scan hidden folders directly under home (~), except .config and .local
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

# Summary counts BEFORE interactive
echo -e "\n${BOLD}===== SUMMARY COUNTS =====${NC}"
for label in "Installed (package match)" "Installed (executable found)" "Installed (Flatpak)" "Installed (desktop file match)" "Installed (AppImage)" "Maybe Installed (partial package name match)" "Orphaned"; do
  count=$(echo -e "${results[$label]}" | grep -v '^\s*$' | wc -l)
  echo -e "${BOLD}$label:${NC} $count"
done

# Safety warning
echo -e "\n${RED}${BOLD}WARNING:${NC} This script cannot be 100% certain that 'Orphaned' folders are truly unused."
echo -e "Before deleting anything, double-check to make sure you are not removing something important."

# Interactive cleanup (WORKING version: uses an array; stdin is not consumed)
if [[ -n "${results["Orphaned"]}" ]]; then
  echo -e "\n${BLUE}Interactive cleanup of orphaned folders.${NC}"
  echo -e "You can choose to ${GREEN}[K]eep${NC}, ${RED}[D]elete${NC}, ${YELLOW}[S]kip${NC}, or ${BLUE}[Q]uit${NC}."

  mapfile -t orphaned_folders <<< "$(printf '%b' "${results["Orphaned"]}")"

  kept_count=0
  deleted_count=0
  skipped_count=0

  for folder in "${orphaned_folders[@]}"; do
    [[ -z "$folder" ]] && continue
    while true; do
      read -rp "$(echo -e "${BOLD}Action for:${NC} $folder [${GREEN}K${NC}/${RED}D${NC}/${YELLOW}S${NC}/${BLUE}Q${NC}]: ")" action
      case "$action" in
        [Kk])
          echo -e "${GREEN}Keeping${NC} $folder."
          ((kept_count++))
          break
          ;;
        [Dd])
          rm -rf -- "$folder"
          echo -e "${RED}Deleted${NC} $folder."
          ((deleted_count++))
          break
          ;;
        [Ss])
          echo -e "${YELLOW}Skipped${NC} $folder."
          ((skipped_count++))
          break
          ;;
        [Qq])
          echo -e "${BLUE}Quitting.${NC}"
          echo -e "\n${BOLD}Summary:${NC} ${GREEN}$kept_count kept${NC}, ${RED}$deleted_count deleted${NC}, ${YELLOW}$skipped_count skipped${NC}."
          exit 0
          ;;
        *)
          echo -e "${RED}Invalid option.${NC} Please choose K, D, S, or Q."
          ;;
      esac
    done
  done

  echo -e "\n${BOLD}Summary:${NC} ${GREEN}$kept_count kept${NC}, ${RED}$deleted_count deleted${NC}, ${YELLOW}$skipped_count skipped${NC}."
else
  echo -e "\n${GREEN}No orphaned folders found for cleanup.${NC}"
fi

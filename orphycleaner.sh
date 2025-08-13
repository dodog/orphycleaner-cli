#!/bin/bash
##
#     Project: OrphyCleaner - Orphaned Config Folder Cleaner
# Description: MScans your home directory for orphaned config folders
#      Author: Jozef Gaal (dodog) <preklady@mayday.sk>
#   Copyright: 2025 Jozef Gaal
#     License: GPL-3+
#         Web: https://github.com/dodog/orphycleaner

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
  # Add more aliases here as needed
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
    # else normalize folder name after removing leading dot if any
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

echo "Scanning folders, please wait..."

counter=0

scan_folders() {
  for folder in "$@"; do
    [ -d "$folder" ] || continue
    if is_ignored_folder "$folder"; then
      continue
    fi
    ((counter++))
    echo -ne "Processing folder #$counter: $folder\r"
    check_folder "$folder"
  done
}

# Scan ~/.config
scan_folders ~/.config/*

# Scan ~/.local/share
scan_folders ~/.local/share/*

# Scan hidden folders directly under home (~), except .config and .local which are scanned already
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

echo -e "\n"
echo "===== RESULTS ====="
for label in "Installed (package match)" "Installed (executable found)" "Installed (Flatpak)" "Installed (desktop file match)" "Installed (AppImage)" "Maybe Installed (partial package name match)" "Orphaned"; do
  echo
  echo "== $label =="
  if [[ -n "${results[$label]}" ]]; then
    echo -e "${results[$label]}" | sort
  else
    echo "None found."
  fi
done

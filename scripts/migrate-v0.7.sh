#!/usr/bin/env bash
set -euo pipefail

OLD_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/engineeringos"
NEW_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/nexora"
OLD_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/engineeringos"
NEW_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nexora"
OLD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/engineeringos"
NEW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nexora"
OLD_PROJECTS="$HOME/EngineeringOSProjects"
NEW_PROJECTS="$HOME/NexoraProjects"
OLD_NOTES="$HOME/EngineeringOSNotes"
NEW_NOTES="$HOME/NexoraNotes"

printf '\nMigrating EngineeringOS data -> Nexora OS 0.8\n'

# Freeze old writers before moving state/memory/model data.
for svc in engineeringos-tony.service engineeringos-context.service engineeringos-llm.service; do
  systemctl --user stop "$svc" >/dev/null 2>&1 || true
  systemctl --user disable "$svc" >/dev/null 2>&1 || true
done

migrate_dir() {
  local old="$1" new="$2"
  if [[ -L "$old" ]]; then return 0; fi
  if [[ -d "$old" && ! -e "$new" ]]; then
    mkdir -p "$(dirname "$new")"
    mv "$old" "$new"
    echo "  moved: $old -> $new"
  elif [[ -d "$old" && -d "$new" ]]; then
    # Merge without overwriting newer Nexora files. This is only a recovery path
    # for users who attempted an earlier V0.8 build.
    cp -a -n "$old"/. "$new"/ 2>/dev/null || true
    echo "  merged: $old -> $new"
  else
    mkdir -p "$new"
  fi
  if [[ ! -e "$old" ]]; then ln -s "$new" "$old" 2>/dev/null || true; fi
}

migrate_dir "$OLD_SHARE" "$NEW_SHARE"
migrate_dir "$OLD_STATE" "$NEW_STATE"
migrate_dir "$OLD_CONFIG" "$NEW_CONFIG"
migrate_dir "$OLD_PROJECTS" "$NEW_PROJECTS"
migrate_dir "$OLD_NOTES" "$NEW_NOTES"

# Project metadata changed from .engos to .nexora. Preserve metadata contents.
if [[ -d "$NEW_PROJECTS" ]]; then
  while IFS= read -r -d '' oldmeta; do
    parent="$(dirname "$oldmeta")"
    if [[ ! -e "$parent/.nexora" ]]; then mv "$oldmeta" "$parent/.nexora"; fi
  done < <(find "$NEW_PROJECTS" -mindepth 2 -maxdepth 2 -type d -name .engos -print0 2>/dev/null)
fi

# Remove old user service unit copies after data has moved. New units are
# installed later by install-user-service.sh.
rm -f "$HOME/.config/systemd/user/engineeringos-context.service" \
      "$HOME/.config/systemd/user/engineeringos-tony.service" \
      "$HOME/.config/systemd/user/engineeringos-llm.service"
systemctl --user daemon-reload

echo "Migration complete. Tony memory/model cache and project files are preserved."

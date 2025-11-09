#!/usr/bin/env bash

PACMAN_LOG="/var/log/pacman.log"

# Get list of explicitly installed packages
mapfile -t explicit_installed < <(pacman -Qe --quiet)

# Get list of orphaned packages
mapfile -t orphans < <(pacman -Qdtq)

declare -A used_orphans_map
unused_orphans=()

print_logs_for_package() {
  local pkg=$1
  echo "---- Logs for package: $pkg ----"
  grep -E "\[(ALPM|PACMAN)\] (installed|upgraded|removed|downgraded) $pkg" "$PACMAN_LOG" | tail -n 5
  echo
}

for orphan in "${orphans[@]}"; do
  mapfile -t revdeps < <(pactree -r "$orphan" 2>/dev/null || echo "")
  explicitly_using=()
  for dep in "${revdeps[@]}"; do
    if [[ " ${explicit_installed[*]} " == *" $dep "* ]]; then
      explicitly_using+=("$dep")
    fi
  done
  if (( ${#explicitly_using[@]} > 0 )); then
    for user_pkg in "${explicitly_using[@]}"; do
      used_orphans_map["$user_pkg"]+="$orphan "
    done
  else
    unused_orphans+=("$orphan")
  fi
done

echo "Orphaned dependencies grouped by explicitly installed packages using them:"
for pkg in "${explicit_installed[@]}"; do
  if [[ -n "${used_orphans_map[$pkg]}" ]]; then
    echo "$pkg:"
    for orphan_pkg in ${used_orphans_map[$pkg]}; do
      echo "  - $orphan_pkg"
    done
  fi
done

echo
echo "Orphaned dependencies not used by any explicitly installed package:"
for orphan_pkg in "${unused_orphans[@]}"; do
  echo "  - $orphan_pkg"
done

echo
echo "== Pacman logs for orphans still used =="
for pkg in "${explicit_installed[@]}"; do
  if [[ -n "${used_orphans_map[$pkg]}" ]]; then
    for orphan_pkg in ${used_orphans_map[$pkg]}; do
      print_logs_for_package "$orphan_pkg"
    done
  fi
done

echo "== Pacman logs for orphans not used =="
for orphan_pkg in "${unused_orphans[@]}"; do
  print_logs_for_package "$orphan_pkg"
done

echo
if (( ${#unused_orphans[@]} > 0 )); then
  echo "You can remove the ${#unused_orphans[@]} unused orphaned packages listed above."
  echo "Packages: ${unused_orphans[*]}"
  read -r -p "Remove them now with 'pacman -Rns'? (y/N): " remove_choice
  if [[ $remove_choice =~ ^[Yy]$ ]]; then
    echo "Removing unused orphaned packages..."
    if [[ $EUID -eq 0 ]]; then
      pacman -Rns -- "${unused_orphans[@]}"
    else
      sudo pacman -Rns -- "${unused_orphans[@]}"
    fi
  else
    echo "Skipping removal of unused orphaned packages."
  fi
else
  echo "No unused orphaned packages to remove."
fi

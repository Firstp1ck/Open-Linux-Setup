## Walker

Use the helper to refresh your local configuration if anything looks off:

```bash
omarchy-refresh-walker
```

### Fuzzy Field menu (hierarchical, configurable)

- A new script `bin/omarchy-menu-fuzzy` provides a fuzzy “Field” that searches across a hierarchical menu you define.
- It flattens the structure into path-like labels (for example, `Setup/Hyprland`, `System/Restart`) and uses `walker --dmenu` for selection.
- The flattened list and a path→command map are cached in `/tmp` and will be regenerated when the source config changes.

Configuration locations:
- User: `~/.config/walker/menu.jsonc`
- Default (synced via `omarchy-refresh-walker`): `~/.local/share/omarchy/config/walker/menu.jsonc`

Example `menu.jsonc` (JSONC allowed):

```jsonc
{
  "System": {
    "Lock": { "run": "omarchy-lock-screen" },
    "Restart": { "run": "systemctl reboot" }
  },
  "Setup": {
    "Hyprland": { "run": "omarchy-launch-editor ~/.config/hypr/hyprland.conf" }
  }
}
```

Usage:
- Open the main Omarchy menu: `omarchy-menu`
- Choose “Field” to fuzzy search the configured entries

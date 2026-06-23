#!/opt/homebrew/bin/bash
# Otevře nové tmux okno z ticketu: vlevo claude (pojmenovaná session),
# vpravo shell ve složce projektu. Jméno okna i claude session = slug.
# Voláno z `prefix + n` (tmux keybind) nebo shell funkce `tt`.
#
# Argumenty:
#   $1 = syrový vstup z promptu, např. "em3-26 auth"
#   $2 = startovní cesta (složka projektu); fallback na $PWD
#
# Claude session se pojmenuje přes `--name` (display name v pickeru i titulku),
# takže není potřeba dodatečný `/rename` ani čekání na start claude.

set -u

raw="${1:-}"
start_path="${2:-$PWD}"

# Slug: ořež okraje, vnitřní mezery → jedna pomlčka ("em3-26 auth" → "em3-26-auth").
slug="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/-/g')"

# Prázdný vstup → nedělej nic (žádná bezejmenná okna).
[[ -z "$slug" ]] && exit 0

# Nové okno (levý pane = shell), spusť v něm claude, pak odděl pravý pane.
win="$(tmux new-window -P -F '#{window_id}' -c "$start_path" -n "$slug")"
tmux send-keys -t "$win" "claude --name \"$slug\"" Enter
tmux split-window -h -t "$win" -c "$start_path"
tmux select-pane -t "$win" -L

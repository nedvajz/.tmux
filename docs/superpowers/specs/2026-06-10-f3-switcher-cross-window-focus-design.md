# F3 switcher — skok na Claude session zobrazenou v jiném Ghostty okně

## Problém

F3 (`~/.claude/scripts/tmux-claude-switcher.sh`) dnes umí dvě akce:

- `pane` — `switch-client` na cílový pane **v aktuálním klientovi**
- `new` — otevřít nové tmux okno a `claude --resume`

Když je ale cílová session už attachnutá jiným tmux klientem (jiné Ghostty
okno, typicky na jiné macOS Space), `switch-client` ji „přetáhne" do
aktuálního okna místo toho, aby uživatele přenesl tam, kde už session žije.

## Cíl

Při výběru session ve switcheru:

1. Session **není zobrazená nikde** → dnešní chování (`switch-client`
   v aktuálním klientovi).
2. Session **už zobrazuje jiný Ghostty klient** → přepnout window/pane v té
   session a zaostřit jeho Ghostty okno na úrovni macOS (včetně přepnutí
   Space). V aktuálním okně se nic nemění.
3. Session je session **aktuálního klienta** → jen `select-window` +
   `select-pane`.

## Návrh

### tmux.conf

```tmux
set -g set-titles on
set -g set-titles-string '#S — tmux'
```

Každé Ghostty okno dostane do titulku jméno session, kterou jeho klient
zobrazuje — podle toho AppleScript okno najde. Vedlejší efekt: titulky
Ghostty oken řídí tmux.

### Switcher — rozhodovací logika akce `pane`

Zdroj pravdy: `tmux list-clients -F '#{client_session}'` (žádné hádání
z velikosti okna).

| Stav cílové session | Akce |
|---|---|
| = session aktuálního klienta | `select-window` + `select-pane` |
| attachnutá jiným klientem | `select-window` + `select-pane` v cílové session, pak AppleScript focus Ghostty okna s titulkem `<session> — tmux`; aktuální klient beze změny |
| neattachnutá | `switch-client` (dnešní chování) |

Akce `new` beze změny.

### AppleScript focus

```applescript
tell application "System Events" to tell process "Ghostty"
    perform action "AXRaise" of (first window whose title starts with "<session> — tmux")
    set frontmost to true
end tell
```

macOS přepne na Space okna sám (výchozí chování „switch to a Space with
open windows"). Vyžaduje jednorázové povolení Accessibility pro Ghostty.

### Chybové stavy

- Okno s titulkem nenalezeno (titulek ještě nepřekreslen, zavřené okno)
  → `tmux display-message` s hintem, žádný pád.
- Accessibility nepovoleno → osascript selže → stejný fallback na hint.

## Pořadí implementace — de-risk first

1. **Ruční test AXRaise** přes 3 workspaces jedním osascript příkazem,
   ještě před psaním kódu. Pokud nefunguje spolehlivě, focus krok se
   nahradí hintem (`display-message "session běží v okně X"`); zbytek
   logiky zůstává stejný.
2. tmux.conf + reload.
3. Úprava switcheru.
4. Ruční ověření všech tří scénářů.

## Mimo rozsah

- Window managery (Moom, yabai…) — čistý macOS přístup.
- Akce `new` a řazení/ikony ve fzf seznamu.

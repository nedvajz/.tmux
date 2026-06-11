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
zobrazuje — podle toho Ghostty scripting okno najde (`window whose name
is "<session> — tmux"`). Vedlejší efekt: titulky Ghostty oken řídí tmux.

### Switcher — rozhodovací logika akce `pane`

Zdroj pravdy: `tmux list-clients -F '#{client_session}'` (žádné hádání
z velikosti okna).

| Stav cílové session | Akce |
|---|---|
| = session aktuálního klienta | `select-window` + `select-pane` |
| attachnutá jiným klientem | `select-window` + `select-pane` v cílové session, pak Ghostty `activate window` toho okna; aktuální klient beze změny |
| neattachnutá | `switch-client` (dnešní chování) |

Akce `new` beze změny.

### Ghostty focus (ověřeno de-riskem)

```applescript
tell application "Ghostty" to activate window ¬
  (first window whose name is "<session> — tmux")
```

Ghostty zná všechna svá okna napříč Spaces (na rozdíl od System Events /
AX API, které vidí jen okna na aktuální Space) a `activate window` reálně
přepne i na cílovou Space — ověřeno ručním testem na 3 workspaces.

**Žádná Accessibility / Automation permission není potřeba:** switcher
běží uvnitř Ghostty (přes tmux), takže `tell application "Ghostty"` je
self-automation bez systémového dialogu.

### Chybové stavy

- Okno s daným jménem nenalezeno (titulek ještě nepřekreslen, zavřené
  okno) → `tmux display-message` s hintem, žádný pád.
- osascript selže z jiného důvodu → stejný fallback na hint.

## Pořadí implementace

De-risk (klíčový test `activate window` přes 3 workspaces) **hotový a
úspěšný** — focus přes Ghostty scripting funguje včetně přeskoku Space.

1. tmux.conf: `set-titles on` + `set-titles-string` + reload.
2. Úprava switcheru (rozhodovací logika + Ghostty focus helper).
3. Ruční ověření všech tří scénářů.

## Mimo rozsah

- Window managery (Moom, yabai…) — čistý macOS přístup.
- Akce `new` a řazení/ikony ve fzf seznamu.

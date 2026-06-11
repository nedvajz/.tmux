# F3 switcher — cross-window focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Když F3 switcher vybere Claude session, která je už zobrazená v jiném Ghostty okně (jiná macOS Space), zaostřit to okno systémově místo přetažení session do aktuálního klienta.

**Architecture:** tmux.conf zapne `set-titles`, takže každé Ghostty okno nese jméno své session. Switcher porovná cílovou session se seznamem attachnutých klientů a podle toho buď přepne lokálně, zaostří cizí Ghostty okno přes nativní `activate window` (de-riskem ověřeno, že přeskakuje i Spaces a nepotřebuje Accessibility), nebo zachová dnešní `switch-client`. Očekávaný titulek okna se odvozuje z aktuálního `set-titles-string` přes `tmux display-message`, takže switcher zůstává nezávislý na konkrétním formátu (sdílený `~/.claude` mezi dvěma vývojáři s různým `.tmux` conf).

**Tech Stack:** tmux, bash, osascript (Apple Events na Ghostty), fzf.

**Spec:** `docs/superpowers/specs/2026-06-10-f3-switcher-cross-window-focus-design.md`

**Testing note:** Změna řídí GUI okna přes Apple Events napříč macOS Spaces — nelze ji pokrýt automatizovaným testem (vyžaduje živý tmux + Ghostty + víc oken na víc Spaces). Verifikace je manuální, reálné scénáře. Každý úkol má explicitní manuální test s očekávaným výsledkem.

---

## Soubory

- **Modify:** `tmux.conf` — přidat `set-titles on` + `set-titles-string` (po řádku 31, k ostatním globálním `set -g`).
- **Modify:** `~/.claude/scripts/tmux-claude-switcher.sh` — nahradit `pane)` case-blok (řádky 71–74) rozhodovací logikou; přidat helper `focus_ghostty_window()`. **Mimo tento repo, edituje se přímo.**

---

### Task 1: tmux.conf — pojmenovat Ghostty okna podle session

**Files:**
- Modify: `tmux.conf` (po řádku 31)

- [ ] **Step 1: Přidat set-titles volby**

Do `tmux.conf` za řádek 31 (`set -ga terminal-overrides …`) vlož:

```tmux

# Ghostty okno pojmenuj podle tmux session, kterou jeho klient zobrazuje.
# Čte to F3 switcher (~/.claude/scripts/tmux-claude-switcher.sh), aby uměl
# zaostřit Ghostty okno session běžící na jiné macOS Space.
set -g set-titles on
set -g set-titles-string '#S — tmux'
```

- [ ] **Step 2: Reload configu**

Run: `tmux source-file ~/.tmux/tmux.conf`
Expected: bez chyb.

- [ ] **Step 3: Ověřit, že okna nesou jména session**

Run:
```bash
osascript -e 'tell application "Ghostty" to get name of every window'
```
Expected: seznam jako `main — tmux, Porsenna — tmux, GEM — tmux, IFM24 — tmux` (jména tvých session), ne `👻`.

- [ ] **Step 4: Ověřit expanzi titulku z formátu (jádro párování)**

Run:
```bash
fmt="$(tmux show-options -gv set-titles-string)"
tmux display-message -p -t "main:" "$fmt"
```
Expected: `main — tmux` — shoduje se s názvem okna z kroku 3.

- [ ] **Step 5: Commit**

```bash
git add tmux.conf
git commit -m "Name Ghostty windows by tmux session for F3 cross-window focus"
```

---

### Task 2: Switcher — zaostřit cizí Ghostty okno

**Files:**
- Modify: `~/.claude/scripts/tmux-claude-switcher.sh` (helper nad `case`; `pane)` blok na ř. 71–74)

**Kontext — současný `pane)` blok:**
```bash
  pane)
    tmux switch-client -t "$arg" \; select-window -t "$arg" \; select-pane -t "$arg"
    ;;
```

- [ ] **Step 1: Přidat helper `focus_ghostty_window()`**

Vlož nad `case "$action" in` (cca ř. 71) novou funkci. Titulek se cílové session **expanduje z aktuálního `set-titles-string`** (nezávislost na formátu) a předává do osascript přes `argv` (bezpečné vůči `—`, mezerám, uvozovkám):

```bash
# Zaostři Ghostty okno, které zobrazuje danou tmux session.
# Titulek odvodíme z aktuálního set-titles-string, takže to funguje
# pro libovolný formát (sdílený switcher, různé .tmux conf).
# Návratový kód != 0 → okno nenalezeno / Ghostty nedostupná (volající fallbackne).
focus_ghostty_window() {
  local session="$1" fmt title
  fmt="$(tmux show-options -gv set-titles-string 2>/dev/null)"
  [[ -z "$fmt" ]] && return 1
  title="$(tmux display-message -p -t "${session}:" "$fmt" 2>/dev/null)"
  [[ -z "$title" ]] && return 1
  osascript - "$title" <<'OSA' >/dev/null 2>&1
on run argv
  set wantedTitle to item 1 of argv
  tell application "Ghostty"
    activate
    activate window (first window whose name is wantedTitle)
  end tell
end run
OSA
}
```

- [ ] **Step 2: Nahradit `pane)` blok rozhodovací logikou**

Nahraď stávající `pane)` blok (ř. 71–74) tímto:

```bash
  pane)
    target_session="$(tmux display-message -p -t "$arg" '#{session_name}')"
    current_session="$(tmux display-message -p '#{client_session}')"
    if [[ "$target_session" == "$current_session" ]]; then
      # už jsem ve správném Ghostty okně → jen přepni window/pane
      tmux select-window -t "$arg" \; select-pane -t "$arg"
    elif tmux list-clients -F '#{client_session}' | grep -Fxq "$target_session"; then
      # session zobrazuje JINÝ Ghostty klient → přepni v ní a zaostři jeho okno;
      # aktuální okno necháme být
      tmux select-window -t "$arg" \; select-pane -t "$arg"
      focus_ghostty_window "$target_session" \
        || tmux display-message "Session '$target_session' běží v jiném okně — přepni se ručně."
    else
      # session není nikde attachnutá → přitáhni ji do aktuálního okna (dnešní chování)
      tmux switch-client -t "$arg" \; select-window -t "$arg" \; select-pane -t "$arg"
    fi
    ;;
```

- [ ] **Step 3: Syntax check skriptu**

Run: `/opt/homebrew/bin/bash -n ~/.claude/scripts/tmux-claude-switcher.sh`
Expected: bez výstupu (žádná syntaktická chyba).

- [ ] **Step 4: Manuální test — scénář „jiné okno / jiná Space"**

Předpoklad: běžící Claude session v jiné Ghostty okně, ideálně na jiné Space, než jsi teď.
1. Stiskni F3.
2. Vyber tu session.

Expected: macOS přeskočí na okno (a jeho Space), kde session běží; ve správné session je vybrané její window/pane. Tvoje původní okno se nezměnilo.

- [ ] **Step 5: Manuální test — scénář „stejné okno"**

Předpoklad: Claude session v jiném tmux **window** téže session, kterou máš v aktuálním Ghostty okně.
1. Stiskni F3.
2. Vyber tu session.

Expected: aktuální Ghostty okno přepne na její window/pane (žádný systémový přeskok okna).

- [ ] **Step 6: Manuální test — scénář „neattachnutá session"**

Předpoklad: Claude session v tmux session, která nemá žádného klienta (`tmux list-clients` ji neobsahuje), ale má tmux okno.
1. Stiskni F3.
2. Vyber ji.

Expected: session se přitáhne do aktuálního Ghostty okna (dnešní chování), vybrané její window/pane.

- [ ] **Step 7: Manuální test — fallback při nenalezeném okně**

Ověř, že když cílové Ghostty okno neexistuje, switcher nespadne a zobrazí hint:
přímý test helperu s neexistujícím titulkem.

Run:
```bash
source ~/.claude/scripts/tmux-claude-switcher.sh 2>/dev/null  # načte jen funkce (skript bez TMUX hned exitne — spusť uvnitř tmuxu)
fmt_backup="$(tmux show-options -gv set-titles-string)"
focus_ghostty_window "__neexistujici_session__"; echo "exit=$?"
```
Expected: `exit=1` (okno nenalezeno), žádná viditelná chyba osascript.
Reálná cesta: ve fzf vyber session zobrazenou jiným klientem, jejíž Ghostty okno mezitím zavřeš → tmux zpráva „… přepni se ručně.", switcher doběhne bez pádu.

- [ ] **Step 8: Commit (mimo tento repo — jen pokud je `~/.claude` git repo)**

`~/.claude/scripts/` není součást tohoto `.tmux` repa. Pokud je `~/.claude` samostatný git repo, commitni tam:
```bash
git -C ~/.claude add scripts/tmux-claude-switcher.sh
git -C ~/.claude commit -m "F3 switcher: focus existing Ghostty window across Spaces"
```
Pokud `~/.claude` není git repo, změna zůstává jen na disku (sdílená oběma vývojáři) — zaznamenej to v závěrečné zprávě uživateli.

---

### Task 3: Sync dokumentace

**Files:**
- Modify: `tmux-help` (jen pokud zmiňuje chování F3)

- [ ] **Step 1: Zkontrolovat, zda tmux-help popisuje F3**

Run: `grep -n F3 tmux-help`
Expected: pokud existuje popis F3, aktualizuj ho, ať zmíní „skočí do okna session i přes workspace". Pokud F3 v helpu není, přeskoč (keybind se nemění, jen chování).

- [ ] **Step 2: Commit (jen pokud se tmux-help měnil)**

```bash
git add tmux-help
git commit -m "tmux-help: F3 jumps to session window across workspaces"
```

---

## Hotovo, když

- Všechny tři scénáře (Task 2 kroky 4–6) se chovají dle očekávání.
- Fallback (krok 7) nespadne a zobrazí hint.
- `tmux.conf` změna je commitnutá v tomto repu; switcher změna je na disku (a commitnutá v `~/.claude`, je-li to repo).

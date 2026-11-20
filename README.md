# Fellowship Desktop

Gandalf (albo ktoś inny z Drużyny) stoi na pulpicie Maca i pokazuje, co robi Claude Code.

![Postacie i stany](docs/preview.png)

| Stan Claude Code | Co robi postać |
|---|---|
| pracuje | maszeruje (animacja pracy) |
| czeka na Twoją zgodę lub odpowiedź | podskakuje, czerwony dymek z nazwą projektu |
| skończył | podskakuje, zielony dymek „gotowe!”; kliknij postać, żeby odpoczęła |
| nic się nie dzieje | pyka fajkę |

Przy kilku sesjach naraz postać pokazuje najpilniejszą: czeka > pracuje > skończył > odpoczywa.
Działa z Claude Code w terminalu, w Herdrze, w VS Code i w aplikacji desktopowej Claude, bo wszystkie czytają te
same hooki z `~/.claude/settings.json`.

## Instalacja

Wymaga macOS 13+ na Apple Silicon i Xcode (albo Command Line Tools ze Swiftem 5.10+).

```bash
git clone <ten-repo> && cd fellowship-desktop
scripts/install.sh
```

Skrypt buduje aplikację, kopiuje ją do `~/Applications/FellowshipDesktop.app` i uruchamia. Nic poza tym nie zmienia.

### Status Claude Code (opcjonalnie)

```bash
scripts/install-hooks.sh
```

Dopisuje do `~/.claude/settings.json` hooki `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PermissionRequest`, `Notification`, `Stop` i `SessionEnd`. Przed zmianą robi kopię
(`settings.json.fellowship-backup-<data>`), inne ustawienia i hooki zostawia. Można go uruchomić drugi raz.
Usunięcie: `scripts/install-hooks.sh --remove`.

Hook to ta sama aplikacja wywołana jako `FellowshipDesktop hook`: czyta JSON od Claude Code i zapisuje stan sesji
w `~/Library/Application Support/FellowshipDesktop/sessions/`. Trwa ok. 15 ms, nic nie wypisuje i nie łączy się
z siecią.

## Menu na pasku

Ikonka postaci na pasku menu:

- **Postać**: Gandalf, Frodo, Sam, Aragorn, Legolas, Gimli, Sauron
- **Edycja**: losowa przy starcie (10% rzadka, 1% Epic Sax Gandalf), zwykła, rzadka, Epic Sax Gandalf
- **Rozmiar**: mała, średnia, duża
- dźwięk, gdy Claude czeka lub skończy; uruchamianie przy logowaniu
- ukryj / pokaż, przywróć w prawy dolny róg

Postać przeciągasz myszką. Klika się tylko w samą postać, reszta okna przepuszcza kliknięcia.

## Rozwój

```bash
swift test                                   # testy
swift run FellowshipDesktop                  # uruchomienie z repo (sprite'y z Sprites/)
swift run FellowshipDesktop preview out.png  # arkusz z postaciami, jak docs/preview.png
scripts/build-app.sh                         # build/FellowshipDesktop.app
```

## Licencje

- Kod: MIT, zob. [LICENSE](LICENSE).
- Pikselowe postacie w `Sprites/` pochodzą z
  [joaovitorwoliveira/herdr-middle-earth](https://github.com/joaovitorwoliveira/herdr-middle-earth)
  (MIT, © 2026 joaovitorwoliveira), zob. [Sprites/LICENSE](Sprites/LICENSE).
- Projekt fanowski, niezwiązany z Middle-earth Enterprises, Tolkien Estate ani Warner Bros.

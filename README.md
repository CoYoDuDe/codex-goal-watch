# codex-goal-watch

Sicheres automatisches Fortsetzen usage-limitierter OpenAI-Codex-CLI-Goals in GNU-screen-Sitzungen auf Debian und Ubuntu.

> Inoffizielles Community-Projekt – nicht mit OpenAI verbunden und nicht von OpenAI unterstützt oder empfohlen.
> Unofficial community project – not affiliated with or endorsed by OpenAI.

`codex-goal-watch` ist ein Kompatibilitäts-Supervisor für unbeaufsichtigte Codex-CLI-Sitzungen. Sobald Codex eine gleichwertige native Funktion bietet, hat diese Vorrang.

## Zweck

Der Watchdog liest die sichtbare Terminalausgabe von GNU screen. Er akzeptiert nur die eindeutige Kombination aus Codex-Usage-Limit, pausiertem Goal und gültiger angezeigter Reset-Zeit. Erst nach Reset und Sicherheitsfrist wird ein Resume versucht – und nur bei sicher erkennbarer Composer-Zeile.

Mehrere Sitzungen können registriert und aktiviert sein. Version 0.1.0 untersucht alle aktivierten Sitzungen, sendet aber höchstens eine Resume-Aktion pro Timerlauf und setzt danach einen globalen Cooldown. Eine höhere Zahl bei der Priorität gewinnt; bei gleicher Priorität entscheiden Wartezeit und Sitzungsname. Dadurch wird ein gemeinsames Codex-Kontingent nicht unkontrolliert mehrfach genutzt.

## Sicherheitsmodell

Standard ist immer Fail-closed:

- Unbekannte, mehrdeutige oder versteckte Composer-Inhalte werden niemals abgesendet.
- Eine allgemeine Limitmeldung, ein Goal-Status oder eine Reset-Zeit allein lösen keine Eingabe aus.
- Bei leerem Composer wird `/goal resume` plus Enter gesendet. Bei sichtbar vorbereitetem `/goal resume` wird nur Enter gesendet.
- Ein vollständig versteckter Entwurf `[Pasted Content ...]` bleibt blockiert, bis `codex-goal-watch arm-enter NAME` die einmalige, sitzungsgebundene Freigabe setzt.
- Replace-goal-Dialoge werden in v0.1.0 bewusst nur erkannt und blockiert, nie bestätigt.
- Globales `flock`, Fingerprints, sitzungsspezifische Versuchszähler, erneutes Lesen vor der Eingabe, Nachprüfung und Retry-Fristen verhindern Mehrfachsendungen und Stürme.
- Ein erfolgreicher `screen`-Tastendruck gilt nicht als erfolgreicher Codex-Resume. Erst eine spätere sichtbare Zustandsänderung bestätigt den Erfolg.
- `/goal resume` und Enter werden als eine zusammengehörige Eingabe übertragen, damit kein Enter zwischen zwei Screen-Operationen verloren geht.

Die Codex-TUI kann sich ändern. Vor einer Aktivierung sollte immer `inspect` verwendet werden, da das Projekt nur sichtbare Terminalausgabe auswertet.

## Voraussetzungen

- Debian 12+ oder Ubuntu 22.04+
- Bash 5, GNU screen, Python 3.9+, `flock`, `pstree`, GNU `date`, `logger` und systemd
- Codex CLI in einer GNU-screen-Sitzung des konfigurierten Linux-Benutzers

## Installation

```bash
git clone https://github.com/CoYoDuDe/codex-goal-watch.git
cd codex-goal-watch
sudo ./scripts/install.sh --enable
```

Eine Sitzung kann direkt bei der Installation registriert werden:

```bash
sudo ./scripts/install.sh --user root --session projekt-alpha --window auto --timezone Europe/Berlin --enable
```

Der Installer sichert vorhandenes Programm, Bibliotheken, Konfiguration, Zustand und systemd-Dateien. Eine alte Einzelsitzungsdatei `active` wird in die Mehrsitzungs-Registry migriert; einmalige Freigaben werden dabei entfernt.

## Schnellstart mit mehreren Sitzungen

```bash
sudo codex-goal-watch add projekt-alpha auto --priority 100
sudo codex-goal-watch add projekt-beta auto --priority 80
sudo codex-goal-watch add projekt-gamma auto --priority 50

codex-goal-watch list
codex-goal-watch inspect --all
codex-goal-watch status --all
```

Neue Screen-Sitzungen benötigen keine Änderung der systemd-Dateien. `auto` durchsucht höchstens `WINDOW_SCAN_MAX` Fenster und verweigert mehrdeutige Treffer. `activate NAME` ist ein kompatibler Alias für `add NAME` und deaktiviert keine anderen Registrierungen. `deactivate NAME` deaktiviert nur diese eine Sitzung; `deactivate --all` ist ausdrücklich nötig, um alle zu deaktivieren.

## Befehle

| Befehl | Zweck |
| --- | --- |
| `list` | Registrierte und dynamisch erkannte Sitzungen mit letztem Zustand anzeigen. |
| `add NAME [WINDOW|auto] [--priority N] [--user USER]` | Sitzung registrieren und aktivieren. |
| `remove NAME` | Nur Registry und Laufzeitdaten entfernen, niemals screen beenden. |
| `enable NAME` / `disable NAME` | Automatische Behandlung ein- oder ausschalten. |
| `priority NAME N` | Priorität von 0 bis 100000 setzen. |
| `status [NAME|--all]` | Globalen Cooldown und Sitzungszustände anzeigen. |
| `inspect [NAME|--all]` | Vollständig lesende Analyse, sendet nie Tasten. |
| `run` | Ein Timerlauf; höchstens eine sichere Aktion möglich. |
| `arm-enter NAME` | Genau ein Enter für versteckten Paste-Inhalt dieser Sitzung erlauben. |
| `disarm-enter NAME` | Einmalfreigabe entfernen. |
| `reset-state [NAME|--all]` | Nur Retry-, Fingerprint- und Verifikationszustand löschen. |
| `cancel-pending [NAME|--all]` | Ausstehenden Zustand verwerfen, Registrierung behalten. |
| `doctor` | Abhängigkeiten und Konfiguration nur lesend prüfen. |

`--force` bei `add` oder `activate` übersteuert ausschließlich die Codex-Prozessprüfung. Keine spätere Sicherheitsprüfung wird damit abgeschaltet.

## Composer-Verhalten

| Sichtbarer Composer am Terminalende | Verhalten nach gültigem Reset |
| --- | --- |
| leerer Prompt (`>`, `:` oder Codex-Prompt) | `/goal resume` und Enter senden |
| `/goal resume` oder `/goal resume [Pasted Content ...]` | nur Enter senden |
| `[Pasted Content ...]` | `BLOCKED_HIDDEN_PASTE`, bis diese Sitzung scharf geschaltet wird |
| beliebiger anderer Text | `BLOCKED_UNKNOWN_INPUT` |
| kein sicherer Composer | `BLOCKED_COMPOSER_UNCERTAIN` |

## Konfiguration

`/etc/codex-goal-watch/config` ist eine strenge `KEY=VALUE`-Datei und kein Shell-Skript. Unbekannte Schlüssel und ungültige Werte führen sicher zum Abbruch. Standardwerte:

```text
TIMEZONE=Europe/Berlin
GRACE_SECONDS=120
RETRY_SECONDS=900
VERIFY_SECONDS=30
MAX_ATTEMPTS=3
WINDOW_SCAN_MAX=30
SCREEN_USER=root
LOG_LEVEL=info
HARD_COPY_LINES=100
MAX_CONCURRENT_SESSIONS=1
GLOBAL_ACTION_COOLDOWN_SECONDS=120
```

`MAX_CONCURRENT_SESSIONS` ist in v0.1.0 absichtlich auf `1` begrenzt. Mehrere Sitzungen dürfen warten, aber pro Lauf kann nur ein Resume gesendet werden; der globale Cooldown schützt das gemeinsame Kontingent zusätzlich.

Reset-Zeiten dürfen im 12- oder 24-Stunden-Format erscheinen. Explizite Angaben wie `18.07.2026 08:31`, `2026-07-18 08:31` oder `Jul 18th, 2026 8:31 AM` werden mit der konfigurierten IANA-Zeitzone verarbeitet; bei reinen Uhrzeiten berücksichtigt der Watchdog Tageswechsel und Sommerzeit.

## Betrieb und Fehlerdiagnose

```bash
systemctl status codex-goal-watch.timer --no-pager
systemctl list-timers --all codex-goal-watch.timer --no-pager
journalctl -u codex-goal-watch.service -n 100 --no-pager
codex-goal-watch doctor
codex-goal-watch inspect --all
```

Weitere Informationen: [Architektur](docs/architecture.md), [Sicherheitsmodell](docs/security-model.md) und [Fehlerdiagnose](docs/troubleshooting.md). Mehrere Codex-Sitzungen können dasselbe Account-Limit teilen; deshalb werden Kandidaten geordnet und nicht blind gleichzeitig fortgesetzt.

## Aktualisierung und Deinstallation

```bash
sudo ./scripts/update.sh
sudo ./scripts/uninstall.sh --keep-config
sudo ./scripts/uninstall.sh --purge --non-interactive
```

Der Updater prüft Quelltext, sichert die Installation, stoppt nur Timer und Oneshot-Service, installiert atomar, lädt systemd neu und stellt bei Fehlern die Sicherung wieder her. Weder GNU screen noch Codex werden beendet.

Der systemd-Service bleibt mit `PrivateTmp=yes` gehärtet. Für die ausschließlich lesenden GNU-screen-Hardcopies verwendet der Watchdog deshalb sein geschütztes gemeinsames Laufzeitverzeichnis unter `/run/codex-goal-watch`.

## Bekannte Einschränkungen

- v0.1.0 unterstützt GNU screen, nicht tmux.
- Änderungen an der Codex-TUI können Anpassungen der Erkennung nötig machen.
- Replace-goal-Dialoge werden erkannt und blockiert, nie bestätigt.
- Terminalbeobachtung kann keine erfolgreiche Codex-Verarbeitung beweisen; daher ist die Nachprüfung verpflichtend.

## Mitwirken

Vor Änderungen `make lint` und `make test` ausführen. Siehe [CONTRIBUTING.md](CONTRIBUTING.md).

## Unterstützung

Dieses Projekt wird unabhängig und privat entwickelt und kostenlos bereitgestellt. Freiwillige Unterstützung hilft bei Infrastruktur, Servern, Domains, Tests, Wartung und Weiterentwicklung.

- [PayPal](https://paypal.me/CoYoDuDe)
- [Buy Me a Coffee](https://www.buymeacoffee.com/CoYoDuDe)
- [Weitere Projekte und Informationen](https://dnsmith.net/)

Unterstützung ist freiwillig. Es gibt keinen Abo-Zwang und daraus entsteht kein Anspruch auf bestimmte Funktionen oder persönlichen Support.

## Lizenz

MIT. Siehe [LICENSE](LICENSE).

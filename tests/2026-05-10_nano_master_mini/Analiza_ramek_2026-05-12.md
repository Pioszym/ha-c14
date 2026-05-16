# Analiza ramek #1 E4(29) i #2 E3(29) z log_esp02_202605101228.log

Sesja Nano-master 2026-05-10 (12:28-13:58, łącznie ~90min). 560 ramek E4 i 558 ramek E3.

## Cel
Sprawdzenie unikalnych wartości w "header" pozycjach (poza znanymi dynamicznymi jak zegar, T_pok, T_sp) — czy któryś bajt traktowany jako stały faktycznie się zmienia (i jest nieidentyfikowanym parametrem).

## E4(29) #1 — analiza 560 ramek

### Stałe potwierdzone (1 unikalna wartość w całej sesji)

| f[N] | Wartość | Komentarz |
|------|---------|-----------|
| f[1] | `0x21` | src marker master id=1 |
| f[3] | `0x29` | subtyp master |
| f[4] | `0x0A` | const, znaczenie nieznane |
| f[6] | `0x00` | const |
| f[10] | `0x7E` | padding |
| f[11] | `0x00` | const |
| f[12] | `0x11` | T_pok H (zakres 17.6-31°C cały test) |
| f[16-22] | `0x7E` | padding |
| f[23] | `0x14` | const, znaczenie nieznane |
| f[29] | `0x23` | terminator |

### Dynamiczne (oczekiwane)

| f[N] | Unikalne | Komentarz |
|------|----------|-----------|
| f[2] | 119 | CRC |
| f[5] | 2 (`0x40`/`0x44`) | Programy (Normal=0x40, Poza domem=0x44) |
| f[7] | 1 (`0x06`=Sob) | DOW — sesja w niedzielę, jeden dzień |
| f[8] | 2 (`0x0C`/`0x0D`) | HH (12-13) |
| f[9] | 60 | MM (minuty) |
| f[13] | 35 | T_pok L |
| f[14] | 2 (`0x10`/`0x11`) | T_sp H |
| f[15] | 9 | T_sp L |
| f[24] | 3 (`0x00`/`0x32`/`0x64`) | **sync flag — patrz sekcja niżej** |
| f[25] | 3 (`0x01`/`0x02`/`0x03`) | rotator daty phase |
| f[26] | 3 | rotator daty value (per phase) |
| f[27] | 13 | sezon\|term\|wietrz combos |
| f[28] | 10 | bieg\|chłodz_overlay\|stable bit |

## E3(29) #2 src=44 — analiza 558 ramek

### Stałe header (16 pozycji bytewise stałych w całej sesji)

| f[N] | Wartość | f[N] | Wartość |
|------|---------|------|---------|
| f[1] | `0x44` | f[12] | `0x01` |
| f[3] | `0x29` | f[13] | `0x17` |
| f[4] | `0x32` | f[16] | `0x18` |
| f[5] | `0x00` | f[17] | `0x14` |
| f[6] | `0x05` | f[18] | `0x00` |
| f[7] | `0x0A` | f[19] | `0x24` |
| f[8] | `0x28` | f[26] | `0x20` |
| f[9] | `0x1C` | f[29] | `0x23` |
| f[10] | `0x2A` |   |   |
| f[11] | `0x1E` |   |   |

### Dynamiczne

| f[N] | Komentarz |
|------|-----------|
| f[2] | CRC (25 unique) |
| f[14] | % wyw wietrzenia (w log 1228 stale `0x1E`=30%) |
| f[15] | % naw wietrzenia (stale `0x1E`=30%) |
| f[20-25] | % per bieg B1/B2/B3 (stałe w sesji, ale user-set) |
| f[27] | 11 unique — sezon\|bypass\|wietrz |
| f[28] | 9 unique — bieg\|chłodz_overlay\|marker 0x10\|stable 0x40 |

## Werdykt: encoding ESP

ESP wysyła identyczne wartości stałych header w E4 i E3. Wszystkie 16 stałych pozycji header w E3 i 9 stałych w E4 — **bytewise match z Nano**.

Różnice tylko w polach dynamicznych (zegar, T_pok, T_sp, %, sync flag).

---

## f[24] sync flag w E4(29) — szczegółowa analiza

3 wartości w log 1228 (560 ramek total):

| Wartość | Liczba | Stan |
|---------|--------|------|
| `0x32` | 403 | "untrusted/unsynced master" — Zima/Lato bez większość sesji |
| `0x00` | 129 | Chłodzenie (Nano-specific, ZAWSZE w Chłodz) |
| `0x64` | **28** | "Trusted Master + fresh AERO sync" — RZADKI |

### Kiedy `0x64` wystąpił

Tylko **2 okresy** w całej sesji:

**Okres 1: 12:45:46 - 12:48:27 (~3 min, 20 ramek)**

- Przed (12:45:21): Manual+Lato bez+B2 → f[24]=`0x32`
- Wejście: **12:45:46.759** — zmiana Sezon=Lato bez → Zima
  - Frame: `E4,21,14,29,...,14,**64**,03,0A,02,45,23`
  - Stan: Manual+**Zima**+B2 (f[27]=0x02, f[28]=0x45=B2+stable 0x40)
- Persystencja: f[24]=`0x64` pozostał przez zmianę Termostatu Manual→Harm w 12:46:02
  - Frame 12:46:02: `...,14,**64**,02,05,00,43,23` (Harm+Zima+B1, f[28]=0x43 stable bit ZOSTAJE)
- Wyjście: **12:48:35** — utrata jednocześnie f[24] i stable bit
  - Frame: `...,14,**32**,02,05,00,03,23` (Harm+Zima+B1, f[28]=0x03 BEZ stable)

**Okres 2: 12:57:39 - 12:58:39 (~1 min, 8 ramek)**

- Wejście: **12:57:39** — Manual+Zima+B1
  - Frame: `...,14,**64**,03,0A,02,43,23` (Manual+Zima+B1 z stable)
- Wyjście: po 12:58:39 wraca do `0x32`

### Reguła Nano dla f[24]=0x64

**Wejście:**
- Świeże wejście w **Manual + Zima** (z jakiegokolwiek poprzedniego stanu)
- Towarzyszy bit `0x40` (stable) w f[28]

**Persystencja:**
- Pozostaje przez zmianę Termostatu (Manual→Harm) — "lepkie" jak stable bit
- Pozostaje dopóki nie ma zmian Sezonu lub korekty termostatu

**Wyjście:**
- Wraca do `0x32` przy zmianie Sezonu lub po nieznanym warunku (timeout?)
- Wraca razem ze stable bitem `0x40` (oba zanikają razem)

### Interpretacja (per HISTORY 2026-05-11 wieczór)

`f[24]=0x64` = **"Trusted Master + Fresh AERO Heartbeat"** — synced state z fabrycznym sparingiem AERO-Nano.

**ESP NIGDY nie wysyła `0x64`** bo:
- Nie ma fabrycznego sparingu z AERO (instalacja "po fakcie")
- Wysyłanie `0x64` przez ESP wprowadza AERO w "service mode TX off" (analogicznie do bit `0x40`)
- Bezpiecznie: ESP zawsze `0x32` (lub `0x00` w Chłodz po fix 2026-05-12)

### Tabela kompletna f[24] przez sezon

Z log 1228 + obserwacje ESP:

| Sezon | Term | f[24] Nano | f[24] ESP |
|-------|------|------------|-----------|
| Zima | Manual+B1/B2/B3 (świeże wejście) | `0x64` (28 ramek) | `0x32` |
| Zima | Harm/Urlop | `0x32` | `0x32` |
| Zima | Manual+B1/B2/B3 (po dłuższym czasie?) | `0x32` | `0x32` |
| Lato bez | wszystkie | `0x32` | `0x32` |
| Chłodz | wszystkie | `0x00` | `0x00` (po fix 2026-05-12) |

## Konkluzje

1. **Encoding header bajtów ESP = Nano w 100% (bytewise).** Wszystkie nieidentyfikowane stałe (`f[4]=0x0A`, `f[23]=0x14`, etc.) są identyczne.

2. **f[24]=0x64 nigdy nie pojawia się w ESP** — i to dobrze (per "Trusted Master" hipoteza wprowadziłoby AERO w service mode).

3. **Nano używa `0x64` rzadko** — tylko 5% ramek (28/560) i tylko w **świeżym Manual+Zima**. Po dłuższym czasie wraca do `0x32`.

4. **f[24]=0x64 wymaga `f[28]` bit `0x40` (stable)** — oba pojawiają się i znikają razem. Sparowane jako "trusted master signature".

5. **Wszystkie inne stałe header (E4 f[4]/f[6]/f[10]-f[12]/f[16-23], E3 f[4-13]/f[16-19]/f[26])** są identyczne ESP=Nano. **Nie ma "ukrytego parametru" którego ESP nie wysyła.**

## Co pozostaje niewytłumaczone (do dalszej diagnostyki)

- **Chłodz+Wietrz AERO milczy do ESP** mimo bytewise-identycznych ramek vs Nano (z f[24]=0x00 fix)
- **% wietrzenia walidacja przez AERO** — 30/30 OK, 33/33 reject, ale 30/33 lub 33/30 OK (rate-limited per cycle?)
- **Zmiana biegu B1→B2 z aktywnym Wietrz** — AERO milknie (per obserwacja 2026-05-12)

Te zachowania sugerują AERO ma state machine z walidacjami poza bytewise content ramek (timing, fingerprint, historia komend).

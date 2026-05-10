# Test Nano Slave Sync — empiryczna weryfikacja fixów esp02 (2026-05-XX)

Plan systematycznego testu w setupie **ESP=Master, Nano=Slave**. Cel:
- weryfikacja fixów esp02.yaml z 2026-05-10 (commit `9fffa9e`) w boju z prawdziwym slave
- odpowiedź na otwarte pytania §7 #6 (synced state slave), #9 (config push trigger), #14 (lag Chłodz)
- sprawdzenie niezweryfikowanych historycznych hipotez (E5 f[26]=`0x50` gdy slave aktywny)

## Setup hardware

**Pojedynczy bus RS-485** (po refaktorze esp02 — usunięty MITM forward, 1 UART):
- ESP02 GPIO16/17 (UART2) → wspólny bus z AERO i Nano
- AERO 3B na busie (pasywnie nasłuchuje E3, odpowiada E4(63))
- Nano Color CTP na busie

**Konfiguracja:**
- **ESP02**: `C14 Rola = Master` (cykl Master Full ~22.5s, 27 ramek)
  - VS slaves (id=3,4,5) WYŁĄCZONE switchami `c14_master_vs_id_*` żeby nie interferowały
  - Wersja firmware: po commit `9fffa9e` (z fixami z Faza B 2026-05-10)
- **Nano Color CTP**: w menu serwisowym
  - `TRYB W SIECI C14` = MASTER (rola)
  - `ID STEROWNIKA` = **2** (slave)
  - Ekran panelowy slave'a pokazuje stan z lokalnego termostatu + sezon kopiowany z mastera
- **AERO**: bez zmian, na busie

**Capture (przez SSH, do pliku):**
```bash
ssh -i ~/.ssh/ha_ed25519 root@homeassistant \
  "docker exec addon_5c53de3b_esphome esphome logs /config/esphome/esp02.yaml --device 192.168.88.206" \
  > log_esp02_$(date +%Y%m%d_%H%M).log 2>&1 &
```

ESP02 jako master loguje **wszystkie odebrane ramki** (Bus reader RX) — w tym:
- E4(29) src=0x21 f[3]=0x2A z Nano-slave (odpowiedź na AA wake-up #22)
- E4(63) src=0x21 z AERO (odpowiedź na E3 trigger #2 i #14)
- 80(29) src=0x44 — slave boot announcement (jednorazowo po power-on)

**Nie zobaczymy własnych ramek TX** (RS-485 transceiver nie pętli) — własne master TX ESP02 publikuje do sensorów BUS bezpośrednio (bez RX).

---

## Workflow (analogiczny do TEST_NANO_MASTER_MINI.md)

**Faza A — capture + markery:**
1. Capture do pliku (jak wyżej)
2. Operator: jedna zmiana w UI HA (lub menu Nano-slave) → komunikat na czacie
3. Analyst: marker do logu (`echo "=== T<N>: <opis> @ HH:MM:SS ===" >> logfile`)
4. Czekaj **≥45s** (5 cykli Master Full × 22.5s = 112s; zaokrągl do 60-90s)
5. Powtarzaj

**Faza B — analiza po sesji:**
1. Pobierz log + markery
2. Per-test: porównaj E4(29) src=0x2A (Nano slave odpowiedź) bajt po bajcie
3. Generuj DIFF report + lista propozycji do PROTOCOL.md (review przez Piotra)

---

## Faza 0 — Baseline po flashu fixów (powrót do produkcji)

**Operator:** ustaw na ESP02 (UI HA):
- Rola = **Master**
- Sezon = **Zima**
- Termostat = **Harmonogram**
- Wentylacja = **B1**
- Wietrzenie = **OFF**
- Bypass = **AUTO**
- Programy = **Normal**
- VS slaves (id=3,4,5) **wyłączone**

**Operator:** na Nano-slave w menu serwisowym ustaw `ID=2`, tryb sieci = MASTER (slave id=2 nasłuchuje na AA wake-up).

**Power-cycle Nano-slave** (wyciągnij + włóż wtyk RJ-12 RS485 lub przerwij zasilanie panelu).

**Capture 5+ cykli Master Full** + odnotuj:
- Czas pojawienia się **80(29) src=0x44 f[3]=0x2A** (boot announcement) — typowo ~3-5s po power-on slave
- Czas pierwszej **E4(29) src=0x21 f[3]=0x2A** (slave odpowiedź na AA wake-up)
- Stan początkowy `f[24]/f[28]` w E4(2A) — UNSYNCED (`0x32`/`0x03`) czy SYNCED (`0x64`/`0x43`)?

---

## Cykl Master Full ESP (~22.5s) — schemat (PROTOCOL §2)

```
#1  E4(29) src=0x21    Master broadcast — komenda biegu, zegar, sezon
#2  E3(29) src=0x44    Trigger AERO #1 → AERO odpowiada E4(63) ~400ms
#3  E3(29) src=0x56    iNEXT slot
#4  E2(29) src=0x44    Status broadcast
#5  E5(29) src=0x21    Setpointy + bypass + sezon
#6  F0(29) src=0x44    Heartbeat
#7  81(29) src=0x44    Heartbeat master
#8-13 D0..D5(29)       Slave config 1..6
#14 E3(29) src=0x44    Trigger AERO #2 → AERO odpowiada E4(63) ponownie
#15-21 8B/9F/82/8C/8D/8E/95(29)  Heartbeats
#22 AA(29) src=0x44    Wake-up slave id=2 → Nano slave odpowiada E4(2A) ~280ms
#23 AA(29) src=0x56    iNEXT slot
#24-27 AB/AC(29)       Wake-up id=3/4 (VS off w testowym setupie — slave nie odpowiada bo VS off)
```

**Pola dynamiczne do śledzenia:** głównie **#22 AA wake-up + odpowiedź E4(2A) z Nano-slave**.

---

# CZĘŚĆ I — Weryfikacja fixów esp02.yaml (Faza A)

Cel: potwierdzić że 5 fixów z commit `9fffa9e` daje prawidłowe ramki ESP master.

## Faza A1 — Sezon × Bypass macierz w E3 f[27]

Fix #1: E3 f[27] = `(sezon_szyld) | (bypass_cmd 2-bit) | (wietrz)`. Test: zmień Sezon i Bypass, obserwuj E3 f[27] (sensor BUS w HA lub log RX z bus readera).

| Test | Sezon | Bypass | Oczekiwane E3 f[27] |
|------|-------|--------|---------------------|
| A1.1 | Zima | AUTO | `0x01` |
| A1.2 | Zima | OFF | `0x00` |
| A1.3 | Zima | ON | `0x02` |
| A1.4 | Lato bez | AUTO | `0x09` |
| A1.5 | Lato bez | OFF | `0x08` |
| A1.6 | Lato bez | ON | `0x0A` |
| A1.7 | Chłodz | AUTO | `0x11` |
| A1.8 | Chłodz | OFF | `0x10` |
| A1.9 | Chłodz | ON | `0x12` |

**Po każdej zmianie** ≥45s. Po macierzy wróć do Zima+AUTO.

**Bonus:** sprawdź czy slave w E4(2A) **kopiuje** sezon z mastera (`f[27]` bity 3-4) — to test czy slave dalej syncuje sezon mimo nowego formatu E3 f[27].

## Faza A2 — Programy=Urlop f[28]=`0x00`

Fix #2: Programy=Urlop wysyła E4 f[28]=`0x00` (NIE `0x40`).

| Test | Akcja | Oczekiwane (sensor BUS w HA + RX log) |
|------|-------|---------------------------------------|
| A2.1 | Programy: Normal → **Urlop** | E4 f[28]=`0x00` (publikowane przez ts_bieg jako "Urlop") |
| A2.2 | Programy: Urlop → **Poza domem** | E4 f[28]=bieg ze slotu Poza-domem (np. `0x01` Stop) + f[5] bit `0x04` SET |
| A2.3 | Programy: Poza domem → **Normal** | f[28]=normalny bieg, f[5] bit `0x04` CLEAR |

**Bonus:** Slave w E4(2A) — czy kopiuje f[28]=`0x00`? Czy w stanie Programy=Urlop slave dalej raportuje swój własny bieg z EEPROM (`0x43` synced lub `0x03` unsynced)?

## Faza A3 — Stable bit warunki

Fix #3: stable `+0x40` wymaga Term=Manual + Wentylacja manual + Sezon=**Zima**.

| Test | Setup | Oczekiwane E4 f[28] | Oczekiwane f[24] |
|------|-------|---------------------|-------------------|
| A3.1 | Term=Manual, Sezon=Zima, Went=B1 | `0x43` (`0x03\|0x40`) | `0x64` |
| A3.2 | Term=Manual, Sezon=**Chłodz**, Went=B1 | `0x0B` (`0x03\|0x08`, BEZ `0x40`) | `0x00` |
| A3.3 | Term=Manual, Sezon=Lato bez, Went=B1 | `0x03` (BEZ `0x40` ani overlay) | `0x32` |
| A3.4 | Term=Harm, Sezon=Zima, Went=B1 | `0x03` (BEZ `0x40`) | `0x32` |

Po macierzy wróć do baseline.

## Faza A4 — Wietrzenie + bs_fan

Fix #5: `bs_fan = (f[27] & 0x02) != 0` rozpoznaje też `0x0A` Wietrzenie.

| Test | Akcja | Oczekiwane sensor "Wentylator" w HA |
|------|-------|-------------------------------------|
| A4.1 | Wietrzenie OFF (baseline) | true (B1 aktywny, AERO f[27]=`0x02`) |
| A4.2 | Wietrzenie **ON** | true (AERO f[27]=`0x0A`) — przed fixem było false |
| A4.3 | Wentylacja **Stop** | false (AERO f[27]=`0x00`) |
| A4.4 | Wentylacja → B1 (powrót) | true |

---

# CZĘŚĆ II — Otwarte pytania PROTOCOL §7 (Faza B)

## Faza B1 — Synced state slave (§7 #6)

**Pytanie:** kiedy Nano slave przechodzi z UNSYNCED (`f[28]=0x03`, `f[24]=0x32`) → SYNCED (`f[28]=0x43`, `f[24]=0x64`)?

**Wcześniejsze ustalenia:**
- Power-cycle slave + obecność Nano mastera + AERO → SYNCED (potwierdzone)
- Power-cycle slave + ESP master + AERO → UNSYNCED (przed fixami)

**Test po fixach:**

| Test | Krok | Co mierzymy |
|------|------|-------------|
| B1.1 | Power-cycle slave (krótka przerwa zasilania ~5s) | Czas do pierwszego E4(2A) z `f[28]=0x43` |
| B1.2 | Jeśli B1.1 nie dało SYNCED w 60s → reset slave + obserwacja 5+ minut | Może wymaga długiego okna |
| B1.3 | Power-cycle slave + ESP w trybie **Master Full** (z config push przy boot detect) | Czy config push aktywuje SYNCED? |
| B1.4 | Power-cycle slave + ESP wysyła ponownie config push co 5 cykli (ręcznie wymuszone) | Czy retransmisja config push pomaga? |

**Pomiar:** monitoruj `s_termostat_bus` / RX log przez ESP. Czas od `80(29)` boot do pierwszego `E4(29) src=0x21 f[3]=0x2A` z `f[28]=0x43`.

## Faza B2 — Config push trigger (§7 #9)

**Pytanie:** jak Nano master rozpoznaje slave i decyduje że mu wysłać E4(29) src=0x2X (config push)? Z poprzednich testów: VS slaves dostawały echo wszystkich pól, ale nigdy config push.

**Test:**

| Test | Setup | Oczekiwane |
|------|-------|------------|
| B2.1 | Power-cycle slave id=2, monitor 60s | Czy ESP master wysyła E4(29) src=0x2A? Logu RX nie zobaczy własnego TX, ale można zobaczyć w "tx_frame" debug. |
| B2.2 | Wł. VS id=3 w esp02 (`c14_master_vs_id_3`), monitor 5 cykli | Czy ESP master rozpoznaje VS jako "real slave" i wysyła config push? Powinien NIE — VS to tylko echo z ESP, nie "real" Nano. |
| B2.3 | Po B1.1, gdy slave SYNCED — zmień nastawę % naw B1 w UI HA, monitor czy ESP wysyła nowy config push do slave | Czy zmiana w EEPROM mastera triggeruje retransmisję? |

## Faza B3 — Sezon=Chłodzenie lag slave (§7 #14)

**Wcześniejsza obserwacja 2026-05-03:** po zmianie Sezon=Chłodzenie na masterze, slave reagował z opóźnieniem (nie 1-2 cykle).

**Test:**

| Test | Krok | Co mierzymy |
|------|------|-------------|
| B3.1 | Sezon Zima → Chłodzenie (na ESP master), monitor E4(2A) z slave | Czas od E4(29) master z nowym `f[27]` do E4(2A) slave z nowym `f[27]` |
| B3.2 | Sezon Chłodzenie → Zima (powrót) | Lag w drugą stronę |
| B3.3 | Wielokrotna zmiana Zima ↔ Chłodzenie co 30s | Czy lag rośnie / czy slave się gubi |

## Faza B4 — Niezweryfikowane historyczne hipotezy (PROTOCOL §7 ostatnia sekcja)

| Test | Hipoteza | Krok |
|------|----------|------|
| B4.1 | E5 f[26]=`0x50` gdy slave aktywny (vs `0x00`) | Po B1 (slave SYNCED), monitor E5 master TX f[26] przez 5 cykli. Sensor BUS w HA pokazuje to (g_slave_ack ? 0x50 : 0x00). |
| B4.2 | E4(29) f[10]=`0x08` przy fan OFF (vs `0x7E`) | Włącz Wentylacja=Stop na ESP master, monitor E4(29) z slave id=2 — czy slave ma `f[10]=0x08` w odpowiedzi? |

---

# CZĘŚĆ III — Mixy (jeśli czas) — opcjonalne

## MX-S1: Term=Urlop slave vs Term=Harm slave

Slave ma własny lokalny termostat (PROTOCOL §6.1). Zmień na Nano-slave w menu lokalny termostat:

| Test | Lokalny Termostat slave | E4(2A) f[27] bity 0-1 | E4(2A) f[14-15] |
|------|-------------------------|------------------------|------------------|
| MX-S1.1 | Manual + lokalna SP=22°C | `0x02` | 22.0 (lokalny SP) |
| MX-S1.2 | Harmonogram | `0x00` | wg lokalnego harmonogramu slave |
| MX-S1.3 | Urlop | `0x01` | wg lokalnego SP urlopu slave |

Pytanie: czy lokalna SP slave wpływa na decyzję AERO (master agreguje)? Test: ustaw lokalny SP slave znacznie wyższy niż T_pok slave, monitor czy ESP master zmienia bieg AERO.

## MX-S2: Power-loss recovery

| Test | Krok | Oczekiwane |
|------|------|------------|
| MX-S2.1 | Slave SYNCED → odepnij wtyk komunikacji slave (zostawia zasilanie) na 30s, podepnij | Czy slave wraca w SYNCED bez power-cycle? |
| MX-S2.2 | Slave SYNCED → odepnij zasilanie ESP master na 30s, podepnij | Czy slave wytrzymuje przerwę master + dalej SYNCED? |

---

## Bajty synchronizacji — osobny tracking

Jak w TEST_NANO_MASTER_MINI.md, ale teraz **z perspektywy odbieranej ramki E4(2A) slave**:

| Pole | Ramka | Co śledzić |
|------|-------|-----------|
| f[7] | E4(2A) | `0x02` lub `0x03` — historyczna obserwacja zmiana między sesjami |
| f[8-9] | E4(2A) | godz/min — czy slave kopiuje 1:1 z mastera? |
| f[12-13] | E4(2A) | T pokojowa slave (jego sensor CTP) — wartość niezależna |
| f[14-15] | E4(2A) | aktywny SP slave (z lokalnego harmonogramu) — niezależny od mastera |
| f[24] | E4(2A) | `0x32`/`0x64` — synced state |
| f[25-26] | E4(2A) | rotator daty kopiowany z mastera |
| f[27] | E4(2A) | sezon (bity 3-4) z mastera + lokalny tryb (bity 0-1) |
| f[28] | E4(2A) | bieg + flagi — z EEPROM slave (slave nie komenderuje AERO) |

---

## Lista pytań otwartych do zaadresowania

1. **§7 #6** — synced state slave po fixach esp02
2. **§7 #9** — kryterium config push do slave id≥3 (możliwe wymaga real Nano vs VS)
3. **§7 #14** — lag Chłodzenie slave
4. **§7 #16** — lepkość stable bit (wymagane: power-cycle Nano + sekwencja Manual; w tym teście Nano jest slave więc ESP ma stable, sprawdź lepkość ESP master po sekwencji)
5. **§7 #17** — slot Comfort harmonogramu (test wymaga harmonogramu zestrojenia, nie krytyczny w tym teście)
6. **Niezweryfikowane historyczne** — E5 f[26]=`0x50`, E4 f[10]=`0x08`

## Wskazówki praktyczne

- **5 cykli Master Full × 22.5s = ~115s** między testami — większe okno niż w teście Master Mini.
- **Power-cycle Nano-slave** = wyciągnij + włóż wtyk RJ-12 lub odłącz zasilanie panelu (w zależności od montażu Piotra).
- **Nie zmieniaj `C14 Rola`** w trakcie testu — przełączenie OFF/Master/Slave zaburzy bus (zostaw Master).
- **Po każdej fazie wracaj do baseline F0** (Sezon=Zima, Term=Harm, Went=B1, Wietrz=OFF, Bypass=AUTO, Programy=Normal).
- **VS slaves wyłączone** przez cały test (żeby nie konkurowały z prawdziwym Nano-slave o wake-up'y).

## Kolejność wykonania

```
F0 baseline + power-cycle Nano-slave (5+ minut obserwacji)
  ↓
A1 Sezon×Bypass (9 testów × 60s)
A2 Programy=Urlop (3 testy)
A3 Stable bit warunki (4 testy)
A4 Wietrzenie + bs_fan (4 testy)
  ↓
B1 Synced state slave (4 testy)
B2 Config push trigger (3 testy)
B3 Sezon Chłodz lag (3 testy)
B4 Historyczne hipotezy (2 testy)
  ↓
Faza B: analiza pełnego logu + DIFF report
  ↓
Lista propozycji do PROTOCOL.md (manual review)
```

Sesja capture szacowana **~1.5-2h**. Faza B (analiza po sesji) **~1h**.

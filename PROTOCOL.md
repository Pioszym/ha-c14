# Protokół C14 (COMPIT) — mapa ramek

Reverse engineering magistrali RS-485 między rekuperatorem **COMPIT AERO 3B** a panelem pokojowym **COMPIT Nano Color CTP**.

**Status:** częściowo rozszyfrowany, wystarczający do pełnego sterowania. Otwarte pytania niżej.

## Hardware

- Magistrala: RS-485, 9600 8N1, terminator 0x23
- Wszystkie ramki **30 bajtów** (f[0]..f[29]), f[29] = terminator `0x23`
- Padding: `0x7E` = puste pole
- Master: Nano Color CTP (tryb **MASTER MINI** — 11 ramek/cykl ~8.5s)
- Slave główny: AERO 3B (odpowiada tylko na trigger)

### Uwagi o RS-485 transceiverach

- **HW-0519 (auto-direction, 3.3V)** używane w projekcie **nie echują TX na RX** — chip blokuje RO podczas TX. Echo filter w kodzie **niepotrzebny**.
- Moduły z pinem DE/RE (np. MAX485) echują jeśli pin nie jest poprawnie sterowany — dla nich trzeba filtrować lub używać GPIO do przełączania kierunku.
- Przy `auto-direction` slot po TX musi być minimum kilka ms (chip potrzebuje czasu na przełączenie), ale dla 800ms slot AERO odpowiedź (400ms) zmieściła się bez problemu.

## Adresy / markery typu ramki (f[1])

**UWAGA:** `f[1]` to **marker typu ramki**, NIE adres źródłowy.

| f[1] | Znaczenie |
|------|-----------|
| 0x21 | Ramki sterujące (E4, E5, E4_63) |
| 0x44 | Broadcasty (D0-D2, E3, E2, F0, 81) |
| 0x56 | Slot iNext/EX4 |
| 0x63 | Tylko E4 od AERO (odpowiedź) |

## Checksum (f[2])

Formuła: `(f[0] + f[1] + sum(f[3]..f[28]) + K) & 0xFF`

| K | Dotyczy ramek |
|---|---------------|
| **0xA3** | E4(29), E4(63), E5(29), E3(29)_44, E3(29)_56, E2(29), F0(29), D0-D2(29), 81(29) — **prawdopodobnie wszystkie** |

> **Historia:** wcześniej (memory) zakładano różne K dla różnych ramek. Empirycznie zweryfikowane 2026-04-19 — wszystkie obserwowane ramki C14 w tym setupie używają **K=0xA3**. Jeśli pojawią się ramki z innym K, uzupełnić tabelę.

## Master ID — pole f[3] (subtyp ramki)

**Wzór:** `f[3] = 0x28 + id` — gdzie `id` to numer sterownika (Nano Color) w menu serwisowym.

| ID | f[3] | Rola |
|----|------|------|
| 1 | 0x29 | **Master główny** — jedyny z pełną kontrolą biegów/bypass |
| 2 | 0x2A | Slave/pasywny (UI biegów ukryte na Nano) |
| 3 | 0x2B | Slave/pasywny |
| 5 | 0x2D | Slave/pasywny |
| 10 | 0x32 | Slave/pasywny |
| 20 | 0x3C | Slave/pasywny |
| ... | 0x28+id | (do max ~20) |

Potwierdzone empirycznie testami 2026-04-22:
- Zmiana ID w menu Nano → zmienia `f[3]` we wszystkich ramkach wysyłanych przez ten sterownik
- Power cycle nie zmienia ID (zapamiętane w EEPROM Nano)

### Różnice w zachowaniu master vs slave w ramce E4(29)

Tylko master **id=1** może sterować biegami — pozostałe ID nadają ramki, ale bez komendy biegu:

| ID | E4(29) f[28] | Znaczenie |
|----|--------------|-----------|
| 1 (master) | `0x41/0x43/0x45/0x47` | Stop / B1 / B2 / B3 |
| 1 (master, overlay) | `+0x08` na f[28] | Wietrzenie ON (0x49/4B/4D/4F) |
| 2+ (slave) | `0x03` stale | Brak komendy — "follow master" |

Konsekwencja: jeśli na magistrali **nie ma żadnego urządzenia z id=1**, AERO nie dostaje komendy biegu → wentylatory nie startują (test 2026-04-22: id=20 + power cycle = brak kontroli).

### Dual master (ESP + Nano)

- ESP jako master id=1 (`f[3]=0x29`) → pełna kontrola komendami
- Nano jako slave id=2 (`f[3]=0x2A`) → wyświetlacz pasywny, czyta E4(63) od AERO

Ta konfiguracja jest zgodna z dokumentacją COMPIT: "jeden master, unikalne ID dla każdego urządzenia".

## Enkoding temperatury

```
T = (H*128 + L%128 - 2000) / 10              # dekodowanie
val = T*10 + 2000; H = val/128; L = val%128  # kodowanie
```

Przykłady: `11,36` = 23.0°C · `11,40` = 24.0°C · `11,04` = 18.0°C · `10,66` = 15.0°C

## Cykle master

### Master Mini (11 ramek, ~8.5s) — obserwowane

Sekwencja Master Mini: komenda biegu najpierw, trigger QUERY zaraz po, potem reszta broadcastów.

| # | Ramka | Nadawca | Rola |
|---|-------|---------|------|
| 1 | E4(29) src=0x21 | **Master** | Komenda biegu + zegar |
| 2 | E3(29) src=0x44 | **Master** | **QUERY — trigger AERO** |
| 3 | E4(63) src=0x21 | **AERO** | Odpowiedź AERO (~400ms po triggerze) |
| 4 | E3(29) src=0x56 | **Master** | iNEXT slot (zera) |
| 5 | E2(29) src=0x44 | **Master** | Status broadcast |
| 6 | E5(29) src=0x21 | **Master** | Setpointy temperatur + bypass |
| 7 | F0(29) src=0x44 | **Master** | Heartbeat (0x7E fill) |
| 8 | 81(29) src=0x44 | **Master** | Heartbeat Master |
| 9 | D0(29) src=0x44 | **Master** | Slave config 1 |
| 10 | D1(29) src=0x44 | **Master** | Slave config 2 |
| 11 | D2(29) src=0x44 | **Master** | Slave config 3 |

Uwaga: w Master Mini Nano slave jest **cichy** — nie odpowiada na żadną ramkę. Dla aktywacji slave potrzebna AA(29) src=0x44 z Master Full.

### Master Full (27 ramek, ~22s) — obserwowane

Master Full to rozszerzona wersja Mini, aktywowana w menu serwisowym Nano (TRYB W SIECI C14 = MASTER). Dodaje 17 ramek enumeration/keepalive dla rzadkich slave ID. **E3(29)_44 występuje DWA razy w cyklu** — AERO odpowiada E4(63) dwukrotnie per cykl (~10s + ~13s split).

Pełna sekwencja w kolejności nadawania:

| # | Ramka | Nadawca | Rola |
|---|-------|---------|------|
| 1 | E4(29) src=0x21 | **Master** | Komenda biegu + zegar (lub jednorazowo E4(29) src=0x2A config push po boot slave) |
| 2 | E3(29) src=0x44 | **Master** | **QUERY #1 — trigger AERO** |
| — | E4(63) src=0x21 | **AERO** | Odpowiedź AERO #1 (~400ms po #2) |
| 3 | E3(29) src=0x56 | **Master** | iNEXT slot (zera) |
| 4 | E2(29) src=0x44 | **Master** | Status broadcast (stałe) |
| 5 | E5(29) src=0x21 | **Master** | Setpointy temperatur + bypass + sezon |
| 6 | F0(29) src=0x44 | **Master** | Heartbeat (0x7E fill) |
| 7 | 81(29) src=0x44 | **Master** | Heartbeat Master |
| 8 | D0(29) src=0x44 | **Master** | Slave config 1 |
| 9 | D1(29) src=0x44 | **Master** | Slave config 2 |
| 10 | D2(29) src=0x44 | **Master** | Slave config 3 |
| 11 | D3(29) src=0x44 | **Master** | Slave config 4 |
| 12 | D4(29) src=0x44 | **Master** | Slave config 5 |
| 13 | D5(29) src=0x44 | **Master** | Slave config 6 |
| 14 | E3(29) src=0x44 | **Master** | **QUERY #2 — drugi trigger** (identyczne jak #2) |
| — | E4(63) src=0x21 | **AERO** | Odpowiedź AERO #2 |
| 15 | 8B(29) src=0x44 | **Master** | Heartbeat slave ID 0x8B (0x7E fill) |
| 16 | 9F(29) src=0x44 | **Master** | Heartbeat 0x9F |
| 17 | 82(29) src=0x44 | **Master** | Heartbeat 0x82 |
| 18 | 8C(29) src=0x44 | **Master** | Heartbeat 0x8C |
| 19 | 8D(29) src=0x44 | **Master** | Heartbeat 0x8D |
| 20 | 8E(29) src=0x44 | **Master** | Heartbeat 0x8E |
| 21 | 95(29) src=0x44 | **Master** | Heartbeat 0x95 |
| 22 | AA(29) src=0x44 | **Master** | **Wake-up dla slave id=2** (0x7E fill) |
| — | E4(29) src=0x21 f[3]=0x2A | **Slave** | **Odpowiedź slave** E4(2A) (~400ms po #22, jeśli slave obecny) |
| 23 | AA(29) src=0x56 | **Master** | Broadcast 0xAA iNEXT-side (0x00 fill) |
| 24 | AB(29) src=0x44 | **Master** | Broadcast 0xAB master-side |
| 25 | AB(29) src=0x56 | **Master** | Broadcast 0xAB iNEXT-side |
| 26 | AC(29) src=0x44 | **Master** | Broadcast 0xAC master-side |
| 27 | AC(29) src=0x56 | **Master** | Broadcast 0xAC iNEXT-side |

**Zdarzenia asynchroniczne (poza cyklem master):**

| Kiedy | Ramka | Nadawca | Rola |
|-------|-------|---------|------|
| Po power-on slave (1× jednorazowo, ~3-5s po starcie, **losowa pozycja w cyklu** — bus arbitration) | 80(29) src=0x44 f[3]=0x2A | **Slave** | Slave boot announcement (`80,44,5F,2A,7E×26,23`) |
| ~16s po boot slave (1× w najbliższym cyklu master) | E4(29) src=0x2A | **Master** | Config push do slave id=2 — zastępuje pozycję #1 cyklu |
| Co cykl po wykryciu AA(29)_44 (#22) | E4(29) src=0x21 f[3]=0x2A | **Slave** | Odpowiedź slave (~400ms po #22) — obecna gdy slave id=2 aktywny |

**17 ramek dodatkowych (#11-13, #14, #15-21, #22-27) ma zawartość statyczną** (0x7E lub 0x00 fill) — enumeration/keepalive. Mimo to Master Full jest **wymagany** żeby Nano w trybie slave zaczął aktywnie komunikować się na magistrali (w Mini Nano slave jest całkowicie cichy). Konkretnie **AA(29) src=0x44 (#22)** jest wake-up'em dla Nano slave.

**Ramka specjalna E4(29) src=0x2A** pojawia się **jednorazowo** na pozycji #1 ~16s po power-on Nano slave (detail w sekcji niżej). Zastępuje standardową E4(29) src=0x21 w tym jednym cyklu. W kolejnych cyklach wraca standardowa E4(29) src=0x21.

### Timing odpowiedzi AERO (zmierzone przez bridge MITM)

| Czas (względny) | Zdarzenie |
|-----------------|-----------|
| t+0.0s | Master wysyła E4(29) |
| t+0.8s | Master wysyła E3(29) src=0x44 (trigger) |
| t+1.2s | **AERO odpowiada E4(63)** (~400ms po triggerze) |
| t+1.6s – koniec | Reszta ramek mastera (broadcasty, enumeration) |

W Master Full drugi trigger #14 → druga odpowiedź AERO w t+~11s.

Dla ESP-mastera: po wysłaniu E3(29)_44 wystarczy slot **≥500ms** na nasłuch E4(63).

### Role ramek w cyklu

| Ramka | Efekt po stronie AERO |
|-------|----------------------|
| **E4(29) src=0x21** | Komenda biegu — AERO reaguje mechanicznie (zmienia wentylator), NIE odpowiada ramką |
| **E3(29) src=0x44** | **TRIGGER** dla odpowiedzi E4(63). Wystarczy ta jedna ramka żeby AERO odpowiedziało |
| E3(29) src=0x56 | iNEXT slot (ignorowana przez AERO) |
| E2, E5, F0, 81, D0-D2 | Broadcasty dla slaves (iNEXT, EX4, Nano-slave) — AERO ignoruje |

Minimalna ramka triggerująca odpowiedź AERO:
```
E3,44,[cks],29,32,00,05,0A,28,1C,2A,1E,01,17,5F,64,18,14,00,24,20,28,46,25,2D,4B,20,01,53,23
```

(Zobacz [HISTORY.md](HISTORY.md) — sekcja "Odkrycie triggera przez button-per-frame test" dla procesu weryfikacji.)

---

## Menu Nano — kompletny mapping ustawień (2026-04-26)

Lista wszystkich zaobserwowanych ustawień w menu użytkownika i serwisowym Nano oraz **gdzie w protokole** są kodowane.

### 1. Termostat (tryb sterowania temperaturą)

3 opcje w menu Nano (ikony):
- 🕐 Harmonogram
- 🕐🍸 Urlop (zegarek + kieliszek = wariant harmonogramu)
- 👆 Manual

| Pole | Manual | Harmonogram | Urlop |
|------|--------|-------------|-------|
| **E4 f[27]** bity 0-1 | 0x02 | 0x00 | 0x00 (jak Harm) |
| Aktywny setpoint w E4 f[14-15] | manual (25°C) | dynamiczny z harmonogramu | poza_domem (20°C) lub eco_lato (18°C) |
| Bit 0x40 stable w f[28] | tak (jeśli Zima) | nie | nie |

### 2. Sezon / Tryb pracy instalacji

3 opcje:
- Zima ogrzewanie
- Lato bez ogrzewania/chłodzenia
- Chłodzenie aktywne

| Pole | Zima | Lato | Chłodzenie |
|------|------|------|------------|
| **E4 f[27]** bity 3-4 | 0x00 | 0x08 | 0x10 |
| **E5 f[27]** | 0x00 | 0x0A | 0x14 |
| **E3 f[27]** bity 3-4 (+ stała 0x01) | 0x01 | 0x09 | 0x11 |
| **E4 f[28]** bit 0x08 (chłodz overlay) | nie | nie | tak |

### 3. Wentylacja (bieg)

6 opcji:
- Harmonogram (B z harmonogramu, np. eco=B1)
- Harmonogram-Urlop (wariant urlopowy harmonogramu)
- B3 (manual)
- B2 (manual)
- B1 (manual)
- Stop

| Bieg | E4 f[28] (bez stable) | E3 f[28] (= bieg \| 0x10 znacznik) |
|------|------------------------|-----------------------------------|
| Stop | 0x01 | 0x11 |
| B1 | 0x03 | 0x13 |
| B2 | 0x05 | 0x15 |
| B3 | 0x07 | 0x17 |

E5 f[28] zawiera kompozycyjny "UI screen code" zależny od (Termostat × Sezon × Bieg × Wentylacja) — patrz oddzielna tabela.

### 4. Wietrzenie (overlay)

ON/OFF — niezależny od sezonu i trybu temp.

| Pole | OFF | ON |
|------|-----|-----|
| **E4 f[27]** bit 0x20 | 0 | **+0x20** |
| **E3 f[27]** bit 0x20 | 0 | **+0x20** |
| **E5 f[27]** | brak wpływu | brak wpływu |

### 5. Programy trybu pracy (zweryfikowane 2026-04-26)

W menu Nano "Program" jest **3-stanowy radio** (mutually exclusive):
- **Normal** (żadna ikona) — domyślny harmonogram
- **Poza domem** (ikona poza domem)
- **Urlop** (ikona urlopu)

Włączenie jednego automatycznie wyłącza drugi.

**Empirycznie potwierdzone:**

| Program | f[5] | f[28] (E4) | f[15] aktywny setpoint |
|---------|------|-----------|------------------------|
| **Normal** | 0x44 | bieg z harmonogramu (0x03 dla B1) | eco_zima/comfort/poza_domem (cyklicznie z harmonogramu) |
| **Poza domem** | 0x44 | bieg z harmonogramu (0x03 dla B1) | **poza_domem (20°C) stale** |
| **Urlop** | 0x40 | **0x02** (specjalny kod "stop urlop") | poza_domem (20°C) |

**Bit 0x04 w f[5] = "harmonogram aktywny"**:
- SET (f[5]=0x44) → master rotuje setpoint zgodnie z harmonogramem (lub używa Poza_domem dla Programu Poza domem)
- CLEAR (f[5]=0x40) → harmonogram zatrzymany, wentylator zatrzymany (Urlop)

**Różnica Normal vs Poza domem:**
- W ramce **identyczne** (oba f[5]=0x44, f[28]=0x03)
- Setpoint może się różnić — Poza domem stale używa Poza_domem (20°C), Normal cyklicznie wybiera z harmonogramu
- Z perspektywy slave i AERO **nieodróżnialne** — Nano aplikuje override lokalnie

**Różnica Urlop:**
- f[28]=0x02 to **wartość poza tabelą biegów** (bit 0 "validity" = 0) — kod "zatrzymaj komendę biegu"
- AERO interpretuje jako "tryb urlop, wentylacja minimalna"
- f[5] bit 0x04 wyłączony — harmonogram nieaktywny

**Setpoint współdzielony:** menu serwisowe Nano ma jedną nastawę "Poza Domem" (20°C) używaną dla OBU programów (Poza domem i Urlop).

### 6. Setpointy temperatur (menu serwisowe Nano)

5 niezależnych setpointów w EEPROM Nano:

| Setpoint | Wartość przykł. | Pozycja w E5 broadcast |
|----------|----------------|------------------------|
| Comfort | 23°C | f[8-9] |
| Eco_zima | 21°C | f[10-11] (gdy Sezon=Zima) |
| Eco_lato/chłodzenie | 18°C | f[12-13] (gdy Sezon=Lato/Chłodz) |
| Manual | 25°C | f[14-15] (gdy Termostat=Manual) |
| Poza_domem | 20°C | f[16-17] (gdy Termostat=Urlop+Zima) |

**Aktywny setpoint** (który steruje grzaniem) master kopiuje do **E4 f[14-15]** zgodnie z aktualnym Termostat × Sezon:
- Manual + dowolny sezon → manual setpoint
- Harm/Urlop + Zima → eco_zima (21°C) lub poza_domem
- Harm/Urlop + Lato/Chłodz → eco_lato (18°C)

### 7. Bypass (f[25] w E5)

3 opcje:
- Manual OFF → 0x60
- AUTO → 0x61
- Manual ON → 0x62

W AUTO AERO sam decyduje (np. otwiera w trybie Chłodzenie dla free-cooling).

### 8. Zegar, dzień tygodnia i data

Master nadaje czas + datę w E4(29) src=0x21:

| Pole | Znaczenie | Format |
|------|-----------|--------|
| f[7] | day_of_week | `0=Pn, 1=Wt, 2=Śr, 3=Cz, 4=Pt, 5=Sob, 6=Nd` |
| f[8] | godzina | decimal jako byte (0x0A=10) |
| f[9] | minuta | decimal jako byte (0x0F=15) |
| f[25-26] | data w 3 fazach (rotujące) | patrz tabela poniżej |

**Transmisja daty f[25-26]** — 3 fazy po 1 ramce każda, master rotuje co cykl Master Full:

| f[25] | f[26] |
|-------|-------|
| 0x01 | rok mod 100 (np. 0x16=22 → 2022) |
| 0x02 | miesiąc (1-12) |
| 0x03 | dzień miesiąca (1-31) |

Slave rekonstruuje pełną datę po 3 cyklach (~66s).

---

## Slave SYNC z mastera

Slave Nano (E4(2A) src=0x21) odbija w cyclic odpowiedzi WSZYSTKIE pola z mastera:

| Pole slave | Źródło z mastera |
|------------|------------------|
| f[7] day_of_week | f[7] master |
| f[8-9] godz/min | f[8-9] master |
| f[25-26] data (3 fazy) | f[25-26] master |
| f[27] tryb termostatu + sezon + wietrzenie | f[27] master |
| f[28] bieg + flagi | f[28] master |
| f[14-15] aktywny setpoint | f[14-15] master |

Slave jest **w pełni reaktywny** — wszystko co master nadaje, slave przyjmuje natychmiast (1-3 cykle).

---

## Ramka E4(29) — KOMENDA biegu (src=0x21)

Nano → AERO. Komenda biegu + zegar + flagi trybów. AERO reaguje mechanicznie (zmienia wentylator), ale **nie odpowiada** tą ramką.

```
E4,21,[cks],29,[DOM],40,00,[DOW],[HH],[MM],7E,00,[TRM_H],[TRM_L],[SP_H],[SP_L],7E×7,14,[X24],[ROT],[LK],[F27],[F28],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE4` | ID ramki | KNOWN |
| f[1] | `0x21` | marker typu (komenda master) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x29` | subtyp (master id=1) | KNOWN |
| f[4] | `0x0A` | stała dla Nano master (znaczenie nieznane) | UNKNOWN |
| f[5] | `0x40/0x44` | **Flaga trybu:** `0x44`=harmonogram aktywny (Normal/Poza domem), `0x40`=harmonogram WYŁĄCZONY (URLOP) | KNOWN |
| f[6] | `0x00` | stałe | UNKNOWN |
| f[7] | 0-6 | **Dzień tygodnia** (`0=Pn..6=Nd`) | KNOWN |
| f[8] | 0-23 | **Godzina** (decimal jako byte) | KNOWN |
| f[9] | 0-59 | **Minuta** (decimal jako byte) | KNOWN |
| f[10] | `0x7E/0x08` | 0x7E normalnie, 0x08 obserwowane przy fan OFF | PARTIAL |
| f[11] | `0x00` | stałe | UNKNOWN |
| f[12-13] | HH,LL | **Temp pokojowa Nano** (sensor wewn CTP) | KNOWN |
| f[14-15] | HH,LL | **Aktywny setpoint** (śledzi aktualnie wybrany tryb: Comfort/Eco/itp.) | KNOWN |
| f[16-22] | `0x7E` ×7 | stałe fillery | UNKNOWN |
| f[23] | `0x14` | stałe | UNKNOWN |
| f[24] | `0x32/0x64` | tryb mocy: 0x64 = synced (Manual+Zima), 0x32 = unsynced/awaryjny | KNOWN |
| f[25] | `0x00/0x01/0x02/0x03` | **Faza transmisji daty:** 0x00 init, 1=rok, 2=miesiąc, 3=dzień | KNOWN |
| f[26] | wartość daty | zależnie od f[25]: rok mod 100 / miesiąc 1-12 / dzień 1-31 | KNOWN |
| f[27] | bitfield | **Multi-field encoding** (tryb temp + sezon + wietrzenie, patrz niżej) | KNOWN |
| f[28] | bitfield | **BIEG + overlays** (patrz niżej) | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

**Niezmapowane / niejednoznaczne w E4(29) src=0x21:**
- f[4]=0x0A — stała Nano (model? wersja?)
- f[10] — 0x7E/0x08 podczas fan OFF
- f[23]=0x14 — stała nieznana
- Bit 0 w f[27] — pojawia się tylko Urlop+Wentyl=Manual / Urlop+Chłodz, funkcja nieznana

### E4(29) f[27] — multi-field encoding (uściślone 2026-04-25)

Jeden bajt koduje 3 niezależne wymiary stanu:

**Bity 0-1 = Tryb sterowania temperaturą:**
| Bits | Tryb | Ikona Nano |
|------|------|-----------|
| 0x00 | Harmonogram | 🕐 |
| 0x00 | **Urlop** | 🕐🍸 (zegarek + kieliszek) — wariant harmonogramu |
| 0x02 | Manual | 👆 |

**WAŻNE:** Urlop **NIE ma własnego kodu** w f[27] — używa 0x00 jak Harmonogram. Wcześniejsza hipoteza `0x01 = Urlop` była błędna (obserwowana tylko gdy Nano był slave i miał stary stan EEPROM). Empirycznie zweryfikowane: master Nano wysyła `f[27]=0x00` zarówno dla Harmonogramu jak i Urlopu. Różnicę (Urlop vs Harmonogram) widać tylko na wyświetlaczu Nano (kieliszek + zegarek vs sam zegarek) — protokołowo identyczne, slave nie odróżni. Urlop = "harmonogram z stałym setpointem poza_domem".

**Bity 3-5 = Sezon** (3 enum, nie bitmaska):
| Bits | Sezon |
|------|-------|
| 0x00 | Zima ogrzewanie |
| 0x08 | Lato bez ogrzewania/chłodzenia |
| 0x10 | Chłodzenie aktywne |

**Bit 5 overlay:**
| Bit | Znaczenie |
|-----|-----------|
| +0x20 | Wietrzenie ON (overlay, niezależny od sezonu i trybu temp) |

Łączne: f[27] = `tryb_temp | sezon | wietrzenie_overlay`.

### E4(29) f[28] — BIEG + flaga "stable config"

Bit 0 = validity flag (zawsze set), bity 1-2 = value biegu (0-3):

| Bieg | f[28] (bez bitu 0x40) |
|------|---------------------|
| Stop | `0x01` |
| B1 | `0x03` |
| B2 | `0x05` |
| B3 | `0x07` |

**Overlays:**
- `+0x08` (bit 3) = chłodzenie aktywne (dodawane do biegu: manual B1+cool = `0x0B`)
- `+0x40` (bit 6) = **STABLE CONFIG flag** (uściślone 2026-04-25)

**Bit 0x40 — empirycznie zweryfikowane (2026-04-25):**

Wcześniejsza hipoteza: `0x40 = harmonogram`. **BŁĘDNA**.

Faktyczna obserwacja:
- **Manual + Zima** → f[28] z bitem 0x40 (np. `0x43` dla B1) + f[24]=0x64 (synced)
- **Harmonogram/Urlop + Zima** → f[28] BEZ bitu 0x40 (np. `0x03`) + f[24]=0x32 (unsynced)
- **Lato bez / Chłodzenie** (dowolny tryb) → f[28] BEZ bitu 0x40 + f[24]=0x32

Wniosek: bit `0x40` to **"stable config" flag** — pojawia się tylko gdy master ma jednoznaczny, niezmienny w czasie setpoint do narzucenia slave (Manual + sezon=Zima default). Przy Harmonogramie setpoint zmienia się dynamicznie (eco/comfort/poza_domem), więc master nie może go uznać za "stable" → bit znika. Przy alternatywnych sezonach (Lato/Chłodzenie) także unsynced.

**Para z f[24]:** bit 0x40 w f[28] zawsze paruje się z `f[24]=0x64` (mocy 100%). Bez bitu — `f[24]=0x32` (50% / fallback).

**Uwaga:** AERO reaguje mechanicznie **tylko na bity 1-2** (value biegu). Bit `0x40` (stable) i `0x08` (chłodzenie) ignoruje przy decyzji o prędkości wentylatora — to flagi dla slaves (Nano slave kopiuje do swojej E4(2A)).

### E5(29) f[28] — UI code (zaktualizowane 2026-04-25)

Zaobserwowane wartości w E5 src=21 (mapowanie tryb termostatu × sezon, niejednolite):

| Stan menu Nano | f[28] |
|----------------|-------|
| Manual + Zima | 0x19 |
| Harmonogram + Zima | 0x05 |
| Urlop + Zima | 0x05 (jak Harmonogram) |
| Manual + Chłodzenie | 0x01 |
| Harmonogram + Chłodzenie | (do potwierdzenia) |

Wcześniejsza interpretacja `Vent Urlop = 0x18, Vent Harm = 0x19` w PROTOCOL.md była niedokładna.

### E3(29) src=0x44 f[27] — sezon (uściślone 2026-04-25)

E3 ma własne mapowanie sezonu (różne od E4 i E5):

| Sezon | E4 f[27] | E5 f[27] | E3 f[27] |
|-------|---------|---------|---------|
| Zima | 0x02 (Manual) / 0x00 (Harm) | 0x00 | **0x01** |
| Lato bez | 0x0A | 0x0A | **0x09** |
| Chłodzenie | 0x12 | 0x14 | **0x11** |

E3: bit 0 (`0x01`) zawsze SET, bity 3-4 = sezon (0x08 lato, 0x10 chłodz). Tryb termostatu **nie** wpływa na E3 f[27].

### E3(29) src=0x44 f[28] — bieg + stable flag

Aktualna obserwacja: f[28] = bieg | 0x10 (znacznik) | 0x40 (stable config — jak w E4)

| Stan | f[28] |
|------|-------|
| B1 + Manual + Zima | 0x53 (0x03 \| 0x10 \| 0x40) |
| B1 + Harmonogram/Urlop | 0x13 (0x03 \| 0x10) |
| B1 + Lato/Chłodz + Manual | 0x13 (mimo Manual, bo Lato/Chłodz = unsynced) |

### Programy trybu pracy — kodowanie w E4(29)

Nano oferuje 3 programy użytkownika (TRYB PRACY): 🕐 Normal/Harmonogram, 🏠🚶 Poza Domem, 🧳 Urlop. Z punktu widzenia protokołu:

| Program | f[5] | f[28] | Interpretacja |
|---------|------|-------|---------------|
| 🕐 Normal/Harmonogram | `0x44` | `0x03` | bit 2 (`0x04`) w f[5] = harmonogram aktywny |
| 🏠🚶 Poza Domem | `0x44` | `0x03` | **identyczne jak Normal** — tylko lokalny override Nano |
| 🧳 Urlop | `0x40` | `0x02` | bit 2 w f[5] WYŁĄCZONY + specjalny kod biegu `0x02` |

**POZA DOMEM nie jest widoczny w protokole** — Nano aplikuje setpoint "Poza Domem" lokalnie w ramach harmonogramu, ramki C14 wyglądają identycznie jak w Normal.

**URLOP to właściwa zmiana protokołu:**
- `f[5]` bit 2 wyłączony (`0x40`) — slave'om przekazane "harmonogram nieaktywny"
- `f[28] = 0x02` — wartość poza tabelą biegów (bit 0 "validity" = 0) — kod "zatrzymaj komendę biegu"
- AERO ignoruje harmonogram i utrzymuje setpoint z E5(29) f[16-17]

**Setpoint współdzielony:** Menu serwisowe Nano ma jedną nastawę "Poza Domem" (np. 20°C) używaną dla OBU programów. Różnica jest w zachowaniu: Poza Domem respektuje harmonogram, Urlop go wyłącza.

---

## Ramka E3(29) src=0x44 — QUERY (TRIGGER AERO!)

**Najważniejsza ramka** — bez niej AERO nie odpowiada. Po wysłaniu tej ramki, AERO odpowiada E4(63) w ~400ms.

Zawiera nastawy % nawiewu/wywiewu per bieg (8 wartości).

```
E3,44,[cks],29,32,00,05,0A,28,1C,2A,1E,01,17,[WIET_WYW],[WIET_NAW],18,14,00,[B1_WYW],[B2_WYW],[B3_WYW],[B1_NAW],[B2_NAW],[B3_NAW],20,01,[BIEG+10h],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE3` | ID ramki | KNOWN |
| f[1] | `0x44` | marker typu (query) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x29` | subtyp | KNOWN |
| f[4] | `0x32` | stałe (=50) | UNKNOWN |
| f[5] | `0x00` | stałe | UNKNOWN |
| f[6] | `0x05` | stałe | UNKNOWN |
| f[7] | `0x0A` | stałe (=10) | UNKNOWN |
| f[8] | `0x28` | stałe (=40) | UNKNOWN |
| f[9] | `0x1C` | stałe (=28) | UNKNOWN |
| f[10] | `0x2A` | stałe (=42) | UNKNOWN |
| f[11] | `0x1E` | stałe (=30) | UNKNOWN |
| f[12] | `0x01` | stałe | UNKNOWN |
| f[13] | `0x17` | stałe (=23) | UNKNOWN |
| f[14] | `0x5F`=95 | **Wietrzenie wywiew %** | KNOWN |
| f[15] | `0x64`=100 | **Wietrzenie nawiew %** | KNOWN |
| f[16] | `0x18` | stałe (=24) | UNKNOWN |
| f[17] | `0x14` | stałe (=20) | UNKNOWN |
| f[18] | `0x00` | stałe | UNKNOWN |
| f[19] | `0x24` | stałe (=36) | UNKNOWN |
| f[20] | `0x20`=32 | **B1 wywiew %** | KNOWN |
| f[21] | `0x28`=40 | **B2 wywiew %** | KNOWN |
| f[22] | `0x46`=70 | **B3 wywiew %** | KNOWN |
| f[23] | `0x25`=37 | **B1 nawiew %** | KNOWN |
| f[24] | `0x2D`=45 | **B2 nawiew %** | KNOWN |
| f[25] | `0x4B`=75 | **B3 nawiew %** | KNOWN |
| f[26] | `0x20` | stałe | UNKNOWN |
| f[27] | `0x01` | stałe | UNKNOWN |
| f[28] | `0x11-0x17` | **Znacznik biegu** = `E4 f[28] + 0x10` (manual B1 → `0x13`, Stop → `0x11`) | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

---


## Ramka E4(63) — ODPOWIEDŹ AERO (src=0x21)

**Jedyna ramka nadawana przez AERO.** Odpowiedź na trigger E3(29) src=0x44, przychodzi w ~400ms po triggerze.

```
E4,21,[cks],63,09,74,00,3C,00,00,[CZ_H],[CZ_L],[CZ_H],[CZ_L],[NW_H],[NW_L],[WT_H],[WT_L],[WY_H],[WY_L],7E,00,00,00,[N%],[W%],[BG],02,[BP],23
```

### Pełna tabela bajtów (30B)

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE4` | ID ramki | KNOWN |
| f[1] | `0x21` | marker (odpowiedź AERO) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x63` | subtyp (odpowiedź AERO) | KNOWN |
| f[4] | `0x09` | stałe (header) | UNKNOWN |
| f[5] | `0x74` | stałe (header) | UNKNOWN |
| f[6] | `0x00` | stałe | UNKNOWN |
| f[7] | `0x3C` | stałe (header) | UNKNOWN |
| f[8-9] | `0x00,0x00` | stałe | UNKNOWN |
| f[10-11] | HH,LL | **T1 CZERP** (T.ZEWN) | KNOWN |
| f[12-13] | HH,LL | Duplikat CZERP (zawsze = f[10-11]) | KNOWN |
| f[14-15] | HH,LL | **T2 NAWIEW** | KNOWN |
| f[16-17] | HH,LL | **T4 WYRZUT** | KNOWN |
| f[18-19] | HH,LL | **T3 WYWIEW** | KNOWN |
| f[20] | `0x7E` | stałe filler | UNKNOWN |
| f[21-23] | `0x00,0x00,0x00` | stałe zera | UNKNOWN |
| f[24] | 0-100 | **Nawiew % aktualny** | KNOWN |
| f[25] | 0-100 | **Wywiew % aktualny** | KNOWN |
| f[26] | 0-4 | **Bieg:** 0=Stop, 1=B1, 2=B2, 3=B3, 4=Wietrzenie | KNOWN |
| f[27] | `0x02` | stałe (rola?) | UNKNOWN |
| f[28] | `0x40/0x60` | **Bypass bit 5:** 0x40=zamknięty, 0x60=otwarty (maska `& 0x20`) | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

---


## Ramka E5(29) — SETPOINTY + bypass + sezon (src=0x21)

Nano → magistrala. 5 setpointów temperatury, bypass enum, sezon enum.

```
E5,21,[cks],29,00,00,[CZ_H],[CZ_L],[CMF_H],[CMF_L],[ECO_H],[ECO_L],[CHL_H],[CHL_L],[RCZ_H],[RCZ_L],[POZ_H],[POZ_L],00,30,7E,00,7E,00,00,[BP],00,[SEZ],[UI],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE5` | ID ramki | KNOWN |
| f[1] | `0x21` | marker typu (komenda master) | KNOWN |
| f[2] | zmienne | checksum (K=0x23) | KNOWN |
| f[3] | `0x29` | subtyp (master id=1) | KNOWN |
| f[4] | `0x00` | stałe zero | UNKNOWN (filler?) |
| f[5] | `0x00` | stałe zero | UNKNOWN (filler?) |
| f[6-7] | HH,LL | **T.Czerpnia** (kopia z AERO E4(63), NIE sensor pokojowy) | KNOWN |
| f[8-9] | HH,LL | **Comfort** setpoint | KNOWN |
| f[10-11] | HH,LL | **Eco zima** setpoint (aktywny gdy sezon=Zima) | KNOWN |
| f[12-13] | HH,LL | **Eco lato/chłodzenie** setpoint (aktywny gdy sezon=Lato/Chłodz) | KNOWN |
| f[14-15] | HH,LL | **Manual / Zadana ręczna** setpoint | KNOWN |
| f[16-17] | HH,LL | **Poza domem** setpoint (Urlop+Zima, Poza domem) | KNOWN |
| f[18] | `0x00` | stałe | UNKNOWN |
| f[19] | `0x30` | stałe (niezależne od lato/zima/chłodz) | UNKNOWN |
| f[20] | `0x7E` | stałe (filler) | UNKNOWN |
| f[21] | `0x00` | stałe | UNKNOWN |
| f[22] | `0x7E` | stałe (filler) | UNKNOWN |
| f[23] | `0x00` | stałe | UNKNOWN |
| f[24] | `0x00` | stałe | UNKNOWN |
| f[25] | `0x60/0x61/0x62` | **Bypass enum** (patrz niżej) | KNOWN |
| f[26] | `0x00` normalnie / `0x50` gdy slave aktywny | **Slave ACK flag** (hipoteza — obserwacja 2026-04-23 po aktywacji ESP slave na busie) | PARTIAL |
| f[27] | `0x00/0x0A/0x14` | **Sezon enum** (patrz niżej) | KNOWN |
| f[28] | `0x00-0x1F` | **Kod UI Nano** (stan ekranu — złożony enum) | PARTIAL |
| f[29] | `0x23` | terminator | KNOWN |

### Bypass (f[25]) — 3-stanowy enum
| Kod | Stan | AERO reakcja |
|-----|------|--------------|
| `0x60` | Manual OFF | Zamyka natychmiast (f[28] E4(63) = 0x40) |
| `0x61` | AUTO | Decyduje autonomicznie po temp (autonomous mode) |
| `0x62` | Manual ON | Otwiera natychmiast (f[28] E4(63) = 0x60) |

**Ambiguity w odpowiedzi AERO:** AERO E4(63) f[28] pokazuje **stan fizyczny** (`0x40` zamknięty / `0x60` otwarty), nie komendę. Gdy komenda = AUTO, a AERO zdecyduje "zamknij" — ramka AERO wygląda **identycznie** jak przy manual OFF. Żeby rozróżnić tryb wysłany, trzymaj stan komendy po stronie mastera (np. `g_bypass_cmd` w esp02.yaml), nie próbuj wywnioskować z odpowiedzi AERO.

### Sezon (f[27]) — 3-stanowy enum
| Kod | Sezon |
|-----|-------|
| `0x00` | Zima ogrzewanie |
| `0x0A` | Lato bez ogrzewania/chłodzenia |
| `0x14` | Chłodzenie aktywne |

### UI code (f[28]) — PARTIAL (złożony)
Obserwowane wartości (niejednolite, zależy od ścieżki nawigacji w Nano):

| Stan Nano | f[28] |
|-----------|-------|
| Manual Stop | `0x00` |
| Manual B1 | `0x01` |
| Manual B3 | `0x03` |
| Manual B2 (z pewnej ścieżki menu) | `0x16` |
| Po edycji Eco | `0x05` |
| Vent Urlop | `0x18` |
| Vent Harm | `0x19` |

**Nie jest to czysty enum biegu** — raczej kod stanu UI/ekranu Nano dla slaves. Dla ESP-mastera nie krytyczny (AERO tego nie używa).

---


### F0(29) src=0x44 — heartbeat
Prawie puste: `F0,44,4E,29,7E×25,23`.


### 81(29) src=0x44 — heartbeat Nano
Prawie puste: `81,44,5F,29,7E×25,23`.


### D0/D1/D2(29) src=0x44 — slave config (identyczne payload)
```
D0/D1/D2,44,[cks],29,53,4B,41,07,68,07,04,00,6E,00,5A,7E×14,23
```
- `f[4-6]` = `0x53,0x4B,0x41` = **ASCII "SKA"** — prawdopodobnie model/vendor string COMPIT (znaczenie nieznane — być może "SKALAR" lub kod rodziny sterowników)
- `f[7-14]` = stałe dane config (rola nieznana — prawdopodobnie slot/adres slave'ów w konfiguracji AERO)
- Różni się tylko `f[0]` (D0/D1/D2) i `f[2]` (cksum)


---

## Pozostałe ramki w cyklu (broadcasty/slots)

### E3(29) src=0x56 — iNEXT slot
Same zera, `f[4-28]=0x00`. Rezerwacja miejsca dla iNEXT display.

---


### E2(29) src=0x44 — status broadcast
Niemal stałe bajty (`f[4]=0x4D`, `f[8]=0x03`, reszta `0x7E`/zera). Rola nieznana.


## Zachowanie urządzeń slave

### Ramka E4(29) src=0x2A — master config push do slave id=2

Obserwacja 2026-04-23: ~16s po power-on Nano slave id=2, Nano master **jednorazowo** wysyła ramkę typu E4(29) z `src=0x2A` zamiast zwykłego `src=0x21` — na pozycji #1 cyklu Master Full.

```
E4,2A,[cks],29,0D,01,05,28,1C,2A,00,1E,01,17,5F,64,18,14,00,24,20,28,46,25,2D,4B,20,01,[BIEG],23
```

Charakterystyczne:
- **f[1] = 0x2A** — adresowanie do konkretnego slave id=2 (normalnie ramki mastera mają `f[1]=0x21`)
- f[3] = 0x29 (master-side subtype)
- f[4-13] = `0D,01,05,28,1C,2A,00,1E,01,17` — **stałe** między power cycles, NIE zawiera daty
- Od f[14] do f[27] — identyczne jak w E3(29)_44 query (% per bieg, rotator)
- f[28] — kod biegu slave (`0x53` gdy harmonogram B1, `0x13` gdy manual B1)

**Rola:** master pushuje konfigurację do slave'a (ID-specific broadcast). Slave po tym wydarzeniu aktualizuje encoding w swoich E4(2A):
- f[28] zmienia się z `0x43` (stare B1) na `0x03` (nowe B1, zgodne z trybem master)
- Rotator zresetowany

**Timing:** ~16s po power-on Nano slave (dokładnie co 15.5-16s z 2 obserwacji).

**Data NIE jest w tej ramce** — weryfikowane testem kontrolnym 2026-04-23 (zmiana daty na Nano master przed power cycle slave, porównanie dwóch kolejnych E4(29) src=0x2A: bajty f[4-13] bez zmian mimo różnej daty masters). Data/godzina nie jest w ogóle transmitowana przez C14 — zarówno master jak i slave trzymają własny RTC.

---

### Ramka 80(29) src=0x44 — slave boot announcement

Gdy Nano w trybie slave (id ≠ 1) startuje (power-on), nadaje **jeden raz** ramkę typu 0x80:

```
80,44,[cks],2A,7E×26,23
```

- f[0] = 0x80 (nowy typ, para do 0x81 = master heartbeat)
- f[2] = 0x5F (taka sama cksum jak 81(29) — sugeruje wspólną rodzinę heartbeat)
- f[3] = 0x2A (slave id=2)
- payload = 0x7E fill (puste, tylko sygnalizacja)

**Obserwacja 2026-04-22:** po power-cycle Nano slave wysłał 80(2A) **jednorazowo** ~3-5s po starcie. Po tej ramce Nano zmienił encoding E4(2A):
- f[23-24] z `14,64` → `14,32` (coś typu limit % fan)
- Rotator f[25-26] zresetowany do `00,00`
- f[28] z `0x43` (stare B1) → `0x03` (nowe B1, zgodnie z naszym ESP master)

**Timing w cyklu master (potwierdzone 3 obserwacjami — pozycja LOSOWA):**

| # | Data | Pozycja w cyklu master |
|---|------|------------------------|
| 1 | 2026-04-22 22:45:12 | Między #5 (E5) a #6 (F0) |
| 2 | 2026-04-23 22:04:04 | Między #27 (AC src=56) a #1 nowego cyklu |
| 3 | 2026-04-23 22:05:42 | Między #10 (D2) a #11 (D3) |

**Potwierdzone:** 80(2A) pojawia się w **losowej pozycji cyklu master**, zależnej od timing startu Nano slave. Slave wysyła ramkę gdy tylko zakończy własną inicjalizację (~3-5s po power-on), korzystając z pierwszej dostępnej luki na magistrali (bus arbitration między ramkami master).

**Hipoteza:** 80(2A) to "slave ready announcement" — Nano informuje że jest po boot. Komunikat Nano slave UI "DATĘ I CZAS USTAWIA NANO NR 1" sugeruje że po tym może być oczekiwana odpowiedź od mastera z sync — **weryfikowane 2026-04-23**: master wysyła wtedy ramkę `E4(29) src=0x2A` (config push) ale bez daty.

---

### Nano jako slave (id ≠ 1) — PER-ID WAKE-UP ☆

**Odkryte 2026-04-24 (sweep id=2..6):** każde id slave'a ma **dedykowaną ramkę wake-up** w cyklu Master Full. Slave nasłuchuje WYŁĄCZNIE swojego wake-up'a i IGNORUJE wake-up'y innych slave'ów. To rozwiązuje problem kolizji — wiele slave'ów na jednej magistrali nie musi się między sobą synchronizować.

**Wzór:** `wake-up f[0] = 0xA8 + id`, f[1]=0x44, f[2]=0x06+id, f[3]=0x29, payload=0x7E×26.

| id | Wake-up ramka | Slave f[3] | Status (nasz master) |
|----|---------------|-----------|----------------------|
| 2  | `AA,44,08,29,...` (#22) | 0x2A | ✓ obecne w cyklu |
| 3  | `AB,44,09,29,...` (#24) | 0x2B | ✓ obecne w cyklu |
| 4  | `AC,44,0A,29,...` (#26) | 0x2C | ✓ obecne w cyklu |
| 5  | `AD,44,0B,29,...`       | 0x2D | ✗ TODO (generować) |
| 6  | `AE,44,0C,29,...`       | 0x2E | ✗ TODO |
| ... | ... | ... | ... |
| 20 | `BC,44,1A,29,...`       | 0x3C | ✗ TODO |

**Dowody empiryczne (2026-04-24 22:17-23:18):**
- Nano z id=3 odpowiadało ~280ms po #24_AB,44 — IGNOROWAŁO #22_AA,44 i #26_AC,44
- Nano z id=4 odpowiadało ~280ms po #26_AC,44 — IGNOROWAŁO AA i AB
- Nano z id=5 lub id=6 **milczało cyklicznie** (brak wake-up AD/AE w naszym masterze), mimo że wysyłało 80 boot po power-on
- Po dodaniu wake-up AD,44,0B,29 master będzie mógł obsłużyć slave id=5 i wyżej

**Druga forma wake-up src=0x56** (ramki #23/#25/#27): `AA/AB/AC,56,4C/4D/4E,29,0x00×26`
- Inny payload (0x00 zamiast 0x7E), inny CRC (K=0x23 zamiast K=0x93)
- Rola niejasna — być może kanał dla rozszerzeń iNEXT/EX4 (inne typy urządzeń)

**Wzór CRC wake-up:**
- src=0x44: `f[2] = (f[0]+f[1]+f[3]+25×0x7E + 0x93) & 0xFF = 0x06+id`
- src=0x56: `f[2] = (f[0]+f[1]+f[3]+25×0x00 + 0x23) & 0xFF = 0x4A+id`

### Ramka 80(29) src=0x44 — boot announcement (uzupełnienie)

**Potwierdzone dla wielu id (2026-04-24):**
- Nano slave po power-on wysyła `80(2X)` dla dowolnego id 2-20, gdzie f[3]=0x28+id
- CRC: `f[2] = 0x5F + (id-2)` (0x5F dla id=2, 0x62 dla id=5, 0x63 dla id=6)
- Nawet jeśli master nie ma wake-up'a dla tego id — 80 boot leci **bezwarunkowo**
- ESP master wykrywa 80(2X) i wysyła config push `E4(29) src=0x2X` w nast. cyklu #1 — ale to **nie wystarcza** do pełnego "sparowania" slave'a (f[28] pozostaje 0x03 bez flagi sync 0x40)

### Stany Nano slave w E4(2X) src=21 — synced vs unsynced

**Obserwowane 2 wyraźne stany Nano slave (w f[24] i f[28]):**

| Stan | f[24] | f[28] | Kontekst |
|------|-------|-------|----------|
| **NORMALNY (synced)** | 0x64 (100%) | 0x43 (`0x40\|0x03` = sync flag + B1) | Nano slave w długiej, stabilnej pracy z prawdziwym Nano masterem |
| **AWARYJNY (unsynced)** | 0x32 (50%) | 0x03 (sam B1, brak flagi 0x40) | Po naszych eksperymentach z ESP master, po kilku zmianach id w menu, po długim braku komunikacji z masterem |

**f[7] również się zmienia:**
- `0x02` w starszych sesjach (możliwe normal mode)
- `0x03` w nowszych sesjach (po naszych zabawach — może liczba urządzeń w EEPROM)

**Co prawdopodobnie wywołuje przejście NORMAL → AWARYJNY:**
1. Wewnętrzny watchdog Nano slave po wykryciu nieprawidłowości
2. Brak konkretnej ramki od mastera w cyklu (np. niepełny D0-D5, brakuje E5 setpointów)
3. Niezgodność w E4(29) src=0x2X (config push) — slave porównuje z własnym EEPROM i wykrywa nieprawidłowość
4. Długi czas bez triggera AERO (slave widzi "system się sypie")

**Co przywraca AWARYJNY → NORMAL:**
- Power-cycle slave + obecność prawdziwego Nano mastera + AERO (potwierdzono empirycznie)
- Naszego ESP master config push E4(29) src=0x2A **nie wystarcza** (mimo że ramka 1:1 z Nano)
- Może dodatkowo wymaga: rotator f[25-26] zsynchronizowany z masterem, konkretna sekwencja po 80 boot, albo specjalna treść D0-D5

**Niewiadome bajty w E4(29) src=21 (master broadcast / slave response):**

```
E4,21,CRC,29|2X, [4]?,[5]?,[6]?,[7]?,
                 [8]godz,[9]min,[10]7E,[11]?,
                 [12-13]Tpokoj,[14-15]Tset,
                 [16-22]7E×7 fill,
                 [23]?,[24]mocy?,[25-26]rotator,[27]?,[28]flag|bieg,[29]23
```

Do zbadania: które konkretnie z `f[4]`, `f[5]`, `f[6]`, `f[11]`, `f[23]`, `f[27]` są krytyczne dla utrzymania synced.

**Hipoteza: rotator f[25-26] może wymagać sync z masterem.**
- Master rotuje przez wartości w E4(29) src=21 (np. `01,14`/`02,01`/`03,02` cyklicznie)
- Slave może echować to samo (lub kontrowariantne) — jeśli slave nie nadąża, master wykrywa desync
- Nasz VS wysyła stałe `02,01` (lub przed-flaszem `01,14`) — może to wywołuje awaryjny

**Obserwacja praktyczna z config push:** ramka E4(29) src=0x2A (`E4,2A,43,29,0D,01,05,28,1C,2A,00,1E,01,17,5F,64,18,14,00,24,20,28,46,25,2D,4B,20,01,53,23`) zawiera **całkowicie inny payload** niż E4(29) src=21:

| f[i] | E4(29) src=21 (broadcast) | E4(29) src=0x2X (config push) |
|------|---------------------------|-------------------------------|
| 4 | 0x0A | **0x0D** (różne!) |
| 5 | 0x40 | **0x01** |
| 6 | 0x00 | **0x05** |
| 7 | 0x03 | **0x28** |
| 8-9 | zegar | **0x1C, 0x2A** |
| 10-11 | 0x7E,0x00 | **0x00, 0x1E** |
| 12-13 | T pokoj | **0x01, 0x17** |
| 14-15 | T setpoint | **0x5F, 0x64** |
| 16 | 0x7E fill | **0x18** |
| ... | większość 0x7E | **wypełnione różnymi danymi** |
| 24 | 0x64 (mocy) | **0x4B** |
| 25 | rotator | **0x20** |
| 28 | flag\|bieg | **0x53** |

Czyli config push to **zupełnie inny zestaw danych** — to konfiguracja systemu (sezon, harmonogram, setpointy globalne, kalibracja AERO). Slave ma to "absorbować" do swojego EEPROM.

### Nano slave — czas i RTC

Nano slave **NIE synchronizuje zegara z magistrali**. Mimo że master wysyła poprawny czas w E4(29) f[4-9], Nano slave używa własnego RTC (widoczny drift między sesjami power-cycle). W menu Nano slave komunikat "godzinę ustawia Nano 1" — Nano id=1 ma autorytet czasu, ale mechanizm sync przez C14 nie jest aktywny w obserwowanym firmware.
!! Synchronizuje, tylko jeszcze nie wiemy jak !!

### Nano slave — kod biegu w E4(2A)

Nano slave wysyła w E4(2A) `f[28] = 0x43` (stare encoding B1) niezależnie od aktualnego biegu masters. To jest wartość zapamiętana z sesji gdy Nano był masterem — slave nie komenderuje biegami, nawet jeśli `f[28]` zawiera "komendę". AERO interpretuje komendy **tylko z ramki E4(29) src=0x21 z `f[3] = 0x29`** (master id=1).

---

## Otwarte pytania (do zbadania)

1. **E5(29) f[18-19]** (`00,30` stałe) — przełączanie lato/zima/chłodzenie **nie** zmienia tego pola. Może maska konfiguracji lub parametr którego nie testowaliśmy.
2. **E4(29) f[5]** — nie stałe! `0x44` w Normal/Harmonogram/Poza Domem, `0x40` w URLOP. Bit 2 = "harmonogram aktywny" flag.
3. **E4(29) f[24]** (wariabilne `0x32`/`0x64`/`0x00`) — nie widać prostego wzoru. Może związane z setpoint delta lub PID.
4. **E4(29) f[25-26] rotator** — c=3 wariacje (`0x0E`/`0x0F`/`0x13`) zależnie od trybu.
5. **E5(29) f[28]** — pełny enum kodów UI (obserwowane niejednolite wartości).
6. **Format E2, D0-D2** — wartości w polach "stałych" mogą się zmieniać przy edge case'ach.
7. **Cold-start Nano** — czy istnieje sekwencja handshake? ESP-master jej nie robi i działa, ale być może AERO startuje w trybie "trusted".
8. ~~Która konkretna ramka w Master Full triggeruje Nano slave?~~ **ROZSTRZYGNIĘTE 2026-04-24:** per-id wake-up `0xA8+id, 0x44, 0x06+id, 0x29, ...`. Każde id słucha wyłącznie swojej ramki.
9. **Co dokładnie przełącza slave w stan "synced" (f[28] bit 0x40)?** Nasz ESP master wysyła wake-up + config push E4(29) src=0x2X, ale slave dalej w trybie unsynced (f[28]=0x03, f[24]=0x32). Brakuje prawdopodobnie specyficznej sekwencji handshake (może per-id D0/D1 albo ramki typu E4(29) src=0x2X z konkretnym polem "accept"?).
10. **Rola src=0x56 wake-up'ów (AA/AB/AC,56)** — inny kanał niż src=0x44, inny CRC (K=0x23), payload 0x00. Hipoteza: osobny bus dla EX4/iNEXT/rozszerzeń.
11. **f[7] w E4 od slave** (obecnie 0x03, wcześniej 0x02) — stałe w całej sesji niezależnie od id, zmienia się między sesjami gdy zmienimy coś w konfigu. Może model firmware, może "liczba urządzeń przekazana przez master w config", może tryb pracy Nano (regulator/termostat/kanałowy).
12. ~~**Co przełącza f[24]/f[28] w E4(29) master na synced (0x64/0x43)?**~~ **ROZSTRZYGNIĘTE 2026-04-25:** NIE komunikacja z slave'ami (VS wysyłające synced nie przywracają mastera). NIE komunikacja z AERO (master z AERO OK i f[5]=0x40 nadal ma f[24]=0x32). **f[24]/f[28] to stan menu Nano** (tryb mocy fan, harmonogram, sezon) zapisany w EEPROM — wymaga zmiany w menu UI mastera.
13. **Odkryte 2026-04-25: f[5] w E4(29) src=21 = flaga AERO_OK** (0x40=AERO odpowiada, 0x00=brak odp). Reaguje live (obserwowane przełączenie w trakcie testu).
14. **Jak Nano master dodaje slave do listy wake-up'ów?** 80 boot NIE wystarcza (empirycznie potwierdzone). Prawdopodobnie rejestracja przez menu UI mastera.
15. ~~Topologia bus = single multi-drop, TX z ESP fizycznie dociera do AERO → VS zakłócają AERO.~~ **ERRATUM 2026-04-25:** hipoteza błędna, rzeczywistą przyczyną "zakłócania" była luźna masa RS-485. Po naprawie masy VS + AERO współistnieją bez problemu przy wszystkich 4 VS aktywnych + trigger E3(29)_44 do AERO.

---

## Źródła / wiarygodność

- Wszystkie powyższe ustalenia pochodzą z sniffu rzeczywistej magistrali (prod 2021):
  - AERO 3B V2 .52 (NR M15-04-01792)
  - Nano Color CTP (NR L17-02-02717)
  - Centrala: Prodmax 300
- Sniff przez ESP32 `esp02` w trybie bridge MITM (2x HW-0519 RS-485 na GPIO4/18 + GPIO16/17)
- Hipotezy weryfikowane przez zmiany stanu w Nano i obserwację różnic w ramkach
- Formuła temperatury C14 pochodzi z wątku elektroda.pl o SOLARCOMP 951 (ten sam protokół COMPIT)

**Nie jest to oficjalna dokumentacja COMPIT.** Protokół jest własnościowy, a ta dokumentacja może zawierać błędy lub różnić się dla innych wersji sterowników.

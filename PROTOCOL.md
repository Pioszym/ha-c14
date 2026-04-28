# Protokół C14 (COMPIT) — mapa ramek

Reverse engineering magistrali RS-485 między rekuperatorem **COMPIT AERO 3B** a panelem pokojowym **COMPIT Nano Color CTP**.

**Status:** częściowo rozszyfrowany, wystarczający do pełnego sterowania. Otwarte pytania niżej.

---

## 1. Hardware

**Magistrala:**
- RS-485, 9600 8N1
- Wszystkie ramki **30 bajtów** (f[0]..f[29]), f[29] = terminator `0x23`
- Padding: `0x7E` = puste pole

**Urządzenia w systemie:**
- **COMPIT AERO 3B** — rekuperator. Odpowiada wyłącznie na trigger `E3(29) src=0x44` ramką `E4(29) src=0x63`. Nie inicjuje żadnej komunikacji.
- **COMPIT Nano Color CTP** — panel pokojowy. Rola konfigurowalna w menu serwisowym:
  - **Master id=1** w 2 trybach: **Master Mini** (10 ramek/cykl ~8.5s) lub **Master Full** (27 ramek/cykl ~22s).
  - **Slave id=2..20** — odpowiada na dedykowany wake-up od mastera.

**Topologia testowa (ten projekt):**
- ESP32 `esp02` w trybie MITM bridge — 2× HW-0519 (auto-direction, 3.3V) na GPIO4/18 + GPIO16/17.
- ESP może występować jako master id=1, równolegle Nano jako slave id=2 (dual master setup zgodny z dokumentacją COMPIT: "jeden master, unikalne ID dla każdego urządzenia").

---

## 2. Cykle master

### Master Mini (10 ramek master + 1 AERO, ~8.5s)

Sekwencja: komenda biegu → trigger AERO → broadcasty.

| # | Ramka | Nadawca | Rola |
|---|-------|---------|------|
| 1 | E4(29) src=0x21 | Master | Komenda biegu + zegar |
| 2 | E3(29) src=0x44 | Master | **QUERY — trigger AERO** |
| — | E4(63) src=0x21 | **AERO** | Odpowiedź AERO (~400ms po #2) |
| 3 | E3(29) src=0x56 | Master | iNEXT slot (zera) |
| 4 | E2(29) src=0x44 | Master | Status broadcast |
| 5 | E5(29) src=0x21 | Master | Setpointy temperatur + bypass |
| 6 | F0(29) src=0x44 | Master | Heartbeat |
| 7 | 81(29) src=0x44 | Master | Heartbeat Master |
| 8 | D0(29) src=0x44 | Master | Slave config 1 |
| 9 | D1(29) src=0x44 | Master | Slave config 2 |
| 10 | D2(29) src=0x44 | Master | Slave config 3 |

W Mini Nano slave jest **cichy** — nie odpowiada na żadną ramkę. Aktywacja slave wymaga AA(29) src=0x44 z Master Full.

### Master Full (27 ramek master + 2 AERO + N×slave, ~22s)

Rozszerzona wersja Mini (TRYB W SIECI C14 = MASTER w menu serwisowym Nano). Dodaje 17 ramek enumeration/keepalive. **E3(29)_44 występuje DWA razy** — AERO odpowiada `E4(63)` dwukrotnie per cykl.

| # | Ramka | Nadawca | Rola |
|---|-------|---------|------|
| 1 | E4(29) src=0x21 | Master | Komenda biegu + zegar (lub jednorazowo E4(29) src=0x2A config push po boot slave) |
| 2 | E3(29) src=0x44 | Master | **QUERY #1 — trigger AERO** |
| — | E4(63) src=0x21 | **AERO** | Odpowiedź AERO #1 |
| 3 | E3(29) src=0x56 | Master | iNEXT slot |
| 4 | E2(29) src=0x44 | Master | Status broadcast |
| 5 | E5(29) src=0x21 | Master | Setpointy + bypass + sezon |
| 6 | F0(29) src=0x44 | Master | Heartbeat |
| 7 | 81(29) src=0x44 | Master | Heartbeat Master |
| 8-13 | D0..D5(29) src=0x44 | Master | Slave config 1..6 |
| 14 | E3(29) src=0x44 | Master | **QUERY #2 — drugi trigger** (identyczne jak #2) |
| — | E4(63) src=0x21 | **AERO** | Odpowiedź AERO #2 |
| 15 | 8B(29) src=0x44 | Master | Heartbeat 0x8B |
| 16 | 9F(29) src=0x44 | Master | Heartbeat 0x9F |
| 17 | 82(29) src=0x44 | Master | Heartbeat 0x82 |
| 18-21 | 8C/8D/8E/95(29) src=0x44 | Master | Heartbeats |
| 22 | AA(29) src=0x44 | Master | **Wake-up dla slave id=2** |
| — | E4(29) src=0x21 f[3]=0x2A | **Slave id=2** | Odpowiedź slave id=2 (~280ms po #22) |
| 23 | AA(29) src=0x56 | Master | iNEXT slot dla id=2 |
| 24 | AB(29) src=0x44 | Master | **Wake-up dla slave id=3** |
| — | E4(29) src=0x21 f[3]=0x2B | **Slave id=3** | Odpowiedź slave id=3 |
| 25 | AB(29) src=0x56 | Master | iNEXT slot dla id=3 |
| 26 | AC(29) src=0x44 | Master | **Wake-up dla slave id=4** |
| — | E4(29) src=0x21 f[3]=0x2C | **Slave id=4** | Odpowiedź slave id=4 |
| 27 | AC(29) src=0x56 | Master | iNEXT slot dla id=4 |

**Wake-upy dla id ≥ 5:** wzór protokołu (`f[0]=0xA8+id`) sugeruje rozszerzenie do `BC` (id=20) — protokół teoretycznie obsługuje 19 slave'ów (id 2..20, master zawsze 1). W obserwowanym Nano master wake-upy dla id ≥ 5 **nie zostały zaobserwowane**. W menu serwisowym Nano nie ma ustawienia "lista slave'ów" — master ustala "kogo budzić" prawdopodobnie auto-detect z bus traffic (kryterium nieznane), albo Master Full ma stałą długość = 3 slave'ów (id=2-4).

**Zdarzenia asynchroniczne (poza cyklem master):**

| Kiedy | Ramka | Nadawca | Rola |
|-------|-------|---------|------|
| Po power-on slave (1×, ~3-5s, **losowa pozycja w cyklu** — bus arbitration) | 80(29) src=0x44 f[3]=0x2X | Slave | Slave boot announcement (`80,44,5F,2X,7E×26,23`) |
| ~16s po boot slave (1× w najbliższym cyklu master) | E4(29) src=0x2X | Master | Config push do slave id=X — zastępuje pozycję #1 cyklu |

**17 ramek dodatkowych** (#8-13 dla D3-D5, #14, #15-21, #22-27) ma zawartość statyczną (`0x7E` lub `0x00` fill). Mimo to Master Full jest **wymagany** żeby Nano w trybie slave zaczął aktywnie komunikować się — konkretnie **AA(29) src=0x44 (#22)** jest wake-up'em dla Nano slave id=2.

### Timing odpowiedzi AERO

| Czas | Zdarzenie |
|------|-----------|
| t+0.0s | Master wysyła E4(29) src=0x21 |
| t+0.8s | Master wysyła E3(29) src=0x44 (trigger) |
| t+1.2s | **AERO odpowiada E4(63)** (~400ms po triggerze) |
| t+1.6s+ | Reszta ramek mastera |

Dla ESP-mastera: po wysłaniu E3(29)_44 wystarczy slot **≥500ms** na nasłuch E4(63).

### Role poszczególnych ramek w cyklu

| Ramka | Rola |
|-------|------|
| **E4(29) src=0x21** | Komenda biegu + zegar + flagi trybów (master → bus). AERO reaguje mechanicznie (zmienia wentylator), NIE odpowiada |
| **E3(29) src=0x44** | **TRIGGER** dla odpowiedzi AERO. AERO odpowiada `E4(63)` ~400ms później. Zawiera nastawy % per bieg |
| **E4(63) src=0x21** | Jedyna ramka nadawana przez AERO. Pomiary T (czerpnia, nawiew, wyrzut, wywiew), aktualne %, bieg fizyczny, stan bypass |
| E3(29) src=0x56 | iNEXT slot (zera) — rezerwacja miejsca dla iNEXT display |
| E2(29) src=0x44 | Status broadcast — niemal stałe bajty, rola nieznana |
| **E5(29) src=0x21** | 5 setpointów temperatury, bypass enum, sezon enum, kod UI |
| F0(29) src=0x44 | Heartbeat (`0x7E` fill) |
| 81(29) src=0x44 | Heartbeat Master (`0x7E` fill) |
| D0-D5(29) src=0x44 | Slave config — identyczny payload (ASCII "SKA"), różni się tylko `f[0]`/cksum |
| 8B/9F/82/8C/8D/8E/95(29) src=0x44 | Heartbeats wypełniające cykl Master Full |
| **AA/AB/AC(29) src=0x44** | **Wake-up** dla slave id=2/3/4. Slave odpowiada `E4(29) src=0x21` w ~280ms |
| AA/AB/AC(29) src=0x56 | iNEXT slot dla id=2/3/4 — inny CRC i payload (`0x00`), rola niejasna |

Minimalna ramka triggerująca odpowiedź AERO:
```
E3,44,[cks],29,32,00,05,0A,28,1C,2A,1E,01,17,5F,64,18,14,00,24,20,28,46,25,2D,4B,20,01,53,23
```

---

## 3. Ramki — szczegółowe tabele bajtów

Ramki ułożone w kolejności występowania w cyklu Master Full. Sekcja 3.1 opisuje pola wspólne dla wszystkich ramek (`f[1]`, `f[2]`, `f[3]`, encoding temperatury).

### 3.1 Pola wspólne

#### f[1] — marker typu ramki

**UWAGA:** `f[1]` to marker typu, NIE adres źródłowy.

| f[1] | Znaczenie |
|------|-----------|
| `0x21` | Ramki sterujące (E4, E5, E4_63) |
| `0x44` | Broadcasty (D0-D5, E3, E2, F0, 81, AA-AC wake-up) |
| `0x56` | Slot iNEXT/EX4 |
| `0x63` | Tylko E4 od AERO (odpowiedź) |
| `0x2A`..`0x3C` | Config push do konkretnego slave id (`0x28+id`) |

#### f[2] — checksum

Formuła: `f[2] = (f[0] + f[1] + sum(f[3]..f[28]) + K) & 0xFF`

| K | Dotyczy ramek |
|---|---------------|
| `0xA3` | E4(29), E4(63), E5(29), E3(29), E2(29), F0(29), D0-D5(29), 81(29), 80(2X) — **wszystkie obserwowane src=0x44/0x21/0x63** |
| `0x93` | wake-up `AA/AB/AC,44` (`f[2] = 0x06+id`) |
| `0x23` | wake-up `AA/AB/AC,56` (`f[2] = 0x4A+id`) |

> Empirycznie zweryfikowane 2026-04-19. Wcześniejsza hipoteza (różne K dla różnych ramek głównych) była błędna.

#### f[3] — subtyp / master ID

**Wzór:** `f[3] = 0x28 + id` — gdzie `id` to numer sterownika w menu serwisowym Nano.

| ID | f[3] | Rola |
|----|------|------|
| 1 | `0x29` | **Master główny** — jedyny z pełną kontrolą biegów/bypass |
| 2 | `0x2A` | Slave (odp. na AA wake-up) |
| 3 | `0x2B` | Slave (odp. na AB wake-up) |
| 4 | `0x2C` | Slave (odp. na AC wake-up) |
| 5 | `0x2D` | Slave |
| ... | `0x28+id` | (do max ~20) |

Potwierdzone 2026-04-22: zmiana ID w menu Nano zmienia `f[3]` we wszystkich ramkach wysyłanych przez ten sterownik. Power-cycle nie zmienia ID (EEPROM). Tylko id=1 może sterować biegami — pozostałe ID nadają ramki bez komendy biegu (`f[28]=0x03` stale).

Konsekwencja: jeśli na magistrali nie ma żadnego urządzenia z id=1, AERO nie dostaje komendy biegu → wentylatory nie startują.

#### Enkoding temperatury

```
T = (H*128 + L%128 - 2000) / 10              # dekodowanie
val = T*10 + 2000; H = val/128; L = val%128  # kodowanie
```

Przykłady: `11,36` = 23.0°C · `11,40` = 24.0°C · `11,04` = 18.0°C · `10,66` = 15.0°C

---

### 3.2 E4(29) src=0x21 — KOMENDA biegu (cykl #1)

Najważniejsza ramka mastera. Komenda biegu + zegar + flagi trybów. AERO reaguje mechanicznie, ale **nie odpowiada** tą ramką. Slave kopiuje większość pól do swojej E4(2X).

```
E4,21,[cks],29,[F4],[F5],00,[DOW],[HH],[MM],7E,00,[TPK_H],[TPK_L],[SP_H],[SP_L],7E×7,14,[F24],[ROT_A],[ROT_B],[F27],[F28],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE4` | ID ramki | KNOWN |
| f[1] | `0x21` | marker (komenda master) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x29` | subtyp (master id=1) | KNOWN |
| f[4] | `0x0A` | stała Nano master (model? wersja?) | UNKNOWN |
| f[5] | `0x40/0x44` | Bit `0x04` = "Programy=Poza domem aktywne". Bit `0x40` = AERO_OK (set gdy AERO odpowiada). | KNOWN |
| f[6] | `0x00` | stałe | UNKNOWN |
| f[7] | 0-6 | **Day of week** (`0=Pn..6=Nd`) | KNOWN |
| f[8] | 0-23 | **Godzina** (decimal jako byte) | KNOWN |
| f[9] | 0-59 | **Minuta** (decimal jako byte) | KNOWN |
| f[10] | `0x7E` | filler (stały, możliwe że pole dla features niedostępnych w naszym setupie) | UNKNOWN |
| f[11] | `0x00` | stałe | UNKNOWN |
| f[12-13] | HH,LL | **Temp pokojowa Nano** (sensor wewn CTP + korekta termostatu z menu serwisowego, zakres -10..+10°C) | KNOWN |
| f[14-15] | HH,LL | **Aktywny setpoint** (śledzi tryb: Comfort/Eco/Manual/Poza domem) | KNOWN |
| f[16-22] | `0x7E` ×7 | filler | UNKNOWN |
| f[23] | `0x14` | stałe | UNKNOWN |
| f[24] | `0x32/0x64` | Tryb mocy: `0x64` = synced (Manual+Zima), `0x32` = unsynced/awaryjny. Paruje z f[28] bit 0x40. | KNOWN |
| f[25] | `0x00/0x01/0x02/0x03` | **Faza transmisji daty** (rotuje co cykl Master Full) | KNOWN |
| f[26] | wartość daty | zależnie od f[25]: 0x00 init, rok mod 100, miesiąc 1-12, dzień 1-31 | KNOWN |
| f[27] | bitfield | **tryb temp + sezon + wietrzenie** (patrz niżej) | KNOWN |
| f[28] | bitfield | **bieg + overlays** (patrz niżej) | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

**f[25-26] — 3-fazowa transmisja daty (master rotuje co cykl Master Full):**

| f[25] | f[26] |
|-------|-------|
| `0x00` | `0x00` (init) |
| `0x01` | rok mod 100 (np. `0x16`=22 → 2022) |
| `0x02` | miesiąc (1-12) |
| `0x03` | dzień miesiąca (1-31) |

Slave rekonstruuje pełną datę po 3 cyklach (~66s).

**f[27] — multi-field encoding:**

| Bity | Pole | Wartości |
|------|------|----------|
| 0-1 | Tryb termostatu | `0x00`=Harmonogram · `0x01`=Urlop · `0x02`=Manual |
| 3-4 | Sezon | `0x00`=Zima · `0x08`=Lato bez ogrzewania · `0x10`=Chłodzenie |
| 5 | Wietrzenie overlay | `+0x20` gdy ON |

Łączne: `f[27] = tryb_temp | sezon | wietrzenie_overlay`.

**f[28] — bieg + flagi:**

Bit 0 = validity, bity 1-2 = value biegu:

| Bieg | f[28] (bez overlays) |
|------|---------------------|
| Stop | `0x01` |
| B1 | `0x03` |
| B2 | `0x05` |
| B3 | `0x07` |

Overlays / specjalne wartości:
- `+0x08` (bit 3) = chłodzenie aktywne (B1+cool = `0x0B`)
- `+0x40` (bit 6) = flaga **"konfiguracja deterministyczna"**: SET ⇔ (Termostat=Manual) AND (korekta termostatu = 0). Paruje z `f[24]=0x64`. Każde naruszenie warunku (Term=Harm/Urlop lub korekta≠0) → bit CLEAR + `f[24]=0x32`
- `0x40` sam (validity=0, bieg=0) = **Programy=Urlop**

AERO reaguje mechanicznie tylko na bity 1-2. Bity `0x40` i `0x08` ignoruje — to flagi dla slaves.

**Wpływ menu Nano na f[28]:**

| Stan | f[28] |
|------|-------|
| Wentylacja=Stop/B1/B2/B3 (manual) | `bieg \| 0x40` jeśli Term=Manual, inaczej sam `bieg` |
| Wentylacja=Harmonogram | identyczne jak Manual+bieg_z_slotu (slave nie odróżni) |
| Wentylacja=Harm-Urlop | bieg z slotu, bez `0x40`, `f[24]=0x32` |
| Programy=Poza domem | bieg z slotu poza-domem (override) + `f[5]` bit `0x04` SET, setpoint=poza_domem |
| Programy=Urlop | `0x40`, setpoint=poza_domem |

Programy aktywne nadpisują Wentylacja menu.

### 3.3 E3(29) src=0x44 — QUERY / TRIGGER AERO (cykl #2 i #14)

Bez tej ramki AERO nie odpowiada. Po jej wysłaniu AERO odpowiada `E4(63)` w ~400ms. Zawiera nastawy % nawiewu/wywiewu per bieg.

```
E3,44,[cks],29,32,00,05,0A,28,1C,2A,1E,01,17,[WIET_WYW],[WIET_NAW],18,14,00,[B1_WYW],[B2_WYW],[B3_WYW],[B1_NAW],[B2_NAW],[B3_NAW],20,[F27],[F28],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE3` | ID ramki | KNOWN |
| f[1] | `0x44` | marker (query/broadcast) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x29` | subtyp | KNOWN |
| f[4-13] | `32,00,05,0A,28,1C,2A,1E,01,17` | stałe header (znaczenie nieznane) | UNKNOWN |
| f[14] | 0-100 | **Wietrzenie wywiew %** (np. `0x5F`=95) | KNOWN |
| f[15] | 0-100 | **Wietrzenie nawiew %** (np. `0x64`=100) | KNOWN |
| f[16-19] | `18,14,00,24` | stałe (znaczenie nieznane) | UNKNOWN |
| f[20] | 0-100 | **B1 wywiew %** | KNOWN |
| f[21] | 0-100 | **B2 wywiew %** | KNOWN |
| f[22] | 0-100 | **B3 wywiew %** | KNOWN |
| f[23] | 0-100 | **B1 nawiew %** | KNOWN |
| f[24] | 0-100 | **B2 nawiew %** | KNOWN |
| f[25] | 0-100 | **B3 nawiew %** | KNOWN |
| f[26] | `0x20` | stałe | UNKNOWN |
| f[27] | bitfield | **Sezon** (mapowanie inne niż E4!) | KNOWN |
| f[28] | bitfield | **bieg + znacznik 0x10 + stable flag 0x40** | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

**f[27] — sezon (E3 ma własne mapowanie, różne od E4 i E5):**

| Sezon | E3 f[27] |
|-------|----------|
| Zima | `0x01` |
| Lato bez ogrzewania | `0x09` |
| Chłodzenie | `0x11` |

Bit 0 (`0x01`) zawsze SET, bity 3-4 = sezon (`0x08` lato, `0x10` chłodz). Tryb termostatu **nie** wpływa na E3 f[27]. Bit 5 (`0x20`) = wietrzenie ON (jak E4).

**f[28] — bieg + flagi:** `f[28] = bieg | 0x10 (znacznik E3) | 0x40 (stable config)`

| Stan | f[28] |
|------|-------|
| B1 + Manual + Zima | `0x53` (`0x03` \| `0x10` \| `0x40`) |
| B1 + Harmonogram/Urlop | `0x13` (`0x03` \| `0x10`) — patrz uwaga niżej |
| B1 + Lato/Chłodz + Manual | `0x13` (Lato/Chłodz = unsynced) |

⚠️ **Bit `0x40` jest WYMAGANY do resync AERO** niezależnie od trybu termostatu. AERO toleruje `0x13` (bez `0x40`) tylko dopóki trzyma świeży sync od mastera. Po dłuższej ciszy lub utracie heartbeat-u AERO przechodzi w stan oczekujący ramkę z bitem `0x40` (deterministyczna konfiguracja); bez tego bitu pozostaje cichy mimo że master cyklicznie nadaje E4(29) i E3(29)_44. **Master powinien zawsze wysyłać `f[28] |= 0x40`**, niezależnie od stanu termostatu — patrz HISTORY 2026-04-28. Nano master tak właśnie robi (zawsze SET), my w ESP poprawiliśmy logikę tego dnia.

### 3.4 E4(63) src=0x21 — ODPOWIEDŹ AERO

Jedyna ramka nadawana przez AERO. Odpowiedź na trigger E3(29) src=0x44 (~400ms).

```
E4,21,[cks],63,09,74,00,3C,00,00,[CZ_H],[CZ_L],[CZ_H],[CZ_L],[NW_H],[NW_L],[WT_H],[WT_L],[WY_H],[WY_L],7E,00,00,00,[N%],[W%],[BG],02,[BP],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE4` | ID ramki | KNOWN |
| f[1] | `0x21` | marker (odpowiedź AERO) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x63` | subtyp (odpowiedź AERO) | KNOWN |
| f[4-9] | `09,74,00,3C,00,00` | stałe header | UNKNOWN |
| f[10-11] | HH,LL | **T1 CZERP** (T.ZEWN) | KNOWN |
| f[12-13] | HH,LL | Duplikat CZERP (zawsze = f[10-11]) | KNOWN |
| f[14-15] | HH,LL | **T2 NAWIEW** | KNOWN |
| f[16-17] | HH,LL | **T4 WYRZUT** | KNOWN |
| f[18-19] | HH,LL | **T3 WYWIEW** | KNOWN |
| f[20-23] | `7E,00,00,00` | stałe filler | UNKNOWN |
| f[24] | 0-100 | **Nawiew % aktualny** | KNOWN |
| f[25] | 0-100 | **Wywiew % aktualny** | KNOWN |
| f[26] | 0-4 | **Bieg:** 0=Stop, 1=B1, 2=B2, 3=B3, 4=Wietrzenie | KNOWN |
| f[27] | `0x00/0x02` | **Flaga "AERO pracuje"**: `0x00`=Stop (bieg=0), `0x02`=B1/B2/B3 (wentylator aktywny) | KNOWN |
| f[28] | `0x40/0x60` | **Bypass fizyczny:** `0x40`=zamknięty, `0x60`=otwarty (maska `& 0x20`) | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

**Ambiguity bypass:** AERO E4(63) f[28] pokazuje **stan fizyczny**, nie komendę. Gdy komenda = AUTO a AERO zdecyduje "zamknij" — ramka identyczna jak przy manual OFF. Żeby rozróżnić tryb wysłany, trzymaj stan komendy po stronie mastera (`g_bypass_cmd` w esp02.yaml), nie wnioskuj z odpowiedzi AERO.

### 3.5 E3(29) src=0x56 — iNEXT slot (cykl #3)

Same zera, `f[4-28]=0x00`. Rezerwacja miejsca dla iNEXT display.

### 3.6 E2(29) src=0x44 — status broadcast (cykl #4)

Niemal stałe bajty (`f[4]=0x4D`, `f[8]=0x03`, reszta `0x7E`/zera). Rola nieznana.

### 3.7 E5(29) src=0x21 — SETPOINTY + bypass + sezon (cykl #5)

5 setpointów temperatury, bypass enum, sezon enum.

```
E5,21,[cks],29,00,00,[CZ_H],[CZ_L],[CMF_H],[CMF_L],[ECZ_H],[ECZ_L],[ECL_H],[ECL_L],[RCZ_H],[RCZ_L],[POZ_H],[POZ_L],00,30,7E,00,7E,00,00,[BP],[F26],[SEZ],[UI],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE5` | ID ramki | KNOWN |
| f[1] | `0x21` | marker | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x29` | subtyp | KNOWN |
| f[4-5] | `0x00,0x00` | stałe filler | UNKNOWN |
| f[6-7] | HH,LL | **T.Czerpnia** (kopia z AERO E4(63), NIE sensor pokojowy) | KNOWN |
| f[8-9] | HH,LL | **Comfort** setpoint | KNOWN |
| f[10-11] | HH,LL | **Eco zima** setpoint (aktywny gdy sezon=Zima) | KNOWN |
| f[12-13] | HH,LL | **Eco chłodzenie** setpoint (aktywny gdy sezon=Lato/Chłodz) | KNOWN |
| f[14-15] | HH,LL | **Manual / zadana ręczna** setpoint | KNOWN |
| f[16-17] | HH,LL | **Poza domem** setpoint (Urlop+Zima, Poza domem) | KNOWN |
| f[18] | `0x00` | stałe | UNKNOWN |
| f[19] | `0x30` | stałe (niezależne od sezonu) | UNKNOWN |
| f[20] | `0x7E` | filler | UNKNOWN |
| f[21] | `0x00` | stałe | UNKNOWN |
| f[22] | `0x7E` | filler | UNKNOWN |
| f[23-24] | `0x00,0x00` | stałe | UNKNOWN |
| f[25] | `0x60/0x61/0x62` | **Bypass enum** | KNOWN |
| f[26] | `0x00` | stałe (hipoteza `0x50` gdy slave aktywny — niezweryfikowane, patrz §7) | UNKNOWN |
| f[27] | `0x00/0x0A/0x14` | **Sezon enum** | KNOWN |
| f[28] | `0x00-0x1F` | **Kod UI Nano** (stan ekranu — złożony enum) | PARTIAL |
| f[29] | `0x23` | terminator | KNOWN |

**f[25] — Bypass (3-stanowy enum):**

| Kod | Stan | AERO reakcja |
|-----|------|--------------|
| `0x60` | OFF | Zamyka natychmiast (E4(63) f[28] = `0x40`) |
| `0x61` | AUTO | Decyduje autonomicznie |
| `0x62` | ON | Otwiera natychmiast (E4(63) f[28] = `0x60`) |

**f[27] — Sezon (3-stanowy enum, mapowanie różne od E4 i E3):**

| Kod | Sezon |
|-----|-------|
| `0x00` | Zima ogrzewanie |
| `0x0A` | Lato bez ogrzewania |
| `0x14` | Chłodzenie |

**f[28] — Kod UI (PARTIAL, niejednolite, zależy od ścieżki nawigacji):**

| Stan menu Nano | f[28] |
|----------------|-------|
| Manual + Zima | `0x19` |
| Harmonogram + Zima | `0x05` |
| Urlop + Zima | `0x05` (jak Harmonogram) |
| Manual + Chłodzenie | `0x01` |
| Manual Stop | `0x00` |
| Manual B1 | `0x01` |
| Manual B3 | `0x03` |

Nie czysty enum biegu — kod stanu UI dla slaves. AERO go nie używa.

### 3.8 F0(29) src=0x44 — heartbeat (cykl #6)

Prawie puste: `F0,44,4E,29,7E×25,23`.

### 3.9 81(29) src=0x44 — heartbeat Nano master (cykl #7)

Prawie puste: `81,44,5F,29,7E×25,23`.

### 3.10 D0/D1/D2/D3/D4/D5(29) src=0x44 — config serwisowy (cykl #8-13)

Identyczny payload, różni się tylko `f[0]` i `f[2]` (cksum). D0-D2 obecne też w Master Mini, D3-D5 dodane w Master Full.

```
DX,44,[cks],29,[F4],[OSUSZ],[F6],[F7],[F8],[F9],[F10],00,[F12],00,[F14],7E×14,23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[4] | `0x53` (83) | stała (parametr config) | UNKNOWN |
| f[5] | 0-100 | **Start osuszania — przekroczona wilgotność %** (próg dla startu osuszania, menu serwisowe; `0x4B`=75%, `0x64`=100%, `0x32`=50%) | KNOWN |
| f[6] | 0-100 | **Stop osuszania %** (próg wilgotności do zatrzymania osuszania, linear dec; `0x41`=65%, `0x37`=55%) | KNOWN |
| f[7-8] | HH,LL | **Start wietrzenia CO2 ppm** (zakres 0-2000, encoding jak temperatura: `ppm = HH*128 + LL%128`, bez offsetu -2000; `07,68`=1000ppm, `07,31`=945ppm) | KNOWN |
| f[9-10] | HH,LL | **Stop wietrzenia CO2 ppm** (encoding jak f[7-8]; `07,04`=900ppm, `06,52`=850ppm) | KNOWN |
| f[11-12] | HH,LL | **Start wietrzenia VOC** (zakres 0-1000, encoding jak f[7-8]; `00,6E`=110) | KNOWN |
| f[13-14] | HH,LL | **Stop wietrzenia VOC** (encoding jak f[11-12]; `00,5A`=90) | KNOWN |
| f[15-28] | `0x7E` ×14 | filler | UNKNOWN |

D0-D5 broadcastowane do slaves zawierają parametry serwisowe rekuperatora (progi osuszania, CO2, VOC). `f[4]` (stałe `0x53`) prawdopodobnie też parametr z menu serwisowego — czeka na identyfikację.

### 3.11 8B/9F/82/8C/8D/8E/95(29) src=0x44 — heartbeats (cykl #15-21)

Wypełnienie cyklu Master Full. Statyczne `0x7E` fill, rola nieznana (prawdopodobnie keepalive dla rzadkich typów slave).

### 3.12 AA/AB/AC(29) src=0x44 — wake-up dla slave id=2/3/4 (cykl #22/24/26) ☆

Odkryte 2026-04-24 (sweep id=2..6): każde id slave'a ma **dedykowaną ramkę wake-up** w cyklu Master Full. Slave nasłuchuje WYŁĄCZNIE swojego wake-up'a i IGNORUJE wake-up'y innych slave'ów. To rozwiązuje problem kolizji — wiele slave'ów na jednej magistrali nie musi się między sobą synchronizować.

**Wzór:** `wake-up f[0] = 0xA8 + id`, f[1]=`0x44`, f[2]=`0x06+id`, f[3]=`0x29`, payload=`0x7E×26`.

| id | Wake-up ramka | Slave f[3] | Status (nasz master) |
|----|---------------|-----------|----------------------|
| 2  | `AA,44,08,29,7E×26,23` (#22) | `0x2A` | ✓ obecne |
| 3  | `AB,44,09,29,7E×26,23` (#24) | `0x2B` | ✓ obecne |
| 4  | `AC,44,0A,29,7E×26,23` (#26) | `0x2C` | ✓ obecne |
| 5  | `AD,44,0B,29,7E×26,23` | `0x2D` | ✗ TODO |
| 6  | `AE,44,0C,29,7E×26,23` | `0x2E` | ✗ TODO |
| ... | ... | ... | ... |
| 20 | `BC,44,1A,29,7E×26,23` | `0x3C` | ✗ TODO |

**Dowody empiryczne (2026-04-24 22:17-23:18):**
- Nano z id=3 odpowiadało ~280ms po #24_AB — IGNOROWAŁO #22_AA i #26_AC
- Nano z id=4 odpowiadało ~280ms po #26_AC — IGNOROWAŁO AA i AB
- Nano z id=5/6 milczało (brak wake-up AD/AE w naszym masterze), mimo że wysyłało 80 boot

### 3.13 E4(29) src=0x21 f[3]=0x2X — ODPOWIEDŹ SLAVE (po wake-up)

Slave nadaje tę ramkę ~280ms po swoim wake-up (`AA`/`AB`/`AC` src=0x44, §3.12). Format identyczny jak ramka master E4(29) src=0x21 (§3.2) — różnica tylko w `f[3]` (`0x2A`/`0x2B`/`0x2C` zamiast `0x29`) i w semantyce niektórych pól.

```
E4,21,[cks],2X,0A,40,00,[DOW],[HH],[MM],7E,00,[TPK_H],[TPK_L],[SP_H],[SP_L],7E×7,14,[F24],[ROT_A],[ROT_B],[F27],[F28],23
```

| Bajt | Wartość | Znaczenie | Status |
|------|---------|-----------|--------|
| f[0] | `0xE4` | ID ramki | KNOWN |
| f[1] | `0x21` | marker (jak master broadcast) | KNOWN |
| f[2] | zmienne | checksum (K=0xA3) | KNOWN |
| f[3] | `0x2A`/`0x2B`/`0x2C`/... | **Subtyp = `0x28+id`** (różni od mastera `0x29`) | KNOWN |
| f[4] | `0x0A` | stała (jak master) | UNKNOWN |
| f[5] | `0x40` | flaga AERO_OK kopiowana z mastera (slave nie modyfikuje) | KNOWN |
| f[6] | `0x00` | stałe | UNKNOWN |
| f[7] | `0x02` / `0x03` | Stałe w sesji, **zmienia się między sesjami** (`0x02` w starszych, `0x03` po eksperymentach z ESP master) — może liczba urządzeń w EEPROM lub tryb pracy Nano | PARTIAL |
| f[8] | 0-23 | **Godzina** kopiowana z mastera | KNOWN |
| f[9] | 0-59 | **Minuta** kopiowana z mastera | KNOWN |
| f[10] | `0x7E` | filler | UNKNOWN |
| f[11] | `0x00` | stałe | UNKNOWN |
| f[12-13] | HH,LL | **Temp pokojowa slave** (własny sensor CTP slave + jego korekta) | KNOWN |
| f[14-15] | HH,LL | **Aktywny setpoint** kopiowany z mastera | KNOWN |
| f[16-22] | `0x7E` ×7 | filler (jak master) | UNKNOWN |
| f[23] | `0x14` | stałe (jak master) | UNKNOWN |
| f[24] | `0x32` / `0x64` | **NORMALNY (synced) = `0x64`**, AWARYJNY (unsynced) = `0x32`. Paruje z f[28] bit `0x40`. | KNOWN |
| f[25] | `0x00`-`0x03` | **Faza transmisji daty** kopiowana z mastera | KNOWN |
| f[26] | wartość daty | rok/miesiąc/dzień zależnie od f[25] (kopia z mastera) | KNOWN |
| f[27] | bitfield | tryb temp + sezon + wietrzenie kopiowane z mastera | KNOWN |
| f[28] | `0x43` / `0x03` | **NORMALNY (synced) = `0x43`** (`0x40`\|`0x03`, B1 + sync flag), AWARYJNY = `0x03` (sam B1 bez sync). Slave **NIE komenderuje biegami** mimo wartości w `f[28]` — AERO ignoruje komendy z `f[3] ≠ 0x29` | KNOWN |
| f[29] | `0x23` | terminator | KNOWN |

**2 stany slave (synced vs unsynced)** — szczegóły w §5.

**Co istotne:** AERO interpretuje komendy biegu **wyłącznie** z ramki gdzie `f[3]=0x29` (master id=1). Wartość `f[28]` w odpowiedzi slave to tylko echo/zapamiętana z EEPROM — nie ma efektu mechanicznego.

### 3.14 AA/AB/AC(29) src=0x56 — iNEXT slot dla id=2/3/4 (cykl #23/25/27)

Druga forma wake-up: `AA/AB/AC,56,4C/4D/4E,29,0x00×26`.
- Inny payload (`0x00` zamiast `0x7E`), inny CRC (K=`0x23` zamiast K=`0x93`)
- Rola niejasna — być może osobny kanał dla EX4/iNEXT/rozszerzeń

**CRC wake-up:**
- src=0x44: `f[2] = (f[0]+f[1]+f[3]+25×0x7E + 0x93) & 0xFF = 0x06+id`
- src=0x56: `f[2] = (f[0]+f[1]+f[3]+25×0x00 + 0x23) & 0xFF = 0x4A+id`

### 3.15 Ramki asynchroniczne (poza cyklem)

#### 80(29) src=0x44 — slave boot announcement

Gdy Nano w trybie slave (id ≠ 1) startuje (power-on), nadaje **jeden raz** ramkę 0x80:

```
80,44,[cks],2X,7E×26,23
```

- f[0] = `0x80` (nowy typ, para do `0x81` = master heartbeat)
- f[2] = `0x5F + (id-2)` (`0x5F` dla id=2, `0x62` dla id=5, `0x63` dla id=6)
- f[3] = `0x28+id` (np. `0x2A` dla id=2)
- payload = `0x7E` fill

Ramka leci **bezwarunkowo** ~3-5s po power-on, na pierwszej dostępnej luce na busie (bus arbitration). Pozycja w cyklu master jest **losowa** — potwierdzone 3 obserwacjami:

| # | Data | Pozycja w cyklu master |
|---|------|------------------------|
| 1 | 2026-04-22 22:45:12 | Między #5 (E5) a #6 (F0) |
| 2 | 2026-04-23 22:04:04 | Między #27 (AC src=56) a #1 nowego cyklu |
| 3 | 2026-04-23 22:05:42 | Między #10 (D2) a #11 (D3) |

Po wykryciu 80(2X) Nano master odpowiada **w następnym cyklu** ramką E4(29) src=0x2X (config push) na pozycji #1.

#### E4(29) src=0x2X — config push do slave id=X

~23s po power-on Nano mastera, master **jednorazowo** wysyła E4(29) z `f[1]=0x2X` zamiast standardowego `0x21` — między pozycją #27 (AC src=56) a #1 nowego cyklu Master Full (NIE na pozycji #1 jak wcześniej notowano).

```
E4,2X,[cks],29,[FW_const ×10],[E3_copy_f14-28],23
       f[2]                    f[14-28] = mirror aktualnego E3(29) src=44
       CRC
```

**Struktura ramki (zweryfikowana 2026-04-26 testem Test1+Test2):**

| Bajty | Zawartość | Zachowanie |
|-------|-----------|------------|
| f[0] = `0xE4` | typ ramki | stałe |
| f[1] = `0x2X` | adresat: `0x2A`=id=2, `0x2B`=id=3, ... | per-id |
| f[2] | CRC (K=0xA3) | sumaryczne dla całości |
| f[3] = `0x29` | subtyp master | stałe |
| **f[4-13]** | `0D,01,05,28,1C,2A,00,1E,01,17` | **firmware constanty** — niezmienne między sesjami i niezależne od nastaw user (kalibracja AERO? wersja protokołu? id firmware?) |
| **f[14-28]** | **kopia 1:1 z E3(29) src=44 f[14-28] w momencie wysyłki** | mirror aktualnych % per bieg + parametry |
| f[29] = `0x23` | terminator | stałe |

**Test1 (2026-04-26, bez zmian nastaw mastera):**
- Power-cycle Nano mastera bez zmian w menu
- Config push 22:41:20 vs 23:16:03 (po 35min) → **bajt-w-bajt identyczne** włącznie z CRC
- Potwierdza stabilność f[4-13] i mirror f[14-28]

**Test2 (2026-04-26, zmiana % naw B1: 37→35 w menu Nano):**
- Przed power-cycle: w menu Nano `% Nawiew B1` zmieniony 37→35
- Po power-on: config push 23:28:55 ma `f[23]=0x23` (35) zamiast `0x25` (37) z poprzedniego push
- CRC f[2] poprawnie skompensowała: 0x60-2 = 0x5E (różnica = -2 w f[23])
- Pozostałe f[14-28] niezmienione (bo zmieniono tylko jedną wartość)
- **f[4-13] niezmienione** mimo że nastawy w menu inne — potwierdza że to firmware constanty, nie user data

**Wnioski:**
- Config push to **żywy snapshot** generowany w momencie wysyłki, nie pre-cache z EEPROM mastera. Slave dostaje aktualne ustawienia, nie te z momentu rejestracji.
- f[4-13] to "tożsamość mastera" (10 bajtów stałych) — slave może ich używać do walidacji/identyfikacji
- f[14-28] to po prostu broadcast E3(29) src=44 zapakowany w "personalną" ramkę dla slave (redundancja + adresowanie)

**Ograniczenia obserwacji:**
- Potwierdzone tylko dla **id=2** (Nano slave fizyczny). Symulowane VS slaves id=3/4 odpowiadały na wake-up AB/AC pełnym echo'em pól mastera (rotator daty, dow, zegar, setpoint, tryb, bieg z sync flag), ale Nano master **nie wysyłał do nich config push**. Mechanizm rozpoznania "real slave" przez Nano mastera nieznany — w menu serwisowym Nano nie ma ustawienia "lista zarejestrowanych slave'ów" (jest tylko własne ID Nano 1..20, master zawsze 1, slaves 2-20). Możliwe że master kwalifikuje slave'a po jakimś kryterium w treści odpowiedzi E4(2X) którego nasze VS nie spełniają.
- Dla id ≥ 5: **brak obserwacji** ani odpowiedzi mastera. Nano master nie ma wake-up AD/AE itd. wg cyklu Master Full — albo cykl Master Full obsługuje max 3 slave'ów (id=2-4), albo wake-upy dla wyższych id pojawiają się dopiero po spełnieniu kryterium rozpoznania.

---

## 4. Slave Nano — komunikacja dwukierunkowa

Slave Nano (panel Color CTP, id=2..20) **nie jest pasywnym reflektorem mastera** — to niezależna jednostka z własnym lokalnym termostatem, harmonogramem (EEPROM) i sensorem CTP. Komunikacja z masterem jest **dwukierunkowa**:

**Master → Slave** (slave echo'uje w E4(2X) src=0x21):
| Pole | Znaczenie |
|------|-----------|
| f[7] | day_of_week — slave wyświetla na ekranie |
| f[8-9] | godz/min — RTC sync ("DATĘ I CZAS USTAWIA NANO NR 1") |
| f[25-26] | rotator daty (3 fazy: rok/miesiąc/dzień) — slave dekoduje pełną datę po 3 cyklach |
| f[27] bity 3-4 | **sezon** (Zima/Lato bez/Chłodzenie) — slave wyświetla i aktualizuje wg mastera |
| f[27] bit 5 | wietrzenie — slave odbiera, ale na panelu slave'a nie wyświetla (zarządza tym master, dotyczy AERO) |

**Slave → Master** (slave wysyła własne wartości w E4(2X) src=0x21):
| Pole | Znaczenie |
|------|-----------|
| f[12-13] | **temperatura pokojowa** — pomiar z sensora CTP slave'a (jego własny lokalny pomiar) |
| f[14-15] | **aktywny SP** — z lokalnego harmonogramu lub Manual setpoint slave'a (NIE echo z mastera) |
| f[24] | level termostatu slave'a (`0x64`/`0x32`) |
| **f[27] bity 0-1** | **tryb termostatu lokalny slave'a** (Manual/Harmonogram/Urlop) — niezależny od mastera |
| f[28] | bieg + flagi — slave nie zarządza biegiem AERO, ale wysyła wartość (echo z EEPROM lub zapamiętana z sesji gdy był masterem) |

**Mechanizm:** każdy slave to lokalny termostat z własnym harmonogramem dziennym w EEPROM. Slave odpytuje user'a (na panelu) o tryb (Manual/Harm/Urlop) i lokalnie decyduje o swoim aktywnym setpoincie. Wysyła to do mastera + własną temperaturę pokojową. Master agreguje informacje od wszystkich slave'ów (id=2..20) i decyduje o biegu AERO (centralnym).

**Bieg AERO i wietrzenie pochodzą wyłącznie z mastera** — slave w E4(2X) wysyła wartości w f[28] ale **AERO ich nie interpretuje** (akceptuje tylko `f[3]=0x29` z master id=1). To są niejako "echo z EEPROM slave'a" — ślad po dawnym byciu masterem albo dla spójności protokołu.

**Hipotetyczna komenda Master → konkretny Slave** (sterowanie kanałami/damperami w wielostrefowym HVAC) — nie obserwowana w naszym setupie (Prodmax 300 może mieć tylko jedną strefę). Naturalne miejsce: `E4(29) src=0x2X` (config push, per-id) lub osobna ramka adresowana per-id. Patrz §7 #12.

### Synced vs Unsynced — 2 stany Nano slave

W E4(2X) src=21 obserwowane 2 wyraźne stany:

| Stan | f[24] | f[28] | Kontekst |
|------|-------|-------|----------|
| **NORMALNY (synced)** | `0x64` (100%) | `0x43` (`0x40\|0x03` = sync flag + B1) | Nano slave w długiej, stabilnej pracy z prawdziwym Nano masterem |
| **AWARYJNY (unsynced)** | `0x32` (50%) | `0x03` (sam B1, brak `0x40`) | Po eksperymentach z ESP master, długim braku komunikacji z masterem |

**Co przywraca AWARYJNY → NORMAL:**
- Power-cycle slave + obecność prawdziwego Nano mastera + AERO (potwierdzono)
- Nasz ESP master config push E4(29) src=0x2A **nie wystarcza** (mimo że ramka 1:1 z Nano)

**Co prawdopodobnie wywołuje przejście NORMAL → AWARYJNY:**
1. Wewnętrzny watchdog Nano slave po wykryciu nieprawidłowości
2. Brak konkretnej ramki od mastera (np. niepełny D0-D5)
3. Niezgodność w E4(29) src=0x2X (config push) z EEPROM slave
4. Długi czas bez triggera AERO

**f[7] w E4 od slave** zmienia się między sesjami:
- `0x02` w starszych sesjach (możliwe normal mode)
- `0x03` w nowszych (po eksperymentach — może liczba urządzeń w EEPROM)

### Nano slave — kod biegu w E4(2A)

Nano slave wysyła `f[28] = 0x43` (stary encoding B1) niezależnie od aktualnego biegu master. To jest wartość zapamiętana z sesji gdy Nano był masterem — slave **nie komenderuje biegami**, nawet jeśli `f[28]` zawiera "komendę". AERO interpretuje komendy **tylko z E4(29) src=0x21 z `f[3]=0x29`** (master id=1).

### RTC slave

Nano slave **synchronizuje zegar z magistrali** (zegar na wyświetlaczu pokazuje czas mastera po 1-2 cyklach). Mechanizm sync nie jest jeszcze w pełni rozszyfrowany — najprawdopodobniej f[7-9] + f[25-26] w E4(29) src=0x21 wystarczają. Komunikat Nano slave UI "DATĘ I CZAS USTAWIA NANO NR 1" potwierdza autorytet id=1.

---

## 5. Menu Nano Master — cross-reference (ustawienie → bajt ramki)

Ten dział to indeks ustawień **Nano w trybie master id=1** (panel sterujący AERO, biegiem, wietrzeniem, sezonem, harmonogramem globalnym). Slave Nano (id=2..20) ma **własne menu** z lokalnym termostatem — patrz §6.

Pełny opis enkodingu — w odpowiedniej sekcji ramki (§3).

### 5.1 Termostat (Manual / Harmonogram / Urlop)

| Ustawienie | Lokalizacja | Wartość |
|------------|-------------|---------|
| Tryb temp | E4 f[27] bity 0-1 (§3.2) | `0x00`=Harm · `0x01`=Urlop · `0x02`=Manual |
| Aktywny setpoint (kopia) | E4 f[14-15] (§3.2) | Manual=25°C; Harm/Urlop+Zima=eco_zima (21°C) |
| Manual flag | E4 f[28] bit `0x40` + f[24]=`0x64` (§3.2) | SET dla Manual, CLEAR dla Harm/Urlop |

Setpoint Term=Urlop+Zima = eco_zima (taki sam jak Harm) — różnica widoczna tylko przez `f[27]` bit 0 + ikonę na wyświetlaczu (kieliszek + zegarek vs sam zegarek).

**Uwaga:** Termostat-Harmonogram (kiedy comfort/eco) to **inny harmonogram** niż Wentylacja-Harmonogram (§5.3, biegi). Sam harmonogram trzymany w EEPROM Nano — sygnalizacja zmian slotów w protokole nieznana (patrz §7).

### 5.2 Sezon (Zima / Lato bez ogrzewania / Chłodzenie)

Sezon jest kodowany różnie w 3 ramkach:

| Sezon | E4 f[27] bity 3-4 (§3.2) | E5 f[27] (§3.7) | E3 f[27] (§3.3) |
|-------|--------------------------|-----------------|------------------|
| Zima | `0x00` | `0x00` | `0x01` |
| Lato bez ogrzewania | `0x08` | `0x0A` | `0x09` |
| Chłodzenie | `0x10` | `0x14` | `0x11` |

Chłodzenie aktywuje też overlay `+0x08` w E4 f[28].

### 5.3 Wentylacja (6 opcji menu Nano)

Menu Wentylacja w Nano ma 6 opcji: Harmonogram / Harm-Urlop / B3 / B2 / B1 / Stop.

| Wentylacja | E4 f[28] (§3.2) | E3 f[28] (§3.3) | f[24] (§3.2) |
|-----------|-----------------|-----------------|--------------|
| Stop (manual) | `0x01` (lub `0x41` z bitem `0x40` gdy Term=Manual) | `0x11` (lub `0x51`) | `0x32`/`0x64` wg Termostatu |
| B1 (manual) | `0x03` (lub `0x43`) | `0x13` (lub `0x53`) | wg Termostatu |
| B2 (manual) | `0x05` (lub `0x45`) | `0x15` (lub `0x55`) | wg Termostatu |
| B3 (manual) | `0x07` (lub `0x47`) | `0x17` (lub `0x57`) | wg Termostatu |
| Harmonogram | bieg z aktualnego slotu, identyczne jak Manual+bieg_slotu (slave nie odróżni) | analogicznie | wg Termostatu |
| Harm-Urlop | bieg z slotu, **BEZ bitu `0x40`** | analogicznie | **`0x32`** |

Bit `0x40` w E4 f[28] (i odpowiednio w E3 f[28]) pojawia się tylko gdy **Termostat=Manual AND korekta termostatu = 0** (patrz §3.2). E3 f[28] dodatkowo zawsze ma bit `0x10` jako znacznik typu ramki.

E5 f[28] = "kod UI" zależny od kombinacji Termostat × Sezon × Bieg — nie czysty enum biegu, patrz §3.7.

Wentylacja-Harm-Urlop **też rotuje wg harmonogramu** (zmiana slotu eco z B1→B2 natychmiast zmienia `f[28]` z `0x03`→`0x05`). Różni się od Wentylacja=Manual/Harm tylko brakiem bitu `0x40` + `f[24]=0x32`.

Wentylacja-Harmonogram i Wentylacja-Harm-Urlop to osobny harmonogram biegów (niezależny od Termostat-Harmonogram, który dotyczy setpointów — §5.1).

### 5.4 Wietrzenie (overlay ON/OFF)

| Pole | OFF | ON |
|------|-----|----|
| E4 f[27] bit `0x20` (§3.2) | 0 | **+0x20** |
| E3 f[27] bit `0x20` (§3.3) | 0 | **+0x20** |
| E5 f[27] (§3.7) | brak wpływu | brak wpływu |

Niezależny od sezonu i trybu temp.

### 5.5 Programy trybu pracy (Normal / Poza domem / Urlop)

3-stanowy radio w menu Nano. Programy nadpisują Wentylacja menu i setpoint Termostatu.

| Program | f[5] | f[14-15] (setpoint) | f[28] |
|---------|------|---------------------|-------|
| Normal | `0x40` | wg Termostatu | wg Wentylacji |
| Poza domem | `0x44` (bit `0x04` SET) | poza_domem (20°C) | bieg ze slotu poza-domem harmonogramu |
| Urlop | `0x40` | poza_domem (20°C) | `0x40` (validity=0, bieg=0) |

Bit `0x04` w `f[5]` = "Programy=Poza domem aktywne". Aktywny tylko w tym trybie; Normal i Urlop → CLEAR.

**Setpoint współdzielony:** Menu serwisowe Nano ma jedną nastawę "Poza Domem" (20°C) używaną dla OBU programów (Poza domem i Urlop).

**Programy=Urlop vs Wentylacja=Harm-Urlop:**

| | Programy=Urlop | Wentylacja=Harm-Urlop |
|----|----------------|------------------------|
| f[28] | `0x40` (validity=0) | bieg z slotu, bez `0x40` |
| f[24] | wg Termostatu | `0x32` |
| f[5] bit `0x04` | CLEAR | bez wpływu |
| Setpoint | poza_domem (override) | wg Termostatu |

Programy=Urlop wyłącza wentylację (validity=0). Wentylacja=Harm-Urlop sygnalizuje "tryb minimalny" przez `f[24]=0x32`, ale dalej rotuje wg harmonogramu.

### 5.6 Setpointy temperatur (menu serwisowe Nano)

5 niezależnych setpointów w EEPROM Nano, broadcast w E5 f[6-17]:

| Setpoint | Pozycja w E5 (§3.7) | Aktywny gdy |
|----------|---------------------|-------------|
| Comfort | f[8-9] | (zależy od harmonogramu) |
| Eco zima | f[10-11] | Sezon=Zima |
| Eco chłodzenie | f[12-13] | Sezon=Lato/Chłodz |
| Manual | f[14-15] | Termostat=Manual |
| Poza domem | f[16-17] | Urlop+Zima, Poza domem |

**Aktywny setpoint** master kopiuje do **E4 f[14-15]** zgodnie z aktualnym Termostat × Sezon:
- Manual + dowolny sezon → manual setpoint
- Harm/Urlop + Zima → eco_zima (21°C) lub poza_domem
- Harm/Urlop + Lato/Chłodz → eco_lato (18°C)

### 5.7 Bypass (OFF / AUTO / ON)

E5 f[25], 3-stanowy enum. Patrz §3.7.

| Kod | Stan |
|-----|------|
| `0x60` | OFF |
| `0x61` | AUTO |
| `0x62` | ON |

Stan fizyczny bypass widać w E4(63) f[28] (§3.4): `0x40`=zamknięty, `0x60`=otwarty.

### 5.8 Zegar, dzień tygodnia i data

Master nadaje w E4(29) src=0x21 (§3.2):

| Pole | Znaczenie | Format |
|------|-----------|--------|
| f[7] | day_of_week | `0=Pn..6=Nd` |
| f[8] | godzina | decimal jako byte (`0x0A`=10) |
| f[9] | minuta | decimal jako byte (`0x0F`=15) |
| f[25-26] | data w 3 fazach (rotujące) | `0x01`,rok mod 100 / `0x02`,miesiąc / `0x03`,dzień |

Slave rekonstruuje pełną datę po ~66s (3 cykle Master Full).

### 5.9 ID sterownika (menu serwisowe)

Wpływa na f[3] we wszystkich ramkach wysyłanych przez Nano: `f[3] = 0x28 + id` (§3.1). Tylko id=1 może sterować biegami, wietrzeniem, sezonem, datą i zegarem.

---

## 6. Menu Nano Slave — architektura

Nano w trybie slave (id=2..20) to **niezależny lokalny termostat** z własnym harmonogramem i sensorem temperatury, nie pasywny reflektor mastera. Każdy slave to osobny panel CTP montowany w innym pokoju.

### 6.1 Co slave ma własne (niezależne od mastera)

| Element | Opis |
|---------|------|
| **EEPROM harmonogramu dziennego** | Lokalny program tygodniowy (comfort/eco per godzina), niezależny od harmonogramu mastera |
| **Sensor temperatury CTP** | Wbudowany czujnik mierzący temperaturę w pomieszczeniu gdzie wisi panel |
| **Lokalny termostat (Manual/Harmonogram/Urlop)** | User na panelu slave wybiera lokalnie tryb dla **swojego** pokoju |
| **Aktywny setpoint** | Z lokalnego harmonogramu lub Manual setpoint slave'a |

### 6.2 Co slave odbiera od mastera (do wyświetlenia/synchronizacji)

| Element | Źródło | Cel |
|---------|--------|-----|
| Zegar (godz/min) | f[8-9] mastera | RTC sync, wyświetlanie czasu na panelu slave (komunikat UI: "DATĘ I CZAS USTAWIA NANO NR 1") |
| Day of week | f[7] mastera | Wyświetlanie + selekcja slotu z lokalnego harmonogramu |
| Data (rok/mies/dzień) | f[25-26] mastera (3 fazy) | Wyświetlanie pełnej daty (rekonstrukcja po ~66s) |
| Sezon (Zima/Lato/Chłodzenie) | f[27] bity 3-4 mastera | Wyświetlanie + interpretacja setpointu (eco_zima vs eco_chłodz) |

### 6.3 Co slave wysyła do mastera (raportuje swój stan)

W ramce E4(29) src=0x21 z `f[3]=0x28+id` (patrz §3.13 dla pełnej tabeli bajtów):

| Pole | Znaczenie | Obowiązek mastera |
|------|-----------|---------------------|
| f[12-13] | Temperatura pokojowa (sensor CTP slave'a) | Master agreguje temperatury wszystkich slave'ów do decyzji o biegu AERO |
| f[14-15] | Aktywny setpoint slave'a (z harmonogramu lub Manual) | Master porównuje z temp pokojową aby wnioskować zapotrzebowanie na ogrzewanie/chłodzenie |
| f[27] bity 0-1 | Lokalny tryb termostatu (Manual/Harm/Urlop) | Master wie który slave jest w jakim trybie |
| f[24] | Level termostatu (`0x64`/`0x32`) | Stan operacyjny slave'a |
| f[28] | Bieg + flagi (zapamiętane z EEPROM) | Slave **nie zarządza biegiem AERO** — wartość ignorowana przez AERO (wymaga `f[3]=0x29` mastera) |

### 6.4 Czego slave nie obsługuje

- **Bieg AERO** — slave nie wybiera, nie wyświetla; tylko master sterownik (id=1) komenderuje AERO
- **Wietrzenie** — wyłącznie master (overlay na bieg)
- **Bypass** — wyłącznie master (komenda do AERO)
- **Programy globalne (Poza domem/Urlop)** — wyłącznie master
- **Setpointy globalne (menu serwisowe)** — wyłącznie master

### 6.5 Hipotetyczna komenda Master → konkretny Slave

W systemach wielostrefowych HVAC master mógłby wysyłać do konkretnego slave'a komendy sterujące (np. otwórz/zamknij damper w pokoju). W naszym setupie (Prodmax 300) **nie obserwowana** — patrz §7 #12.

Naturalne miejsce: rozszerzenie `E4(29) src=0x2X` (config push, per-id) lub osobna ramka adresowana per-id w nieużywanych pozycjach cyklu.

---

## 7. Otwarte pytania

1. **E5(29) f[18-19]** (`00,30` stałe) — przełączanie lato/zima/chłodzenie nie zmienia. Może maska konfiguracji.
2. **E4(29) f[24]** (`0x32`/`0x64`) — paruje z f[28] bit `0x40` (Term=Manual & korekta=0). Inne stany niezbadane.
3. **E5(29) f[28] — kod UI** (obserwowane wartości `0x00`-`0x1F`, zależne od kombinacji Termostat × Sezon × Bieg × Programy × Wentylacja). Dzisiejsze testy (Sezon=Zima): `0x15` dominujące, plus `0x01/02/03/04/05/0B`. Doc historyczny: też `0x18/0x19` w innych konfiguracjach. **Wymaga systematycznego testu na wszystkich sezonach** (Lato bez ogrzewania, Chłodzenie) — dziś tylko Zima.
4. **Format E2, D0-D5** — `f[4]` i `f[6]` w D0-D5 (stałe `0x53`/`0x41`) prawdopodobnie też parametry serwisowe. Pozostałe pola D0-D5 wymagają identyfikacji testem.
5. **Cold-start Nano** — czy istnieje sekwencja handshake? ESP-master jej nie robi i działa, ale AERO może startować w trybie "trusted".
6. **Co dokładnie przełącza slave w stan synced (f[28] bit `0x40`)?** ESP master wysyła wake-up + config push E4(29) src=0x2X, ale slave dalej w trybie unsynced. Brakuje prawdopodobnie specyficznej sekwencji handshake (per-id D0/D1? specjalne pole "accept" w E4 src=0x2X?).
7. **Rola src=0x56 wake-up'ów (AA/AB/AC,56)** — inny kanał, inny CRC, payload `0x00`. Hipoteza: osobny bus dla EX4/iNEXT.
8. **f[7] w E4 od slave** (`0x02`/`0x03`) — stałe w sesji, zmienia się między sesjami. Może model firmware, liczba urządzeń, tryb pracy Nano.
9. **Jak Nano master "rozpoznaje" slave id≥3 i wysyła do niego config push?** 80 boot NIE wystarcza, pełne echo wszystkich pól mastera w E4(2X) także NIE wystarcza (zweryfikowane 2026-04-26 z VS-3). W menu Nano serwisowym nie ma ustawienia "lista slave'ów" — auto-detect, ale kryterium nieznane. Może wymaga obserwacji slave'a przez N pełnych cykli rotatora daty (3 fazy × M powtórzeń), albo specyficznego pola/flagi w E4(2X) którego brakuje.
10. **f[4-13] w E4(29) src=0x2X** (config push) — stałe między power cycles, nie zawierają daty/zegara. Co dokładnie kodują? (sezon, harmonogram tygodniowy, setpointy, kalibracja AERO?)
11. **Hipoteza "łańcuch slave'ów" — OBALONA (2026-04-27).** Przetestowane z fizycznym Nano slave id=4 (potem id=5) na busie z ESP master, bez slave id=2/3 — Nano slave odpowiadał normalnie na wake-up AC/AD i przechodził w stan SYNCED. Slave **nie wymaga** obecności poprzedników w łańcuchu, każdy reaguje wyłącznie na swój wake-up. Architektura jest **broadcast bus** (master + N independent slaves), nie hierarchical chain.
12. **Hipotetyczna komenda Master → konkretny Slave (multi-zone HVAC)** — w systemach wielostrefowych master mógłby wysyłać per-id komendy sterujące (np. otwórz/zamknij damper w pokoju gdzie jest slave). W obserwowanym ruchu z Prodmax 300 brak takich ramek. Naturalne miejsce: rozszerzenie config push `E4(29) src=0x2X` lub osobna ramka adresowana per-id. Może wymaga konfiguracji Prodmax >300 (większa multi-zona).

### Niezweryfikowane historyczne hipotezy (do sprawdzenia)

Stare obserwacje, które się NIE potwierdziły w nowszych testach — możliwe że były bus glitch / RS-485 zakłócenie albo wymagają specyficznego stanu którego jeszcze nie wywołaliśmy:

- **E4(29) f[10]=0x08 przy fan OFF** (vs `0x7E`) — historyczna obserwacja 2026-04-23, nie zaobserwowane podczas systematycznego testu Wentylacja=Stop 2026-04-26 na Nano master. Możliwe bus glitch / błędny parser w starym skrypcie. Do sprawdzenia: czy występuje gdy Nano slave aktywny.
- **E5(29) f[26]=0x50 gdy slave aktywny** (vs `0x00`) — historyczna obserwacja 2026-04-23. **Nie testowane 2026-04-26** — sesja była tylko z Nano master, bez slave na busie. Do sprawdzenia w przyszłej sesji ze slave.

Historia weryfikacji empirycznej w [HISTORY.md](HISTORY.md).

---

## Źródła / wiarygodność

Wszystkie ustalenia pochodzą z sniffu rzeczywistej magistrali (prod 2021):
- AERO 3B V2 .52 (NR M15-04-01792)
- Nano Color CTP (NR L17-02-02717)
- Centrala: Prodmax 300

Sniff przez ESP32 `esp02` w trybie bridge MITM (2× HW-0519 RS-485 na GPIO4/18 + GPIO16/17). Hipotezy weryfikowane przez zmiany stanu w menu Nano i obserwację różnic w ramkach. Formuła temperatury C14 pochodzi z wątku elektroda.pl o SOLARCOMP 951 (ten sam protokół COMPIT).

Historia odkryć i empirycznych testów: [HISTORY.md](HISTORY.md).

**Nie jest to oficjalna dokumentacja COMPIT.** Protokół jest własnościowy, ta dokumentacja może zawierać błędy lub różnić się dla innych wersji sterowników.

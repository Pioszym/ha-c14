# Protokół C14 (COMPIT) — mapa ramek

Reverse engineering magistrali RS-485 między rekuperatorem **COMPIT AERO 3B** a panelem pokojowym **COMPIT Nano Color CTP**.

**Status:** częściowo rozszyfrowany, wystarczający do pełnego sterowania. Otwarte pytania niżej.

## Hardware

- Magistrala: RS-485, 9600 8N1, terminator 0x23
- Wszystkie ramki **30 bajtów** (f[0]..f[29]), f[29] = terminator `0x23`
- Padding: `0x7E` = puste pole
- Master: Nano Color CTP (tryb **MASTER MINI** — 11 ramek/cykl ~8.5s)
- Slave główny: AERO 3B (odpowiada tylko na trigger)

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

## Enkoding temperatury

```
T = (H*128 + L%128 - 2000) / 10              # dekodowanie
val = T*10 + 2000; H = val/128; L = val%128  # kodowanie
```

Przykłady: `11,36` = 23.0°C · `11,40` = 24.0°C · `11,04` = 18.0°C · `10,66` = 15.0°C

## Cykle master

### Nano Master Mini (11 ramek, ~8.5s) — obserwowane

Nano sekwencja: komenda biegu najpierw, trigger QUERY zaraz po, potem reszta broadcastów.

| # | Ramka | Nadawca | Rola |
|---|-------|---------|------|
| 1 | E4(29) src=0x21 | Nano | Komenda biegu + zegar |
| 2 | E3(29) src=0x44 | Nano | **QUERY — trigger AERO** |
| 3 | E4(63) src=0x21 | **AERO** | **Jedyna ramka od AERO** (odpowiedź, ~400ms po triggerze) |
| 4 | E3(29) src=0x56 | Nano | iNEXT slot (zera) |
| 5 | E2(29) src=0x44 | Nano | Status broadcast |
| 6 | E5(29) src=0x21 | Nano | Setpointy temperatur + bypass |
| 7 | F0(29) src=0x44 | Nano | Heartbeat (0x7E fill) |
| 8 | 81(29) src=0x44 | Nano | Heartbeat Nano |
| 9 | D0(29) src=0x44 | Nano | Slave config 1 |
| 10 | D1(29) src=0x44 | Nano | Slave config 2 |
| 11 | D2(29) src=0x44 | Nano | Slave config 3 |

### ESP Master (esp02.yaml) — zaimplementowane

Odwrócona kolejność: iNEXT pierwsze (rezerwacja slotu), QUERY na końcu żeby AERO miała świeże nastawy. 10 ramek × 800ms = 8s cykl, interval 8500ms.

| # | Ramka | Rola |
|---|-------|------|
| 1 | E3(29) src=0x56 | iNEXT slot (rezerwacja) |
| 2 | E2(29) src=0x44 | Status broadcast |
| 3 | E5(29) src=0x21 | Setpointy temp + bypass + sezon |
| 4 | F0(29) src=0x44 | Heartbeat |
| 5 | 81(29) src=0x44 | Heartbeat Nano |
| 6 | D0(29) src=0x44 | Slave config 1 |
| 7 | D1(29) src=0x44 | Slave config 2 |
| 8 | D2(29) src=0x44 | Slave config 3 |
| 9 | E4(29) src=0x21 | Komenda biegu + zegar + sezon + wietrzenie |
| 10 | E3(29) src=0x44 | **QUERY — trigger AERO** (ostatnia) |

AERO odpowiada E4(63) ~400ms po #10. AERO nadaje **tylko E4(63)** w całym cyklu.

---

## Ramka E4(29) — KOMENDA biegu (src=0x21)

Nano → AERO. Komenda biegu + zegar + flagi trybów. AERO reaguje mechanicznie (zmienia wentylator), ale **nie odpowiada** tą ramką.

```
E4,21,[cks],29,[DOM],40,00,[DOW],[HH],[MM],7E,00,[TRM_H],[TRM_L],[SP_H],[SP_L],7E×7,14,[X24],[ROT],[LK],[F27],[F28],23
```

| Bajty | Znaczenie | Status |
|-------|-----------|--------|
| f[4] | **Dzień miesiąca** (1-31) | KNOWN |
| f[5] | 0x40 stałe | UNKNOWN |
| f[7] | **Dzień tygodnia** (1=Mon..7=Sun) | PARTIAL |
| f[8] | **Godzina** 0-23 | KNOWN |
| f[9] | **Minuta** 0-59 | KNOWN |
| f[10] | 0x7E normalnie, 0x08 przy fan OFF | PARTIAL |
| f[12-13] | **Temp pokojowa Nano** (sensor wewn CTP) | KNOWN |
| f[14-15] | **Aktywny setpoint** (śledzi aktualnie wybrany tryb: Comfort/Eco/itp.) | KNOWN |
| f[23] | 0x14 stałe | UNKNOWN |
| f[24] | Zmienne (obserwowano 0x32, 0x64, 0x00 w chłodzeniu) | UNKNOWN |
| f[25] | **Rotator cyklu:** 01 → 02 → 03 → 01 | KNOWN |
| f[26] | Lookup od f[25]: 01→0x1A, 02→0x04, 03→{0x0E,0x0F,0x13} (wariabilne) | KNOWN |
| f[27] | **Multi-field encoding** (patrz niżej) | KNOWN |
| f[28] | **BIEG + overlays** (patrz niżej) | KNOWN |

### E4(29) f[27] — multi-field encoding

Jeden bajt koduje 3 niezależne wymiary stanu:

**Bity 0-1 = Tryb sterowania temperaturą** (3 opcje, ikony na Nano):
| Bits | Tryb | Ikona |
|------|------|-------|
| 0x00 | Harmonogram | 🕐 |
| 0x01 | Wakacje/Urlop | 🍸 |
| 0x02 | Manual | 👆 |

**Bity 3-5 = Sezon** (3 enum, **nie bitmaska**):
| Bits | Sezon |
|------|-------|
| 0x00 | Zima ogrzewania |
| 0x08 | Lato bez ogrzewania/chłodzenia |
| 0x10 | Chłodzenie aktywne |

**Bit 5 overlay:**
| Bit | Znaczenie |
|-----|-----------|
| +0x20 | Wietrzenie ON (overlay, niezależny od sezonu i trybu temp) |

Łączne: f[27] = `tryb_temp | sezon | wietrzenie_overlay`.

### E4(29) f[28] — BIEG z overlayami

Bit 0 = validity flag (zawsze set), bity 1-2 = value biegu (0-3):

| Bieg | Manual | Harmonogram (+0x40) |
|------|--------|---------------------|
| Stop | `0x01` | `0x41` |
| B1 | `0x03` | `0x43` |
| B2 | `0x05` | `0x45` |
| B3 | `0x07` | `0x47` |

**Overlays:**
- `+0x08` (bit 3) = chłodzenie aktywne (dodawane do biegu: manual B1+cool = `0x0B`)

**Uwaga:** AERO reaguje mechanicznie **tylko na bity 1-2** (value biegu). Bit `0x40` (harmonogram) i `0x08` (chłodzenie) ignoruje przy decyzji o prędkości wentylatora — ale może mieć znaczenie dla innych slaves (iNext).

---

## Ramka E4(63) — ODPOWIEDŹ AERO (src=0x21)

**Jedyna ramka nadawana przez AERO.** Odpowiedź na trigger E3(29) src=0x44, przychodzi w ~400ms po triggerze.

```
E4,21,[cks],63,09,74,00,3C,00,00,[CZ_H],[CZ_L],[CZ_H],[CZ_L],[NW_H],[NW_L],[WT_H],[WT_L],[WY_H],[WY_L],7E,00,00,00,[N%],[W%],[BG],02,[BP],23
```

### Temperatury
| Bajty | Czujnik |
|-------|---------|
| f[10-11] | T1 CZERP (= T.ZEWN) |
| f[12-13] | Duplikat CZERP (zawsze = f[10-11]) |
| f[14-15] | T2 NAWIEW |
| f[16-17] | T4 WYRZUT |
| f[18-19] | T3 WYWIEW |

### Status
| Bajt | Znaczenie |
|------|-----------|
| f[24] | Nawiew % aktualny |
| f[25] | Wywiew % aktualny |
| f[26] | **Bieg: 0=Stop, 1=B1, 2=B2, 3=B3, 4=Wietrzenie** |
| f[27] | 0x02 stałe |
| f[28] | **Bypass bit 5:** `0x40`=zamknięty, `0x60`=otwarty (maska `& 0x20`) |

### % wentylatora per bieg (fabryczne)
| Bieg | f[24] naw | f[25] wyw |
|------|-----------|-----------|
| Stop | `0x00` (0%) | `0x00` (0%) |
| B1 | `0x25` (37%) | `0x20` (32%) |
| B2 | `0x2D` (45%) | `0x28` (40%) |
| B3 | `0x4B` (75%) | `0x46` (70%) |
| Wietrz. | `0x64` (100%) | `0x5F` (95%) |

---

## Ramka E5(29) — SETPOINTY + bypass + sezon (src=0x21)

Nano → magistrala. 5 setpointów temperatury, bypass enum, sezon enum.

```
E5,21,[cks],29,00,00,[CZ_H],[CZ_L],[CMF_H],[CMF_L],[ECO_H],[ECO_L],[CHL_H],[CHL_L],[RCZ_H],[RCZ_L],[POZ_H],[POZ_L],00,30,7E,00,7E,00,00,[BP],00,[SEZ],[UI],23
```

| Bajty | Znaczenie | Status |
|-------|-----------|--------|
| f[6-7] | **T.Czerpnia** (kopia z AERO E4(63), NIE sensor pokojowy) | KNOWN |
| f[8-9] | **Comfort** setpoint | KNOWN |
| f[10-11] | **Eco** setpoint | KNOWN |
| f[12-13] | **Chłodzenie** setpoint | KNOWN |
| f[14-15] | **Zadana ręczna** setpoint | KNOWN |
| f[16-17] | **Poza domem** setpoint | KNOWN |
| f[18-19] | `00,30` stałe, niezależne od lato/zima/chłodz | UNKNOWN |
| f[25] | **Bypass enum** (patrz niżej) | KNOWN |
| f[27] | **Sezon enum** (patrz niżej) | KNOWN |
| f[28] | **Kod UI Nano** (stan ekranu — złożony enum) | PARTIAL |

### Bypass (f[25]) — 3-stanowy enum
| Kod | Stan | AERO reakcja |
|-----|------|--------------|
| `0x60` | Manual OFF | Zamyka natychmiast (f[28] E4(63) = 0x40) |
| `0x61` | AUTO | Decyduje autonomicznie po temp (autonomous mode) |
| `0x62` | Manual ON | Otwiera natychmiast (f[28] E4(63) = 0x60) |

### Sezon (f[27]) — 3-stanowy enum
| Kod | Sezon |
|-----|-------|
| `0x00` | Zima ogrzewania |
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

## Ramka E3(29) src=0x44 — QUERY (TRIGGER AERO!)

**Najważniejsza ramka** — bez niej AERO nie odpowiada. Po wysłaniu tej ramki, AERO odpowiada E4(63) w ~400ms.

Zawiera nastawy % nawiewu/wywiewu per bieg (8 wartości).

```
E3,44,[cks],29,32,00,05,0A,28,1C,2A,1E,01,17,[WIET_WYW],[WIET_NAW],18,14,00,[B1_WYW],[B2_WYW],[B3_WYW],[B1_NAW],[B2_NAW],[B3_NAW],20,01,[BIEG+10h],23
```

| Bajty | Znaczenie | Status |
|-------|-----------|--------|
| f[14] | Wietrzenie wywiew % (fabr. `0x5F`=95) | KNOWN |
| f[15] | Wietrzenie nawiew % (fabr. `0x64`=100) | KNOWN |
| f[20] | B1 wywiew % (fabr. `0x20`=32) | KNOWN |
| f[21] | B2 wywiew % (fabr. `0x28`=40) | KNOWN |
| f[22] | B3 wywiew % (fabr. `0x46`=70) | KNOWN |
| f[23] | B1 nawiew % (fabr. `0x25`=37) | KNOWN |
| f[24] | B2 nawiew % (fabr. `0x2D`=45) | KNOWN |
| f[25] | B3 nawiew % (fabr. `0x4B`=75) | KNOWN |
| f[28] | Znacznik biegu = `E4 f[28] + 0x10` (manual B1 → `0x13`) | KNOWN |
| f[4-13, 16-19, 26-27] | Stałe, rola nieznana | UNKNOWN |

---

## Pozostałe ramki (broadcast, statyczne)

### E2(29) src=0x44 — status broadcast
Niemal stałe bajty (`f[4]=0x4D`, `f[8]=0x03`, reszta `0x7E`/zera). Rola nieznana.

### F0(29) src=0x44 — heartbeat
Prawie puste: `F0,44,4E,29,7E×25,23`.

### 81(29) src=0x44 — heartbeat Nano
Prawie puste: `81,44,5F,29,7E×25,23`.

### D0/D1/D2(29) src=0x44 — slave config (identyczne payload)
```
D0/D1/D2,44,[cks],29,53,4B,41,07,68,07,04,00,6E,00,5A,7E×14,23
```
- `f[4-6]` = ASCII "SKA" (wendor?)
- `f[7-14]` = stałe dane config (rola nieznana)
- Różni się tylko `f[0]` i `f[2]` (cksum)

### E3(29) src=0x56 — iNEXT slot
Same zera, `f[4-28]=0x00`. Rezerwacja miejsca dla iNEXT display.

---

## Otwarte pytania (do zbadania)

1. **E5(29) f[18-19]** (`00,30` stałe) — przełączanie lato/zima/chłodzenie **nie** zmienia tego pola. Może maska konfiguracji lub parametr którego nie testowaliśmy.
2. **E4(29) f[5]** (`0x40` stałe) — rola nieznana.
3. **E4(29) f[24]** (wariabilne `0x32`/`0x64`/`0x00`) — nie widać prostego wzoru. Może związane z setpoint delta lub PID.
4. **E4(29) f[25-26] rotator** — c=3 wariacje (`0x0E`/`0x0F`/`0x13`) zależnie od trybu.
5. **E5(29) f[28]** — pełny enum kodów UI (obserwowane niejednolite wartości).
6. **Format E2, D0-D2** — wartości w polach "stałych" mogą się zmieniać przy edge case'ach.
7. **Cold-start Nano** — czy istnieje sekwencja handshake? ESP-master jej nie robi i działa, ale być może AERO startuje w trybie "trusted".

---

## Źródła / wiarygodność

- Wszystkie powyższe ustalenia pochodzą z sniffu rzeczywistej magistrali w setupie **Piotra** (prod 2021):
  - AERO 3B V2 .52 (NR M15-04-01792)
  - Nano Color CTP (NR L17-02-02717)
  - Centrala: Prodmax 300
- Sniff przez ESP32 `esp02` w trybie bridge MITM (2x HW-0519 RS-485 na GPIO4/18 + GPIO16/17)
- Hipotezy weryfikowane przez zmiany stanu w Nano i obserwację różnic w ramkach
- Formuła temperatury C14 pochodzi z wątku elektroda.pl o SOLARCOMP 951 (ten sam protokół COMPIT)

**Nie jest to oficjalna dokumentacja COMPIT.** Protokół jest własnościowy, a ta dokumentacja może zawierać błędy lub różnić się dla innych wersji sterowników.

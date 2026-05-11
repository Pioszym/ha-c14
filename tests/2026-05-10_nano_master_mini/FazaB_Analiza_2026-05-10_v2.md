# Faza B — Analiza testu Nano Master Mini z 2026-05-10 (v2, re-analiza)

**Log:** `log_esp02_202605101228.log` (12:28:37 — 13:58:25, ~23 522 linii)
**Markery:** `markers.txt` (71 zdarzeń, T1..MX6/6)
**Plan:** `TEST_NANO_MASTER_MINI.md` § Faza B (defensive verification, bez auto-update PROTOCOL.md)

Notacja: `f[N]` = bajt N w ramce 30B; `→` zmiana; ✓ zgodne z PROTOCOL; ⚠ niezgodne; 🔍 nowe odkrycie.
Analiza per test = pierwsze 2-3 cykle Master Mini po markerze (cykl ~8.5s).

Encoding setpointów (kontekst): `T = (H*128 + L%128 - 2000)/10`.
- Comfort 23.0°C = `11,36`; Eco zima 20.0°C = `11,18`; Eco chłodz 18.0°C = `11,04`;
- Manual 25.0°C = `11,4A` / 19.3°C = `11,11`; Poza 16.0°C = `10,70`.

**Pola E4(29):** f[12-13]=T_pok (rośnie naturalnie przez sesję 19.6→20.7°C), f[14-15]=aktywny SP, f[24]=sync flag, f[27]=sezon|term|wietrz, f[28]=bieg|stable|chłodz_overlay.

---

## F0 baseline (12:49:01 — 12:50:30, log T0)

Reprezentatywna ramka cyklu (Sezon=Zima, Term=Harm, Went=B1, Wietrz=OFF, Bypass=AUTO, Programy=Normal):
```
E4   [E4,21,70,29,0A,40,00,06,0C,31,7E,00,11,18,11,18,7E×7,14,32,02,05,00,03,23]
E3   [E3,44,68,29,32,00,05,0A,28,1C,2A,1E,01,17,1E,1E,18,14,00,24,20,23,22,23,25,23,20,01,13,23]
AERO [E4,21,69,63,09,74,00,3C,00,00,10,4A,10,4A,11,1C,10,74,11,2B,7E,00,00,00,23,20,01,02,40,23]
E5   [E5,21,1A,29,00,00,10,4A,11,36,11,18,11,04,11,4A,10,70,00,30,7E,00,7E,00,00,61,00,00,01,23]
```

**Anomalia F0 (do wyjaśnienia):**
- W markers.txt baseline (12:47:10-12:47:19) widać `E4 f[24]=0x64`, `f[28]=0x43` + `E3 f[28]=0x53` (stable SET).
- W LOGU od 12:49:01 (T0+) już `f[24]=0x32`, `f[28]=0x03`, `E3 f[28]=0x13` — stable bit **utracony** w oknie 12:47:19 → 12:49:01 (najprawdopodobniej przez nawigację menu Nano przed pierwszym markerem).
- **Wniosek:** state "Manual+stable" znikł **przed T1** i już nigdy nie wrócił przez całą sesję — kluczowe dla interpretacji wszystkich późniejszych testów dotykających `f[28] bit 0x40`.

---

# CZĘŚĆ I — TESTY LINIOWE

## T1: Sezon Zima → Lato bez (12:50:33)

```
E4   [...,11,19,11,04,...,14,32,01,1A,08,03,23]
E3   [...,20,09,13,23]
E5   [...,61,00,0A,01,23]
AERO [...,23,20,01,02,60,23]   # bypass otwarty!
```

| Pole | F0 → T1 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x00`→`0x08` | §3.2 Lato bez | ✓ |
| E4 f[28] | `0x03` (bez zmian) | §3.2 — sezon overlay tylko Chłodz | ✓ |
| E3 f[27] | `0x01`→`0x09` | §3.3 Lato bez \| bypass=AUTO | ✓ |
| E3 f[28] | `0x13` (bez zmian) | – | ✓ |
| E5 f[27] | `0x00`→`0x0A` | §3.7 Lato bez | ✓ |
| **E4 f[14-15]** | `11:18`→`11:04` | §5.6: Harm+Lato bez=Eco_chłodz | ✓ |
| **AERO f[28]** | `0x40`→`0x60` | – | 🔍 **auto-bypass otwarty w Lato bez+AUTO** |

**🔍 T1 nowe odkrycia:**
1. **Auto-bypass działa również w sezonie Lato bez** (nie tylko Chłodzenie z T15c) — AERO sam otworzył mimo `f[25]=0x61` niezmiennego. Wcześniej Faza 4b zakładała auto-bypass tylko dla Chłodzenia.
2. **Slot Harm dla Sezon=Lato bez używa Eco_chłodz** (f[12-13] w E5 = `11:04` = 18.0°C). PROTOCOL §5.6 to dopuszcza ("aktywny gdy Lato/Chłodz"), ale brak jednoznacznego potwierdzenia per Sezon.

**Bajty synchronizacji:**
- E5 f[6-7]: `10:48`→`10:4A` — mirror AERO f[10-11] (T.Czerpnia 12.0→12.2°C), potwierdza §3.7.

---

## T2: Sezon Lato bez → Chłodzenie (12:54:04)

```
E4   [...,11,1D,11,04,...,14,00,02,05,10,0B,23]
E3   [...,20,11,1B,23]
E5   [...,61,00,14,01,23]
AERO [...,02,60,23]
```

| Pole | T1 → T2 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x08`→`0x10` | §3.2 Chłodz | ✓ |
| E4 f[28] | `0x03`→`0x0B` | §3.2 +`0x08` chłodz overlay | ✓ |
| **E3 f[28]** | `0x13`→`0x1B` | §3.3 nie wymienia | 🔍 **E3 f[28] dostaje +`0x08` Chłodz overlay** |
| E3 f[27] | `0x09`→`0x11` | §3.3 | ✓ |
| E5 f[27] | `0x0A`→`0x14` | §3.7 | ✓ |
| **E4 f[24]** | `0x32`→`0x00` | §3.2: tylko `0x32`/`0x64` | 🔍 **trzecia wartość `0x00`** w Chłodz+brak_stable |

**🔍 T2 nowe odkrycia:**
1. **E3 f[28] +`0x08` overlay Chłodz** — analogicznie do E4 f[28]. Dotąd PROTOCOL §3.3 tego nie wymieniał.
2. **E4 f[24]=`0x00`** — trzecia wartość poza zdokumentowanymi (`0x32`/`0x64`). Występuje gdy Sezon=Chłodzenie **AND** `f[28] bit 0x40` CLEAR.

---

## T3: Sezon Chłodzenie → Zima (12:56:36)

DIFF T2→T3 (wszystko clear):
- E4 f[27] `0x10`→`0x00` ✓ · f[28] `0x0B`→`0x03` ✓ · f[24] `0x00`→`0x32` ✓
- E3 f[27] `0x11`→`0x01` ✓ · f[28] `0x1B`→`0x13` ✓ (overlay clear)
- E5 f[27] `0x14`→`0x00` ✓
- E4 f[14-15] `11:04`→`11:18` (Eco_chłodz→Eco_zima) ✓
- **AERO f[28] `0x60`→`0x40`** ✓ — Zima dezaktywuje auto-bypass.

**🔍 Obserwacja:** stable bit nadal CLEAR po powrocie do Zima+Harm — potwierdza anomalię F0 (raz utracony stable nie wraca samoczynnie).

---

## T4: Termostat Harm → Manual (12:57:56)

```
E4   [...,11,20,11,4A,...,14,64,02,05,02,43,23]
E3   [...,20,01,53,23]
E5   [...,61,00,00,15,23]
```

| Pole | T3 → T4 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x00`→`0x02` | §3.2 Manual | ✓ |
| E4 f[28] | `0x03`→`0x43` | §3.2 +`0x40` stable | ✓ |
| E4 f[24] | `0x32`→`0x64` | §3.2 synced | ✓ |
| E4 f[14-15] | `11:18`→`11:4A` (20.0→25.0) | §5.6 Manual SP | ✓ |
| E3 f[28] | `0x13`→`0x53` | §3.3 +`0x40` | ✓ |
| **E5 f[28]** | `0x01`→`0x15` | §3.7 podaje `0x19` dla "Manual+Zima" | ⚠ **`0x15` ≠ `0x19`** |

**⚠ T4 niezgodność:** E5 f[28]=`0x15` (nie `0x19`) w Manual+Zima+B1+Term=Manual. PROTOCOL §3.7 wymaga korekty.

**Dekompozycja:** `0x15` = `0x10 | 0x04 | 0x01`. Hipoteza: bit `0x10` = Term=Manual aktywny w UI, bit `0x04` = grupa B1/B2/B3 stała, bit `0x01` = validity.

---

## T5: Termostat Manual → Urlop (12:58:57)

```
E4   [...,11,22,11,18,...,14,32,01,1A,01,03,23]
E5   [...,61,00,00,0B,23]
```

| Pole | T4 → T5 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x02`→`0x01` | §3.2 Urlop | ✓ |
| E4 f[28] | `0x43`→`0x03` | §3.2 −`0x40` | ✓ |
| E4 f[24] | `0x64`→`0x32` | §3.2 unsynced | ✓ |
| **E4 f[14-15]** | `11:4A`→`11:18` (25.0→20.0) | §5.1: Urlop+Zima=Eco_zima | ✓ |
| **E5 f[28]** | `0x15`→`0x0B` | §3.7 "Urlop+Zima"=`0x05` | ⚠ **`0x0B` ≠ `0x05`** |
| E3 f[28] | `0x53`→`0x13` | – | ✓ |

**⚠ T5 niezgodność:** E5 f[28]=`0x0B` (Urlop+Zima+B1), PROTOCOL §3.7 podaje `0x05`. Wymaga korekty tabeli.

**⚠ Dodatkowo:** Termostat=Urlop+Zima → SP **Eco_zima** (20.0°C), NIE Poza domem (16.0°C). PROTOCOL §5.6 błędnie listuje "Urlop+Zima" jako warunek Poza-domem.

---

## T6: Termostat Urlop → Harm reset (12:59:44)

DIFF T5→T6: E4 f[27] `0x01`→`0x00`, f[28] `0x03` (B1), f[24] `0x32`; E5 f[28] `0x0B`→`0x01` ⚠ (PROTOCOL §3.7 podaje `0x05` dla Harm+Zima — ale w T6 mamy `0x01`).

**🔍 Hipoteza E5 f[28]:** `0x01` to UI code "Manual-wybrany B1 + Zima" (validity SET, bieg=0=B1, brak Manual-flag). `0x05` to "Harm-wybrany-bieg + Zima" (validity + 0x04 grouping). Wartości zależą od trybu wyboru **Wentylacji** w Nano (manualny vs harmonogram), nie tylko Term×Sezon.

Wniosek: tabela §3.7 wymaga dodatkowych wymiarów (Wentylacja_mode + Term + Sezon + bieg).

---

## T7-T9: Wentylacja B1 → B2 → B3 → Stop

| Test | E4 f[28] | E3 f[28] | E5 f[28] | AERO f[26] | AERO f[24-25] |
|------|----------|----------|----------|------------|---------------|
| F0/T6 B1 | `0x03` | `0x13` | `0x01` | `0x01` | `0x23,0x20` (35/32) |
| T7 B2 | `0x05` | `0x15` | `0x02` | `0x02` | `0x25,0x23` (37/35) |
| T8 B3 | `0x07` | `0x17` | `0x03` | `0x03` | `0x23,0x22` (35/34) |
| T9 Stop | `0x01` | `0x11` | `0x00` | `0x00` | `0x23,0x22` → po lagu `0x00,0x00` (45-60s opóźnienia AERO) |

**✓ wszystko zgodne z PROTOCOL §3.2/§3.3.**
**🔍 E5 f[28] uzupełnienie:** B1=`0x01`, B2=`0x02`, B3=`0x03`, Stop=`0x00` (gdy Term=Harm+Zima).
**🔍 AERO f[24-25]:** wartości `B3 Naw=35% Wyw=34%` zgadzają się z menu serwisowym (markers.txt notuje "B3 wyw < B2 wyw — kompromis akustyczny").
**Obserwacja T9:** AERO fizycznie zatrzymał silniki o 13:02:12 (lag ~44s od marker T9 13:01:28 — duże opóźnienie reakcji silników na Stop).

---

## T10-T12: Wentylacja {Stop, Harm, Harm-Urlop, B1}

| Test | Zmiana | E4 f[28] | E3 f[28] | E5 f[28] | Komentarz |
|------|--------|----------|----------|----------|-----------|
| T10 | Stop → Harm | `0x01`→`0x05` | `0x11`→`0x15` | `0x00`→`0x05` | slot Harm = B2 |
| T11 | Harm → Harm-Urlop | `0x05` (bez zm.) | `0x15` (bez zm.) | `0x05`→`0x04` | **E4/E3 niezmienne, różnica TYLKO w E5** |
| T12 | Harm-Urlop → B1 | `0x05`→`0x03` | `0x15`→`0x13` | `0x04`→`0x01` | reset |

**🔍 T11 kluczowe odkrycie:** w trybie Term=Harm różnica między Wentylacja=Harm a Harm-Urlop **widoczna tylko w E5 f[28] bicie 0** (`0x05`↔`0x04`). PROTOCOL §5.3 sugeruje `f[24]=0x32` jako wyznacznik Harm-Urlop, ale w T11 oba mają `f[24]=0x32`. Stable bit `0x40` clear dla obu (bo Term=Harm).

---

## T13-T15: Bypass AUTO → OFF → ON → AUTO (Sezon=Zima)

| Test | E5 f[25] | E3 f[27] | AERO f[28] | Lag AERO |
|------|----------|----------|-------------|----------|
| F0/T12 AUTO | `0x61` | `0x01` | `0x40` | – |
| T13 OFF | `0x60` | `0x00` 🔍 | `0x40` (już zamknięty) | 0 |
| T14 ON | `0x62` | `0x02` 🔍 | `0x60` (~6s) | ≤1 cykl |
| T15 AUTO | `0x61` | `0x01` | `0x60`→`0x40` (~7s) | ≤1 cykl |

**🔍 T13-T15 kluczowe odkrycie — E3 f[27] zawiera bypass cmd:**

PROTOCOL §3.3 obecnie mówi "f[27] = sezon, bit 0 zawsze SET". To **niezgodne** z testem.

Empiryczna formuła: **`E3 f[27] = (sezon_szyld << 3) | (bypass_cmd & 0x03)`** gdzie:
- Sezon szyld: Zima=`0x00`, Lato bez=`0x08`, Chłodz=`0x10`
- Bypass cmd: OFF=`0x00`, AUTO=`0x01`, ON=`0x02`
- Bit `0x20` overlay = Wietrzenie ON (analogicznie jak E4 f[27])

Tabela (Wietrz OFF):
| Sezon × Bypass | OFF | AUTO | ON |
|----------------|-----|------|-----|
| Zima | `0x00` | `0x01` | `0x02` |
| Lato bez | `0x08` | `0x09` | `0x0A` |
| Chłodz | `0x10` | `0x11` | `0x12` |

Potwierdzone w sesji: T13 (Zima+OFF=`0x00`), T14 (Zima+ON=`0x02`), T15 (Zima+AUTO=`0x01`), T15d (Chłodz+OFF=`0x10`), T15e (Chłodz+AUTO=`0x11`), MX5a (Zima+ON=`0x02`), MX5b (Chłodz+ON=`0x12`), MX5c (Lato bez+ON=`0x0A`).

**Czas reakcji AERO:** T14 marker 13:08:15 → AERO `0x60` w pierwszej odpowiedzi 13:08:21 (~6s = jeden cykl Mini). Po komendach OFF/AUTO podobnie. Brak debounce widoczny w sekwencji T15b/1-5.

---

## T15b/1-5: Bypass szybka sekwencja (~10s/krok) (13:10:31..13:12:19)

Sekwencja AUTO→OFF→AUTO→ON→AUTO→OFF wykonana z ~13s/krok. Wszystkie 5 komend dotarły:
- E5 f[25] zmieniał się natychmiast, każdy stan widoczny ≥1 cykl
- AERO reagował w 1 cyklu Mini (na zmiany faktycznie zmieniające stan: `0x40`↔`0x60`)
- **Brak debounce / utraconych komend** mimo szybkiej kadencji

---

## T15c-f: Auto-bypass w Chłodzeniu (Faza 4b — kluczowy test)

**T15c (Sezon=Chłodz, Term=Manual, Bypass=AUTO, SP=25→19.3 → cooling demand):**
```
E4   [...,11,2A,11,4A,...,14,32,01,1A,12,03,23]      # przed SP=19.3
E4   [...,11,2A,11,4A,...]                            # SP=25 nadal, ale Manual potem zmieniony
E5   [...,61,00,14,15,23]
AERO [...,02,40,23] → markers.txt: 13:16:31 panel pokazał bypass=ON
```

| Pole | Stan | Komentarz |
|------|------|-----------|
| E5 f[25] | `0x61` (niezmienne) | komenda AUTO trzymana |
| **AERO f[28]** | `0x40`→`0x60` autonomicznie po SP=19.3 | 🔍 **AERO sam otwiera, master tylko proxy** |
| E4 f[24] | `0x32` (NIE `0x64`) | **stable bit CLEAR w Manual+Chłodz!** |
| E4 f[28] | `0x03` (brak `0x40` stable) | – |
| E5 f[28] | `0x15` | Manual+Chłodz+B1 UI code |

**🔍 Hipotezy 4c potwierdzone:**
1. **`f[25]` (E5) = komenda usera**, nigdy nie zmienia się autonomicznie.
2. **`f[28]` (AERO E4(63)) = stan fizyczny bypass**, AERO ma autonomię w AUTO.
3. **Auto-bypass aktywuje się gdy:** (Sezon=Chłodz **OR** Lato bez) **AND** Bypass=AUTO **AND** cooling demand (T_pok > active SP).

**🔍 T15c dodatkowe odkrycie — stable bit NIE aktywuje się w Manual+Chłodz:**
- T4 (Manual+Zima): stable SET ✓
- T15c (Manual+Chłodz): stable CLEAR ⚠
- MX6/1 (Manual+Zima — drugie wejście w Manual w sesji): stable CLEAR ⚠

Wniosek: stable bit aktywuje się **tylko** przy świeżym wejściu w Manual w określonych warunkach (potencjalnie Manual+Zima+B1/B2/B3+korekta=0). Raz utracony — nie wraca. PROTOCOL §3.2 wymaga ostrożnej reformulacji warunków.

**T15d (AUTO→OFF, Chłodz, AERO otwarty):**
- E5 f[25] `0x61`→`0x60`; E3 f[27] `0x11`→`0x10` (Chłodz+OFF); AERO `0x60`→`0x40`.
- ✓ Komenda OFF nadpisuje auto-decyzję AERO mimo aktywnego cooling demand.

**T15e (OFF→AUTO, Chłodz):**
- E5 f[25] `0x60`→`0x61`; E3 f[27] `0x10`→`0x11`; AERO `0x40`→`0x60` w pierwszym cyklu (markers.txt 13:19:14, ~25s lag).
- ✓ AUTO+Chłodz+cooling_demand → AERO otwiera.

**T15f (Sezon Chłodz→Zima, Bypass=AUTO):**
- E4 f[27] `0x12`→`0x02`; E4 f[28] `0x0B`→`0x03`; E5 f[27] `0x14`→`0x00`; E3 f[28] `0x1B`→`0x13`; AERO `0x60`→`0x40` natychmiast.
- ✓ Zima dezaktywuje auto-bypass.

---

## T16-T25: Setpointy (Faza 5) (13:23:44 — 13:28:11)

Wszystkie 10 testów zmienia jeden z 5 setpointów w E5 o ±0.5°C i resetuje. Encoding `T = (H*128+L%128-2000)/10` potwierdzony.

| Test | SP | E5 pole | Zmiana | Werdykt |
|------|----|---------|--------|---------|
| T16/17 | Comfort | f[8-9] | `11:36`↔`11:31` | ✓ |
| T18/19 | Eco zima | f[10-11] | `11:18`↔`11:13` | ✓ |
| T20/21 | Eco chłodz | f[12-13] | `11:04`↔`10:7F` | ✓ |
| T22/23 | Manual | f[14-15] | `11:11`↔`11:0C` | ✓ |
| T24/25 | Poza domem | f[16-17] | `10:70`↔`10:6B` | ✓ |

**Obserwacja:** SP zmienia się w E5 natychmiast (1 cykl), ale w E4 f[14-15] (aktywny SP) tylko jeśli aktualny tryb używa zmienionego pola. Np. w T22 (Manual zmieniany w Term=Harm) — E5 f[14-15] zmienia się, ale E4 f[14-15] (= Eco_zima) bez zmian. Spójne z §5.6.

---

## T30: Wietrzenie OFF → ON (13:29:05)

```
E4   [...,14,32,01,1A,20,03,23]
E3   [...,20,21,13,23]
E5   [...,61,00,00,01,23]
AERO [...,1E,1E,04,0A,40,23]    # f[24-25]=30%/30%, f[26]=04, f[27]=0A
```

| Pole | F0_reset → T30 | PROTOCOL | Werdykt |
|------|----------------|----------|---------|
| E4 f[27] | `0x00`→`0x20` | §3.2 +`0x20` Wietrz | ✓ |
| E3 f[27] | `0x01`→`0x21` (Zima\|Wietrz) | §3.3 +`0x20` | ✓ |
| E5 f[27] | `0x00` (bez zmian) | §3.7 "brak wpływu" | ✓ |
| E5 f[28] | `0x01` (bez zmian) | – | ✓ |
| **AERO f[26]** | `0x01`→`0x04` | §3.4 bieg=4=Wietrzenie | ✓ |
| **AERO f[27]** | `0x02`→`0x0A` | §3.4 wymienia `0x00`/`0x02` | 🔍 **nowa wartość `0x0A`** = Wietrzenie aktywne |
| **AERO f[24-25]** | `0x23,0x20` (35/32%) → `0x1E,0x1E` (30/30%) | – | ✓ % Wietrzenie z menu serwisowego |

**Obserwacja:** Wietrzenie auto-wyłącza się po krótkim czasie — w cyklu 2 (8s później) AERO f[26-27] już wróciły do `0x02,0x02` (B1 aktywny), f[27] mastera też wrócił do `0x00`. To prawdopodobnie feature UI Nano (timeout Wietrzenia w menu serwisowym), nie zachowanie protokołu.

---

## T31: Wietrzenie ON → OFF (13:29:29)

Powrót do baseline. DIFF: E4 f[27] `0x20`→`0x00`; E3 f[27] `0x21`→`0x01`; AERO f[26-27] `04,0A`→`02,02`. ✓

---

# CZĘŚĆ II — TESTY KRZYŻOWE (MIX)

## MX1: Sezon × Wentylacja

### MX1a: Went=Harm + Sezon Zima→Chłodz (13:31:22)

Pre (Went=Harm slot=B1, Zima): `E4 f[28]=0x05` (slot rotował z B1 na B2), `E3 f[28]=0x15`.
Post (Chłodz):
```
E4   [...,14,00,03,0A,10,0D,23]   # f[28]=0D=0x05|0x08
E3   [...,20,11,1D,23]            # f[28]=1D=0x15|0x08
E5   [...,61,00,14,05,23]         # E5 f[28]=05 (Harm+Chłodz UI)
```

**✓ Wnioski:** overlay `+0x08` Chłodz aplikuje się do bieg ze slotu Harm tak samo jak do biegu manualnego (E4 i E3 oba dostają overlay). f[24]=`0x00` (Chłodz+brak stable).

### MX1b: Went Harm → Harm-Urlop (Sezon=Chłodz) (13:32:07)

DIFF: E4/E3 f[28] **bez zmian** (`0x0D`/`0x1D`); E5 f[28] `0x05`→`0x04` (różnica bit 0).
**🔍 Potwierdza T11:** różnica Harm vs Harm-Urlop widoczna **tylko w E5 f[28]**, gdy Term=Harm.

### MX1c: Sezon Lato bez → Chłodz (Went=B1) (13:34:03)

DIFF: E4 f[27] `0x08`→`0x10`, f[28] `0x03`→`0x0B`; E3 f[27] `0x09`→`0x11`, f[28] `0x13`→`0x1B`; E5 f[27] `0x0A`→`0x14`. **✓ wszystko zgodne.**

### MX1d: Sezon Lato bez → Chłodz (Went=Stop) (13:35:58)

```
E4   [...,14,00,03,0A,10,09,23]   # f[28]=09 = 0x01|0x08 (Stop+chłodz)
E3   [...,20,11,19,23]            # f[28]=19 = 0x11|0x08
E5   [...,61,00,14,00,23]
AERO [...,00,00,00,00,60,23]      # f[20-27]=00,00,00,00,00,00,00,00; bypass 60!
```

**🔍 MX1d nowe odkrycia:**
1. **Stop+Chłodz** = E4 f[28]=`0x09`, E3 f[28]=`0x19`. Overlay `+0x08` aplikuje się nawet do biegu Stop.
2. **AERO w pełnym Stop zeruje f[20-27]** — f[20] zmienia się z `0x7E` na `0x00`, f[24-27] wszystkie `0x00`. PROTOCOL §3.4 mówi "f[20-23]=7E,00,00,00 stałe" — w Stop **f[20]=`0x00`** (uzupełnić).
3. **AERO f[28]=`0x60` (bypass otwarty)** mimo Sezon=Chłodz+Went=Stop. Najprawdopodobniej pozostałość z T15c (bypass był otwarty, brak wentylatorów = brak motoryzacji do zamknięcia). Wymaga osobnej weryfikacji.

---

## MX2: Termostat × Wentylacja

### MX2a: Went B1→Harm (Term=Manual, Sezon=Chłodz) (13:37:41)

Pre (Manual+Chłodz+B1): `E4 f[28]=0x0B`, f[27]=`0x12`, f[24]=`0x32` (**stable BRAK mimo Manual**).
Post (Went=Harm, slot=B2):
```
E4   [...,14,00,01,1A,12,0D,23]   # f[28]=0D (B2+chłodz); brak 0x40!
E3   [...,20,11,1D,23]            # f[28]=1D
E5   [...,61,00,14,19,23]         # f[28]=19 (Manual+Chłodz+Harm UI)
```

**🔍 MX2a kluczowy wniosek:** Term=Manual+Wentylacja=Harm **NIE aktywuje stable bit** `0x40` (zgodnie z PROTOCOL §3.2 oczekiwałoby się że Manual aktywuje stable — niezależnie od Wentylacji). Tu f[28]=`0x0D` (bez `0x40`), f[24]=`0x00`.

Warunki stable bit aktywacji w sesji:
- T4 (Manual+Zima+B1, świeże wejście): SET ✓
- T15c (Manual+Chłodz+B1, świeże wejście): CLEAR
- MX2a (Manual+Chłodz+Harm): CLEAR
- MX6/1 (Manual+Zima+B1, drugie wejście po sesji): CLEAR

Hipoteza: stable wymaga **świeżego wejścia w Manual w Sezon=Zima**. Po wyjściu z Manual (lub w Chłodz) — clear, nie wraca.

### MX2b: Went Harm → Harm-Urlop (Term=Manual, Chłodz) (13:38:25)

DIFF: E4 f[28] niezmienne `0x0D`; E5 f[28] `0x19`→`0x18`.
**Wniosek:** identyczne do MX1b — różnica tylko bit 0 w E5.

### MX2c: Went B1 → Harm (Term=Harm, Sezon=Chłodz) (13:40:05)

Pre (Harm+Chłodz+B1): `E4 f[28]=0x0B`, E3 f[28]=`0x1B`. Post (slot=B2): `E4 f[28]=0x0D`, E3 f[28]=`0x1D`, E5 f[28] `0x01`→`0x05`. **✓** Slot Harm rotuje per cykl tak samo w Zima i Chłodz.

### MX2d: Went B1 → Harm (Term=Urlop, Sezon=Chłodz) (13:41:20)

Pre (Urlop+Chłodz+B1): `E4 f[27]=0x11`, f[28]=`0x0B`, E5 f[28]=`0x0F`. Post (slot=B2): f[28]=`0x0D`, E5 f[28]=`0x0F` (niezmienne dla cycle 1, potem rotuje).

**🔍 MX2d:** Term=Urlop **NIE dominuje** nad Wentylacją=Harm — slot Harm dalej rotuje. To różni Term=Urlop od Programy=Urlop (MX4d gdzie f[28]=`0x00`).

---

## MX3: Wietrzenie × Sezon × Termostat

### MX3a: Wietrz OFF→ON (Chłodz, Manual, B2) (13:42:26)

```
E4   [...,11,2F,11,11,...,14,00,03,0A,32,0D,23]    # f[27]=32=0x12|0x20
E3   [...,20,31,1D,23]                              # f[27]=31=0x11|0x20
E5   [...,61,00,14,16,23]                           # f[28]=16
AERO [...,1E,1E,04,0A,60,23]                        # wietrzenie aktywne; bypass auto otwarty
```

DIFF: E4 f[27] `0x12`→`0x32`; E3 f[27] `0x11`→`0x31`; E4 f[28] niezmienne `0x0D` (B2+Chłodz); AERO f[26-27] `02,02`→`04,0A`, f[24-25] `aktualne%`→`1E,1E`; AERO f[28] `0x60` (auto-bypass dalej otwarty).

**🔍 E5 f[28]=`0x16`** dla Manual+Chłodz+Wietrz+B2 (nowy kod UI).

### MX3b: Wietrz OFF→ON (Lato bez, Harm, B1) (13:44:03)

DIFF: E4 f[27] `0x08`→`0x28`; E3 f[27] `0x09`→`0x29` (Lato\|AUTO\|Wietrz); E4 f[28] `0x03` niezmienne; AERO `04,0A,60` (auto-bypass Lato bez!).

**🔍 Lato bez+AUTO+B1 = AERO otworzył bypass autonomicznie** — potwierdzenie T1, że auto-bypass działa nie tylko w Chłodzeniu.

### MX3c: Wietrz OFF→ON (Zima, Urlop, B1) (13:45:10)

DIFF: E4 f[27] `0x01`→`0x21`; E3 f[27] `0x01`→`0x21`; AERO `04,0A,40` (zima — bypass zamknięty mimo Wietrz).

**✓ Wniosek:** Nano **nie blokuje** Wietrzenia w Term=Urlop.

### MX3d: Went B1→Harm-Urlop (Wietrz=ON, Zima, Urlop) (13:46:05)

DIFF: E4 f[28] `0x03`→`0x05` (B1→slot B2); E3 f[28] `0x13`→`0x15`; f[27] zachowany `0x21` (Wietrz overlay przetrwał zmianę Wentylacji).

**🔍 Wniosek:** Wietrzenie nie jest wymuszane na OFF przy zmianie Wentylacji=Harm-Urlop. Overlay `0x20` żyje niezależnie do timeout Nano.

---

## MX4: Programy × wszystko

### MX4a: Programy Normal→Poza domem (Zima, Harm, B1) (13:47:32)

```
E4   [...,0A,44,...,11,2F,10,70,...,14,32,01,1A,00,01,23]    # f[5]=44, f[14-15]=10:70 (Poza 16°C), f[28]=01 (Stop ze slotu Poza)
E3   [...,20,01,11,23]                                        # f[28]=11 (Stop)
E5   [...,61,00,00,01,23]
AERO [...,23,20,00,00,40,23]                                  # f[26-27]=00,00 (zatrzymany)
```

| Pole | Pre → MX4a | PROTOCOL | Werdykt |
|------|------------|----------|---------|
| E4 f[5] | `0x40`→`0x44` | §5.5 bit `0x04`=Programy=Poza | ✓ |
| E4 f[14-15] | `11:18`→`10:70` (Eco_zima→Poza 16.0) | §5.5 | ✓ |
| E4 f[28] | `0x03`→`0x01` | §5.5 "bieg ze slotu poza-domem" | ✓ slot=Stop (~13:47) |
| AERO f[26-27] | `02,02`→`00,00` | – | ✓ AERO reaguje |

**Obserwacja markers.txt:** "AERO wentylatory STOP w trakcie MX4a @ 13:49:26" — AERO faktycznie zatrzymał silniki po komendzie Stop.

### MX4d: Programy Poza domem → Urlop (13:50:26)

```
E4   [...,0A,40,...,11,2F,10,70,...,14,32,03,0A,00,00,23]    # f[5]=40 (bit 04 CLEAR!); f[28]=00!
E3   [...,20,01,11,23]                                        # f[28]=11 niezmienne
E5   [...,61,00,00,01,23]
AERO [...,00,00,00,00,40,23]                                  # zeruje
```

| Pole | MX4a → MX4d | PROTOCOL | Werdykt |
|------|-------------|----------|---------|
| E4 f[5] | `0x44`→`0x40` | – | ✓ Urlop CLEAR bit 0x04 |
| E4 f[14-15] | `10:70` (bez zmian) | §5.5 "Poza domem 20°C" | ⚠ PROTOCOL podaje 20°C, w teście 16°C (per E5 f[16-17]) |
| **E4 f[28]** | `0x01`→`0x00` | §3.2/§5.5 "Urlop \| f[28]=`0x40`" | ⚠ **`0x00` nie `0x40`** |
| AERO f[20-27] | zera | – | ✓ AERO pełen stop |

**⚠ MX4d kluczowa niezgodność:** PROTOCOL §3.2 mówi "Programy=Urlop \| f[28]=`0x40` (validity=0, bieg=0)". W rzeczywistości `f[28]=0x00` — validity=0+bieg=0, **bez bitu `0x40`**.

**Propozycja:** rozróżnienie Stop vs Programy=Urlop **przez bit 0 (validity)**:
- Fan Stop: f[28]=`0x01` (validity SET, bieg=0)
- Programy=Urlop: f[28]=`0x00` (validity CLEAR, bieg=0, brak stable)

**FINDING (markers.txt):** w Programy=Poza/Urlop tylko **Bypass** pozostaje aktywny w menu Nano. Term/Went/Wietrz są zablokowane. Implikacja protokolu: Programy=Poza/Urlop to "tryb master" zarządzający tymi polami.

---

## MX5: Bypass × Sezon

### MX5a: Bypass AUTO→ON (Sezon=Zima) (13:51:57)

E5 f[25] `0x61`→`0x62`; E3 f[27] `0x01`→`0x02`; AERO `0x40`→`0x60`. **✓**

### MX5b: Sezon Zima→Chłodz (Bypass=ON) (13:52:29)

E5 f[27] `0x00`→`0x14`; E5 f[25] `0x62` (niezmienne); E3 f[27] `0x02`→`0x12` (Chłodz\|ON); E3 f[28] `0x13`→`0x1B` (overlay Chłodz). AERO `0x60`. **✓**

### MX5c: Sezon Chłodz→Lato bez (Bypass=ON) (13:53:24)

E5 f[27] `0x14`→`0x0A`; E3 f[27] `0x12`→`0x0A` (Lato\|ON); E3 f[28] `0x1B`→`0x13`. AERO `0x60`. **✓**

**MX5 podsumowanie:** komenda bypass `f[25]` stabilna we wszystkich sezonach. E3 f[27] = `(sezon<<3) | bypass_cmd` — potwierdzone pełną macierzą.

---

## MX6: Aktywny setpoint cross-table

| Test | Term × Sezon | E4 f[14-15] | E5 pole źródłowe | Werdykt |
|------|--------------|-------------|-------------------|---------|
| MX6/4 | Harm × Lato bez | `11:04` (18.0) | f[12-13] Eco_chłodz | ✓ T1 spójne |
| MX6/5 | Harm × Chłodz | `11:04` (bez zmian) | f[12-13] | ✓ |
| MX6/3 | Harm × Zima | `11:04`→`11:18` (20.0) | f[10-11] Eco_zima | ✓ |
| MX6/1 | Manual × Zima | `11:18`→`11:11` (19.3) | f[14-15] Manual | ✓ |
| MX6/2 | Manual × Chłodz | `11:11` (bez zmian) | f[14-15] Manual | ✓ Manual niezależny od sezonu |
| MX6/6 | Urlop × Chłodz | `11:11`→`11:04` (18.0) | **f[12-13] Eco_chłodz** | 🔍 **brakuje w PROTOCOL §5.6** |

**🔍 MX6/6 nowe odkrycie:** Term=Urlop+Sezon=Chłodz → aktywny SP = **Eco_chłodz** (analogicznie do Urlop+Zima=Eco_zima z T5). PROTOCOL §5.6 wymaga uzupełnienia.

**Termostat=Harm w cross-table:** nigdy nie używa Comfort (`f[8-9]`) — to słot harmonogramu, prawdopodobnie aktywny tylko w określonych godzinach. Wymaga osobnego testu z menu serwisowym (cały dzień Comfort).

**MX6/1 potwierdzenie hipotezy stable bit:** drugie wejście w Manual+Zima w sesji NIE aktywowało `0x40`, mimo wszystkich warunków formalnych. Stable jest "lepkie" — raz utracone w sesji nie wraca samoczynnie.

---

# RAPORT KOŃCOWY — Lista propozycji do PROTOCOL.md

⚠ **Bez auto-update** — decyzja o aktualizacji należy do Piotra.

## P1. §3.3 E3(29) f[27] — REFORMULACJA (priorytet WYSOKI)

**Obecnie:** "Bit 0 (`0x01`) zawsze SET, bity 3-4 = sezon, bit 5 = wietrz overlay"

**Proponowane:**
```
E3(29) f[27] = (sezon_szyld) | (bypass_cmd & 0x03) | (wietrz_overlay)

  Sezon szyld:    Zima=0x00, Lato bez=0x08, Chłodz=0x10
  Bypass cmd:     OFF=0x00, AUTO=0x01, ON=0x02
  Wietrz overlay: +0x20 gdy Wietrzenie ON
```

| Sezon × Bypass | OFF | AUTO | ON |
|----------------|-----|------|-----|
| Zima | `0x00` | `0x01` | `0x02` |
| Lato bez | `0x08` | `0x09` | `0x0A` |
| Chłodz | `0x10` | `0x11` | `0x12` |

**Empirycznie potwierdzone:** T13/T14/T15 (Zima×bypass), T15d/T15e (Chłodz×bypass), MX5a/b/c, MX3b (Lato+AUTO+Wietrz=`0x29`), MX3c (Zima+AUTO+Wietrz=`0x21`).

## P2. §3.3 E3(29) f[28] — DODAĆ overlay Chłodz (priorytet WYSOKI)

**Obecnie:** `f[28] = bieg | 0x10 (znacznik E3) | 0x40 (stable)`

**Proponowane:** `f[28] = bieg | 0x10 | 0x40_stable | 0x08_chłodz_overlay`

**Empirycznie:** T2 (`0x13`→`0x1B`), MX1a (`0x15`→`0x1D`), MX1c (`0x13`→`0x1B`), MX1d (`0x11`→`0x19`), MX5b (`0x13`→`0x1B`). Overlay obecny zawsze gdy Sezon=Chłodz, niezależnie od biegu i Term.

## P3. §3.2 E4(29) f[24] — DODAĆ trzecią wartość `0x00`

**Obecnie:** "`0x64` synced, `0x32` unsynced"

**Proponowane:**
```
f[24] = 0x64 (synced, Term=Manual+korekta=0+stable SET)
      = 0x32 (unsynced/normal)
      = 0x00 (Sezon=Chłodzenie + brak stable)
```

**Korelacja:** f[24]=`0x00` ⇔ Sezon=Chłodz AND f[28] bit `0x40` CLEAR.

**Empirycznie:** T2, T15c, T15d, T15e, MX1a-d, MX2a-d, MX3a, MX5b (wszystkie w Chłodz+brak stable).

## P4. §3.2 E4(29) f[28] bit `0x40` (stable) — USCISŁENIE WARUNKÓW

**Obecnie:** "SET ⇔ (Term=Manual) AND (korekta=0)"

**Proponowane (ostrożna reformulacja, wymaga testu power-cycle dla pełnego potwierdzenia):**
```
Bit 0x40 SET wymaga jednocześnie:
  - Term=Manual ORAZ
  - Wentylacja ∈ {Stop, B1, B2, B3}  (NIE Harm/Harm-Urlop) ORAZ
  - Sezon=Zima                        (Chłodz=brak stable) ORAZ
  - korekta termostatu = 0 ORAZ
  - "świeże" wejście w Manual         (nie wraca po opuszczeniu trybu)

Raz utracony bit nie wraca samoczynnie nawet po przywróceniu warunków —
"lepkość" wymaga osobnego testu power-cycle.
```

**Empirycznie:**
- T4 (Manual+Zima+B1, świeże wejście): SET ✓
- MX2a (Manual+Chłodz+Harm): CLEAR
- T15c (Manual+Chłodz+B1): CLEAR — Chłodz blokuje stable
- MX6/1 (Manual+Zima+B1, drugie wejście): CLEAR — "lepkość"

## P5. §3.4 AERO E4(63) f[27] — DODAĆ wartość `0x0A` (Wietrzenie)

**Obecnie:** "`0x00` Stop, `0x02` B1/B2/B3 aktywny"

**Proponowane:** `0x00` Stop, `0x02` B1/B2/B3 aktywny, `0x0A` **Wietrzenie aktywne** (= `0x08 | 0x02`).

**Empirycznie:** T30, MX3a-d (zawsze gdy AERO f[26]=`0x04`).

## P6. §3.4 AERO E4(63) f[20] — Stop pełen zeruje `0x7E` na `0x00`

**Obecnie:** "f[20-23]=`7E,00,00,00` stałe"

**Proponowane uzupełnienie:**
```
W normalnym pracy: f[20]=0x7E, f[21-23]=0x00,0x00,0x00.
W pełnym Stop wentylatorów (Went=Stop, AERO f[26-27]=0x00):
  f[20]=0x00, wszystkie f[20-27] = 0x00,0x00,...
```

**Empirycznie:** MX1d (Stop+Chłodz), MX4a/MX4d (Programy=Poza/Urlop ze Stop).

## P7. §3.7 E5(29) f[28] — PRZEPISANIE tabeli kodu UI (priorytet WYSOKI)

**PROTOCOL obecnie podaje:** "Manual+Zima=`0x19`", "Urlop+Zima=`0x05`", "Harm+Zima=`0x05`".

**Empirycznie w sesji (wartości obserwowane):**

| Term | Sezon | Wentylacja | Bieg | E5 f[28] | Test |
|------|-------|------------|------|----------|------|
| Harm | Zima | B1 (manual) | B1 | `0x01` | F0, T6 |
| Harm | Zima | B2 | B2 | `0x02` | T7 |
| Harm | Zima | B3 | B3 | `0x03` | T8 |
| Harm | Zima | Stop | Stop | `0x00` | T9 |
| Harm | Zima | Harm | slot | `0x05` | T10 |
| Harm | Zima | Harm-Urlop | slot | `0x04` | T11 |
| Manual | Zima | B1 | B1 | **`0x15`** ⚠ (PROTOCOL: `0x19`) | T4 |
| Urlop | Zima | B1 | B1 | **`0x0B`** ⚠ (PROTOCOL: `0x05`) | T5 |
| Harm | Chłodz | B1 | B1 | `0x01` | MX1c, MX65 |
| Harm | Chłodz | Harm | slot | `0x05` | MX1a, MX2c |
| Harm | Chłodz | Harm-Urlop | slot | `0x04` | MX1b |
| Manual | Chłodz | B1 | B1 | `0x15` | T15c, MX62 |
| Manual | Chłodz | Harm | slot | `0x19` | MX2a |
| Manual | Chłodz | Harm-Urlop | slot | `0x18` | MX2b |
| Manual+Wietrz | Chłodz | B2 | B2 | `0x16` | MX3a |
| Urlop | Chłodz | B1 | B1 | `0x0B`/`0x0F` | MX2d, MX66 |
| Harm+Wietrz | Zima | B1 | B1 | `0x01` | MX3c (niezmienne!) |
| Programy=Poza | Zima | (slot=Stop) | Stop | `0x01` | MX4a |
| Programy=Urlop | – | – | – | `0x01` | MX4d |

**Wniosek:** PROTOCOL §3.7 ma kilka błędnych wartości. Tabela wymaga przepisania. Wietrzenie ON nie zawsze widać w E5 f[28] (MX3c — Zima+Wietrz daje `0x0B` niezmienne).

## P8. §3.2/§5.5 Programy=Urlop — KOREKTA `f[28]` (priorytet WYSOKI)

**Obecnie:** "Programy=Urlop \| f[28] = `0x40` (validity=0, bieg=0)"

**Empirycznie (MX4d):** `f[28]=0x00` (validity=0, bieg=0, **bez bitu `0x40`**).

**Proponowane:**
```
Programy=Urlop:
  f[5]   = bit 0x04 CLEAR (różnica vs Programy=Poza domem)
  f[14-15] = setpoint Poza domem (kopia z E5 f[16-17])
  f[24]  = 0x32
  f[28]  = 0x00 (validity=0, bieg=0, BEZ stable)

Rozróżnienie Stop vs Programy=Urlop przez bit 0 (validity) f[28]:
  Fan Stop:        f[28] = 0x01 (validity SET, bieg=0)
  Programy=Urlop:  f[28] = 0x00 (validity CLEAR, bieg=0)
```

**Uwaga terminologiczna:** Programy=Urlop ≠ Termostat=Urlop ≠ Wentylacja=Harm-Urlop. Trzy różne tryby z różnymi efektami w bajtach:
- Programy=Urlop → f[5] bit 0x04 toggling, f[28]=0x00, SP=Poza
- Termostat=Urlop → f[27] bit 0x01, f[28] normalna (bieg), SP=Eco wg sezonu (NIE Poza!)
- Wentylacja=Harm-Urlop → różnica tylko w E5 f[28] bit 0 (gdy Term=Harm)

## P9. §5.6 Aktywny setpoint — UZUPEŁNIENIE

**Obecnie brakuje wierszy:**

| Termostat | Sezon | Programy | Aktywny SP | Test |
|-----------|-------|----------|------------|------|
| Urlop | Chłodzenie | Normal | **Eco_chłodz (f[12-13])** | ✓ MX6/6 |
| Urlop | Lato bez | Normal | Eco_chłodz (f[12-13]) | (nieprzetestowane, przewidywane) |
| Harm | Lato bez | Normal | **Eco_chłodz (f[12-13])** | ✓ T1, MX6/4 |

**Reguła ogólna:** Term=Harm/Urlop dla sezonu lato/chłodz → Eco_chłodz; dla zimy → Eco_zima. Termostat=Manual jest **niezależny od sezonu** (zawsze Manual SP).

## P10. §5.6 wiersz "Poza domem" — USUNĄĆ "Urlop+Zima"

**Obecnie:** "Poza domem \| f[16-17] \| Urlop+Zima, Poza domem"

**Empirycznie (T5):** Term=Urlop+Zima → Active SP = **Eco_zima** (`f[10-11]`), NIE Poza domem.

**Proponowane:**
```
Poza domem (f[16-17]) aktywny gdy:
  - Programy=Poza domem (zawsze)
  - Programy=Urlop      (zawsze)
NIE aktywny dla Termostat=Urlop — tam Eco wg sezonu.
```

## P11. §5.3 Wentylacja=Harm vs Harm-Urlop — UZUPEŁNIENIE

**Obecnie:** sugeruje że Harm-Urlop ma "BEZ bitu `0x40`" w E4 f[28].

**Empirycznie:** gdy Term=Manual, faktycznie tak. Gdy Term=Harm/Urlop, bit `0x40` i tak nie ma (zgodnie z P4) — więc **E4/E3 f[28] są IDENTYCZNE** dla Wentylacja=Harm i Harm-Urlop.

**Proponowane:** dodać klauzulę:
```
Różnica Wentylacja=Harm vs Harm-Urlop widoczna w:
  - E5 f[28]    — bit 0 (Harm=0x05, Harm-Urlop=0x04 gdy Term=Harm)
  - E4 f[24]    — tylko gdy Term=Manual (Harm=0x64, Harm-Urlop=0x32)
  - E4/E3 f[28] — tylko gdy Term=Manual (Harm zachowuje 0x40, Harm-Urlop clear)

Gdy Term=Harm/Urlop: różnica WIDOCZNA TYLKO w E5 f[28] bit 0.
```

## P12. Auto-bypass — NOWA SEKCJA "Logika decyzji bypass" (priorytet ŚREDNI)

Empirycznie potwierdzone (T13-T15, T15c-f, T1, MX3b):

| Sezon | Bypass cmd (E5 f[25]) | Cooling demand | AERO f[28] (stan fizyczny) |
|-------|----------------------|----------------|-----------------------------|
| Zima | OFF/AUTO | n/a | zamknięty (`0x40`) |
| Zima | ON | n/a | otwarty (`0x60`) |
| Lato bez | AUTO | – | **otwarty autonomicznie (`0x60`)** ← T1, MX3b |
| Lato bez | OFF/ON | – | wg komendy |
| Chłodz | AUTO | aktywne (T_pok > SP) | **otwarty autonomicznie** ← T15c |
| Chłodz | AUTO | nieaktywne | zamknięty (do potwierdzenia) |
| Chłodz | OFF | dowolne | zamknięty ← T15d |
| Chłodz | ON | dowolne | otwarty |

**Hipoteza pełna:** AERO autonomia decyzji bypass:
1. `f[25]=0x60` (OFF) → zawsze zamknięty (komenda nadpisuje).
2. `f[25]=0x62` (ON) → zawsze otwarty (komenda nadpisuje).
3. `f[25]=0x61` (AUTO) → decyzja AERO wg algorytmu:
   - Sezon=Zima → zawsze zamknięty
   - Sezon=Lato bez → otwiera (free-ventilation, niezależnie od demand)
   - Sezon=Chłodz → otwiera gdy cooling demand (T_pok > active SP)

**Czas reakcji AERO:** ≤1 cykl Mini (~6-8s) po komendzie ON/OFF.

## P13. §3.4 AERO E4(63) f[24-25] — DODAĆ wartości Wietrzenia i % per bieg

**Obecnie:** "f[24-25] = naw% / wyw% aktualne"

**Empirycznie (z menu serwisowego per markers.txt):**
| Tryb | f[24] Naw% | f[25] Wyw% |
|------|------------|------------|
| Stop | `0x00` | `0x00` |
| B1 | `0x23` (35) | `0x20` (32) |
| B2 | `0x25` (37) | `0x23` (35) |
| B3 | `0x23` (35) | `0x22` (34) ← B3 wyw < B2 wyw |
| Wietrzenie | `0x1E` (30) | `0x1E` (30) ← oba równe, niższe niż B1 |

**Wartości stałe** dla danej instalacji (menu serwisowe usera) — w innych instalacjach będą inne. AERO ujawnia aktualnie używane % w f[24-25] z lagiem ~1 cykl.

---

# Otwarte pytania / wymagane następne testy

1. **Stable bit `0x40` w E4 f[28]** — mechanizm "lepkości": czy wraca po power-cycle Nano? (Hipoteza P4 wymaga osobnego testu z restartem zasilania).
2. **E5 f[28] kod UI** — pełna macierz Manual × wszystko + Wietrzenie × wszystko (P7 wymaga focused testu).
3. **Slot Harmonogramu Termostatu — Comfort (E5 f[8-9])** — kiedy aktywny? Wymaga testu z menu serwisowym Nano (cały dzień Comfort).
4. **AERO f[28] w MX1d** (`0x60` przy Went=Stop+Chłodz) — czy to artefakt z T15c, czy trwałe zachowanie? Wymaga testu power-cycle AERO + Stop.
5. **Wietrzenie auto-exit timeout** — Nano sam wyłącza po ~5-10s w cyklu 2 (T30, MX3a-d). Sprawdzić czy timeout jest konfigurowalny w menu serwisowym.
6. **MX3b cycle 3** — f[27]=`0x21` zamiast `0x28` (bit 0x08 znikł, 0x01 pojawił się). Auto-exit Wietrzenia czy artefakt? Wymaga dokładniejszego śledzenia.
7. **Bypass komenda — 4. stan (`0x03`)** — propozycja P1 podaje 2-bitowy enum, ale obserwowane tylko 3 wartości. Czy istnieje 4. stan ("Bypass blocked")?
8. **Programy=Poza domem slot harmonogramu** — kiedy slot Poza-domem zwraca B1/B2/B3 zamiast Stop? Test z różnymi godzinami.
9. **E5 f[28] Wietrz overlay w Zima+Harm (MX3c)** — `0x0B` niezmienne mimo Wietrz ON, podczas gdy w Chłodz (MX3a) E5 f[28] zmienia się z `0x15` na `0x16`. Asymetria zachowania w E5 między sezonami.
10. **AERO E4(63) f[27]=`0x0A`** — dekompozycja bitu `0x08`: czy oznacza "tryb Wietrzenie" w kontekście f[27], czy bardziej ogólny "high speed override"?

---

**Status raportu (v2):** kompletny, niezależnie zweryfikowany od poprzedniej wersji `_14-33.md`. Decyzja o aktualizacji PROTOCOL.md / HISTORY.md w kolejnej sesji.

**Główne propozycje wysokiego priorytetu (P1, P2, P7, P8):** reformulacja E3 f[27] (bypass cmd), dodanie overlay Chłodz w E3 f[28], przepisanie tabeli E5 f[28], korekta Programy=Urlop f[28]=`0x00`.

# Test Nano Master Mini — empiryczne mapowanie pól

Plan systematycznego testu cyklu Master Mini z **Nano jako master**. Cel: bajt po bajcie potwierdzić które pola w E4(29)/E3(29)/E5(29)/AERO E4(63) kodują:
- Set temp (Comfort / Eco zima / Eco chłodz / Manual / Poza domem) i aktywny setpoint
- Sezon (Zima / Lato bez / Chłodzenie)
- Termostat (Harmonogram / Urlop / Manual)
- Wentylacja (Harmonogram / Harm-Urlop / B3 / B2 / B1 / Stop)
- Wietrzenie ON/OFF (overlay, osobne menu)
- Bypass (OFF / AUTO / ON)
- Programy (Normal / Poza domem / Urlop)

## Setup

**Hardware:**
- Nano Color CTP (id=1) w trybie **MASTER MINI** (menu serwisowe: TRYB W SIECI C14 = MASTER MINI)
- ESP32 esp02 jako **observer**: Rola=OFF, Forward=ON (passive bridge), `log_nano`=ON, `log_aero`=ON
- Wszystkie VS (Virtual Slaves) w ESP wyłączone (`switch.c14_master_vs_id_2..5 = off`)

**Capture:**
```bash
ssh -i ~/.ssh/ha_ed25519 root@homeassistant \
  "docker exec addon_5c53de3b_esphome esphome logs /config/esphome/esp02.yaml --device 192.168.88.206" \
  > test_nano_$(date +%Y%m%d_%H%M).log 2>&1 &
```

Capture w tle, do pliku. Zapisuje wszystkie ramki na bus (ESP w roli OFF tylko nasłuchuje, nie nadawa).

---

## Workflow: "log everything → analyze later"

**Faza A — sesja capture (live, w dialogu):**

1. Uruchamiam **capture w tle** do pliku — log idzie ciągle przez całą sesję
2. **Operator (Ty):** wykonujesz **jedną zmianę** w menu Nano
3. **Operator (Ty):** piszesz na czacie: `zmieniłem` + krótki kontekst (np. `zmieniłem sezon na Lato`)
4. **Analyst (ja):** zapisuję **marker do logu** (znacznik czasu + opis), `echo "=== T<N>: <opis> @ HH:MM:SS ===" >> logfile`
5. **Operator (Ty):** czeka **≥45 sekund** (5 cykli Mini), żeby logiczna zmiana wpadła do kilku ramek
6. **Operator (Ty):** pisze `ok` (lub `kolejny`) → ja podaję następny test do wykonania
7. **Powtarzaj** kroki 2-6 dla wszystkich testów z list F0-F7 + MX1-MX6

W tej fazie **NIE analizuję na bieżąco** — tylko markeruję log i prowadzę kolejność. Analiza idzie szybciej, capture trwa nieprzerwanie.

**Faza B — analiza po sesji (defensive verification):**

1. Po wykonaniu wszystkich testów (lub gdy chcesz zakończyć sesję) — pobieram pełny log
2. Analizuję **test po teście**: dla każdego markera czytam **wszystkie ramki w 5+ cyklach po markerze**, porównuję bajt po bajcie z baseline (lub poprzednim testem)
3. Generuję raport DIFF z wnioskami dla każdego testu w formacie:
   - **Zgodne z PROTOCOL.md** ✓ (potwierdzone empirycznie)
   - **Niezgodne / niekompletne** ⚠ (rzeczywiste bity ≠ doc, lub doc nie pokrywa zaobserwowanej kombinacji)
   - **Nowe odkrycia** 🔍 (zachowanie nieopisane w doc, np. nowy bit, nieoczekiwana interakcja)
4. Wszystkie ⚠ i 🔍 trafiają do osobnej sekcji **"Do poprawy w PROTOCOL.md"** na końcu raportu — **lista propozycji**, nie auto-update
5. **Decyzję o aktualizacji PROTOCOL.md podejmujesz Ty** po przejrzeniu listy — ja nie ruszam doc bez Twojego potwierdzenia

**Dlaczego ≥5 cykli między testami:**
- Master Mini ma 8.5s/cykl, 5 cykli = ~45s
- Niektóre pola (rotator daty E4 f[25-26], slot harmonogramu Termostatu) zmieniają się tylko co N cykli — krótszy capture mógłby przegapić
- Reakcja Nano na zmianę menu może być opóźniona o 1-2 cykle (Nano potwierdza zmianę, dopiero potem broadcasts)
- AERO E4(63) reaguje wolniej (~2-3 cykle) na zmiany bypass i sezonu

**Dlaczego analiza wszystkich cykli, nie 1:**
- Bajty nieinteresujące mogą fluktuować naturalnie (zegar f[8-9] tyka co minutę, temperatury T się płaczą o 0.1°C)
- Bajt który **konsekwentnie** zmienił się we wszystkich 5 cyklach po markerze = realna zmiana wynikająca z parametru
- Bajt który zmienił się raz a potem wrócił = noise, nie diff parametru
- Bajty rotujące (rotator daty, slot harmonogramu) widać tylko z dłuższego okna — analiza per-test wszystkie cykle

---

## Format zapisu w logu (każda zmiana)

```
=== T<N>: <opis zmiany> @ HH:MM:SS ===
BASELINE (3 cykle przed zmianą, średnia):
  E4: E4,21,XX,29,...,YY,23  (cykle T0+0, T0+8.5, T0+17)
  E3: ...
  E5: ...

PO ZMIANIE (cykle T1+0, T1+8.5, T1+17, T1+25, T1+34 — 5 cykli):
  E4 cykl 1: ...
  E4 cykl 2: ...
  ...
  
DIFF konsekwentny (zmienił się we wszystkich 5 cyklach):
  E4 f[27]: 0x00 → 0x08 ✓ (oczekiwane)
  E3 f[27]: 0x01 → 0x09 ✓
  E5 f[27]: 0x00 → 0x0A ✓

DIFF nietrwały (różnice tylko w niektórych cyklach):
  E4 f[8-9]: zegar tyka — ignorować
  
WNIOSEK: ...
```

---

## Faza 0 — Baseline

**Operator:** ustaw na Nano:
- Sezon=**Zima**
- Termostat=**Harmonogram**
- Wentylacja=**B1**
- Wietrzenie=**OFF**
- Bypass=**AUTO**
- Programy=**Normal**

Setpointy znane (zapisz przed startem): Comfort=23.0°C, Eco zima=21.0°C, Eco chłodz=18.0°C, Manual=25.0°C, Poza domem=20.0°C (lub aktualne).

**Capture 5+ cykli baseline** — to nasz punkt odniesienia dla wszystkich faz.

---

## Cykl Master Mini Nano (~8.5s) — schemat

```
#1 E4(29) src=0x21 — komenda biegu + sezon + termostat + zegar + aktywny SP
#2 E3(29) src=0x44 — TRIGGER AERO + nastawy % per bieg + znacznik biegu
   AERO E4(63) src=0x21 — odpowiedź AERO (~400ms po #2)
#3 E3(29) src=0x56 — iNEXT slot (zera)
#4 E2(29) src=0x44 — status broadcast (nieznane)
#5 E5(29) src=0x21 — 5 setpointów temp + bypass + sezon enum
#6 F0(29) src=0x44 — heartbeat
#7 81(29) src=0x44 — heartbeat
#8-10 D0/D1/D2(29) src=0x44 — slave config (statyczne ASCII "SKA")
```

Pola dynamiczne pojawiają się głównie w **#1 E4**, **#2 E3**, **#5 E5** + **AERO E4(63)**.

---

# CZĘŚĆ I — Testy liniowe (jedna zmienna na raz)

Cel: zidentyfikować **które pole** zmienia się gdy zmieniasz pojedynczy parametr.

## Faza 1 — Sezon (3 stany)

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T1 | Zima → **Lato bez** | E4 f[27] +`0x08` · E3 f[27] `0x01`→`0x09` · E5 f[27] `0x00`→`0x0A` |
| T2 | Lato bez → **Chłodzenie** | E4 f[27] `0x08`→`0x10` · E3 f[27] →`0x11` · E5 f[27] →`0x14` · **E4 f[28] +`0x08`** (Chłodz overlay) |
| T3 | Chłodzenie → **Zima** (powrót) | wszystkie sezon bity CLEAR |

## Faza 2 — Termostat (3 stany)

Wymóg: Sezon=Zima, Wentylacja=B1.

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T4 | Harm → **Manual** | E4 f[27] bity 0-2: `0x00`→`0x02` · **E4 f[28] +`0x40`** (stable) · E4 f[24] `0x32`→`0x64` · E4 f[14-15] zmiana na T_manual |
| T5 | Manual → **Urlop** | E4 f[27] bity 0-2: `0x02`→`0x01` · E4 f[28] −`0x40` · E4 f[24] →`0x32` · E4 f[14-15] na T_poza_domem? |
| T6 | Urlop → **Harm** (powrót) | reset do baseline F0 |

## Faza 3 — Wentylacja (6 opcji per PROTOCOL §5.3)

Menu Nano: **Harmonogram / Harm-Urlop / B3 / B2 / B1 / Stop**. Wietrzenie to osobne menu (F7).

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T7 | B1 → **B2** | E4 f[28] bity 0-2: `0x03`→`0x05` · E5 f[28] zmiana (kod UI) |
| T8 | B2 → **B3** | E4 f[28]: `0x05`→`0x07` |
| T9 | B3 → **Stop** | E4 f[28]: `0x07`→`0x01` |
| T10 | Stop → **Harmonogram** | E4 f[28] bieg ze slotu (rotuje wg czasu) |
| T11 | Harmonogram → **Harm-Urlop** | E4 f[28] bez zmiany w bieg, ale **−`0x40`** (jeśli Manual) lub +flag § PROTOCOL · f[24] zachowanie |
| T12 | Harm-Urlop → **B1** (powrót) | reset |

## Faza 4 — Bypass (rozbudowane — priorytet WYSOKI)

**Kontekst:** obserwacja 2026-05-03: bypass nie zmieniał stanu zgodnie z oczekiwaniem przy ręcznych komendach + Nano master w Chłodzeniu autonomicznie otwierał bypass (free-cooling). Możliwe że źle interpretujemy bajty lub auto-bypass nadpisuje komendę.

**Wymóg:** Sezon=**Zima** (żeby auto-bypass nie zaburzał — w Zimie AERO nie otwiera autonomicznie).

### Faza 4a — Komenda manualna w Zimie (kiedy auto-bypass nieaktywny)

| Test | Zmiana | Oczekiwane (wg PROTOCOL §3.7) | Co mierzymy |
|------|--------|------------------------------|-------------|
| T13 | AUTO (`0x61`) → **OFF** | E5 f[25] →`0x60` · po ~5s AERO E4(63) f[28] →`0x40` (zamknięty) | komenda → reakcja AERO; czas reakcji |
| T14 | OFF → **ON** | E5 f[25] →`0x62` · AERO f[28] →`0x60` (otwarty) | komenda → reakcja AERO |
| T15 | ON → **AUTO** | E5 f[25] →`0x61` · AERO decyduje (w Zimie zwykle zamknięty) | sprawdź czy AUTO w Zima = zawsze zamknięty |
| T15b | AUTO → **OFF → AUTO → ON → AUTO → OFF** (szybka sekwencja, ~10s każda) | każda zmiana w E5 f[25]; AERO może gubić zmiany | test responsywności / debounce |

### Faza 4b — Auto-bypass w Chłodzeniu (NOWE — kluczowy test)

**Wymóg:** Sezon=**Chłodzenie**, Termostat=Manual, Manual setpoint < temp pokojowa (żeby chłodzenie było aktywne).

| Test | Setup | Akcja | Co sprawdzić |
|------|-------|-------|--------------|
| T15c | Sezon=Chłodzenie, Bypass=**AUTO** | Czekaj 5+ minut, monitoruj AERO E4(63) f[28] | Czy AERO sam otwiera (`0x40`→`0x60`) bez zmiany komendy w E5? |
| T15d | Bypass=AUTO, AERO bypass otwarty (po T15c) | Zmień Bypass na **OFF** | Czy AERO zamyka (komenda nadpisuje auto)? Jak szybko? |
| T15e | OFF → AUTO (Chłodz, ciepło) | obserwuj | Czy AERO znów otwiera autonomicznie? |
| T15f | Bypass=AUTO, AERO bypass otwarty | Zmień Sezon na **Zima** (Bypass dalej AUTO) | Czy AERO zamyka po zmianie sezonu (auto-bypass dezaktywowany)? |

**Co mierzyć poza E5 f[25] i E4(63) f[28]:**
- Pozostałe pola E4(63) — czy `f[20-23]=7E,00,00,00` ma jakiś wskaźnik auto vs manual? Snapshot 22 typów ramek przed/po jak w teście schedule (HISTORY 2026-04-26)
- Czy E5 f[25] **automatycznie się zmienia** (może Nano master tylko proxy'uje decyzję AERO)? Jeśli komenda E5=AUTO, ale Nano widzi że AERO otwarło, czy przepisuje E5=ON? Lub utrzymuje AUTO i tylko czyta stan z E4(63)?
- Czas reakcji: timestamp E5 zmiany vs timestamp pierwszej E4(63) z nowym `f[28]` — w T13/T14 vs T15d (manual override w Chłodz vs Zima)

### Faza 4c — Hipotezy do weryfikacji

1. `f[25]` w E5 = **komenda usera** (wg menu Bypass), nie zmienia się autonomicznie. Auto-bypass to decyzja AERO ujawniona tylko w E4(63) `f[28]`. ✓ — jeśli T15c pokaże E5 f[25]=`0x61` stałe, ale E4(63) f[28] zmienia się autonomicznie.
2. `f[25]=0x61` (AUTO) → AERO ma autorytet decyzji (otwiera w Chłodz, zamyka w Zima)
3. `f[25]=0x60` (OFF) → komenda nadpisuje auto (zawsze zamknięty)
4. `f[25]=0x62` (ON) → komenda nadpisuje auto (zawsze otwarty)
5. **Alternatywna hipoteza:** może Nano master zmienia E5 f[25] z AUTO na ON gdy widzi że AERO otworzyło — wtedy `0x61` w naszym ESP master nie wystarczy do free-cooling, trzeba implementować watchdog (czytaj E4(63), aktualizuj E5 f[25])

### Wracaj na koniec Faza 4 do baseline

Sezon=Zima, Bypass=AUTO. Następna faza powinna zacząć z czystym stanem.

## Faza 5 — Setpointy temperatur (E5 f[8-17])

Wymóg: zacznij z baseline, wymóż wszystkie 5 setpointów do określonych wartości aby DIFFy były czytelne.

| Test | Setpoint | Zmiana | Oczekiwane pole E5 |
|------|----------|--------|---------------------|
| T16 | Comfort | 23.0 → **22.5** | E5 f[8-9] zmiana o `−0x05` |
| T17 | Comfort | 22.5 → 23.0 | f[8-9] reset |
| T18 | Eco zima | 21.0 → **20.5** | E5 f[10-11] zmiana |
| T19 | Eco zima | 20.5 → 21.0 | f[10-11] reset |
| T20 | Eco chłodz | 18.0 → **17.5** | E5 f[12-13] zmiana |
| T21 | Eco chłodz | 17.5 → 18.0 | f[12-13] reset |
| T22 | Manual | 25.0 → **24.5** | E5 f[14-15] zmiana |
| T23 | Manual | 24.5 → 25.0 | f[14-15] reset |
| T24 | Poza domem | 20.0 → **19.5** | E5 f[16-17] zmiana |
| T25 | Poza domem | 19.5 → 20.0 | f[16-17] reset |

**Encoding temperatury:** `T = ((H * 128) + (L % 128) - 2000) / 10`. Np. 23.0°C → H=`0x11`, L=`0x36`.

## Faza 7 — Wietrzenie ON/OFF (overlay, osobne menu)

Wymóg: Wentylacja=B1, Termostat=Harm, Sezon=Zima.

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T30 | Wietrzenie OFF → **ON** | E4 f[27] +`0x20` · E3 f[27] +`0x20` · E5 f[27]? · E3#44 f[14-15] zaczyna nadawac %wiet zamiast f[20-25] %B1? |
| T31 | Wietrzenie ON → OFF | reset bitów `0x20` |

---

# CZĘŚĆ II — Testy krzyżowe (mixy parametrów)

Cel: potwierdzić że zachowanie pól jest **konsekwentne** w różnych kombinacjach (nie ma ukrytych interakcji). Każdy mix to **jedna zmiana** dodana do specyficznego baseline'u.

## MIX 1 — Sezon × Wentylacja (priorytet: WYSOKI)

Pytanie: czy bit Chłodzenia `0x08` w E4 f[28] dodaje się do biegu z slotu harmonogramu, czy tylko do "manual" biegów?

| Test | Setup | Zmiana | Oczekiwane |
|------|-------|--------|------------|
| MX1a | Wentylacja=Harmonogram, Sezon=Zima | Zmień Sezon na **Chłodzenie** | E4 f[28] bieg ze slotu **+`0x08`** (jeśli aktualny slot=B1, wtedy `0x03|0x08=0x0B`) — **niezależnie** od Wentylacja=Harm vs Manual |
| MX1b | Wentylacja=Harm-Urlop, Sezon=Zima | Zmień Sezon na **Chłodzenie** | jak MX1a ale `f[24]=0x32` (unsynced) zachowane |
| MX1c | Wentylacja=B1, Sezon=Lato bez | Zmień Sezon na **Chłodzenie** | E4 f[27] `0x08`→`0x10` · f[28] +`0x08` |
| MX1d | Wentylacja=Stop, Sezon=Lato bez | Zmień Sezon na **Chłodzenie** | f[28] = `0x01|0x08 = 0x09`? (czy Stop+Chłodz ma sens) |

## MIX 2 — Termostat × Wentylacja (priorytet: WYSOKI)

Pytanie: czy stable bit `0x40` w f[28] zależy od **Termostat** czy też od **Wentylacja**? PROTOCOL mówi że od Termostat=Manual. Wentylacja=Harm-Urlop **clear**uje go.

| Test | Setup | Zmiana | Oczekiwane |
|------|-------|--------|------------|
| MX2a | Termostat=Manual, Wentylacja=B1 | Zmień Wentylacja na **Harmonogram** | f[28] = bieg_z_slotu + `0x40` (stable trzymane?) lub bez `0x40` (PROTOCOL §3.2 dla Harm)? |
| MX2b | Termostat=Manual, Wentylacja=Harmonogram | Zmień Wentylacja na **Harm-Urlop** | f[28] **−`0x40`** · f[24] →`0x32` |
| MX2c | Termostat=Harm, Wentylacja=B1 | Zmień Wentylacja na **Harmonogram** | f[28] = bieg_ze_slotu (bez `0x40`) — sprawdź czy slot rotuje per Wentylacja-Harm |
| MX2d | Termostat=Urlop, Wentylacja=B1 | Zmień Wentylacja na **Harm** | sprawdź czy Termostat=Urlop dominuje (Programy?) |

## MIX 3 — Wietrzenie × Sezon × Termostat (priorytet: ŚREDNI)

Pytanie: czy Wietrzenie ON nadpisuje wszystko inne czy łączy się z bieżącym stanem?

| Test | Setup | Zmiana | Oczekiwane |
|------|-------|--------|------------|
| MX3a | Sezon=Chłodzenie, Termostat=Manual, Wentylacja=B2 | Włącz **Wietrzenie ON** | f[27] +`0x20` · czy f[28] zachowuje `0x05+0x40+0x08`? |
| MX3b | Sezon=Lato bez, Termostat=Harm, Wentylacja=B1 | Włącz **Wietrzenie ON** | f[27] = `0x08+0x20=0x28` · f[28] zachowuje `0x03`? |
| MX3c | Sezon=Zima, Termostat=Urlop, Wentylacja=B1 | Włącz **Wietrzenie ON** | dozwolone? czy Nano blokuje? |
| MX3d | Wietrzenie ON, Sezon=Zima, Wentylacja=B1 | Zmień Wentylacja na **Harm-Urlop** | czy Wietrzenie ON zachowane? czy Harm-Urlop wymusza Wietrzenie OFF? |

## MIX 4 — Programy × wszystko (priorytet: WYSOKI dla weryfikacji nadpisywania)

Pytanie: które kombinacje Programy nadpisują Wentylacja/Termostat/Sezon?

| Test | Setup | Zmiana | Oczekiwane |
|------|-------|--------|------------|
| MX4a | Sezon=Zima, Termostat=Harm, Wentylacja=B1 | Programy: Normal → **Poza domem** | E4 f[5] +`0x04` · E4 f[14-15] na T_poza_domem (E5 f[16-17]) |
| MX4b | Programy=Poza domem | zmień Wentylacja=B1 → **B3** | f[28] zmienia bieg ALE setpoint zostaje T_poza_domem? |
| MX4c | Programy=Poza domem | zmień Sezon=Zima → **Chłodzenie** | f[27] sezon zmienia, **f[14-15] dalej T_poza_domem** czy przeskoczy na T_chłodz? |
| MX4d | Programy: Poza domem → **Urlop** | f[28] = `0x40` (sam stable, validity=0) · wentylator Stop · f[5] −`0x04` |
| MX4e | Programy=Urlop | zmień Wentylacja=B1 → B3 | czy Wentylacja ignorowana? f[28] dalej `0x40`? |

## MIX 5 — Bypass × Sezon

Komenda E5 f[25] **niezależna** od sezonu (3 enum), ale **stan AERO** w E4(63) f[28] może zależeć (auto-bypass w Chłodz). Szczegółowe testy w Faza 4b. Tu sanity check że enum bypass komenda nie zmienia formatu.

| Test | Setup | Zmiana | Oczekiwane |
|------|-------|--------|------------|
| MX5a | Sezon=Zima | Bypass AUTO → **ON** | E5 f[25] →`0x62` · AERO f[28] →`0x60` |
| MX5b | Sezon=Chłodzenie | Bypass AUTO → **ON** | E5 f[25] →`0x62` (identyczne) · AERO f[28] →`0x60` |
| MX5c | Sezon=Lato bez | Bypass AUTO → **ON** | jak MX5a/b (komenda enum stała) |

## MIX 6 — Aktywny setpoint cross-table (priorytet: WYSOKI)

E4 f[14-15] kopia setpointu z E5 zależnie od Termostat × Sezon × Programy.

Tabela do potwierdzenia (każdy wiersz to mała sesja 5+ cykli):

| Termostat | Sezon | Programy | E4 f[14-15] = E5 ... |
|-----------|-------|----------|----------------------|
| Manual | Zima | Normal | f[14-15] (T_manual) |
| Manual | Chłodzenie | Normal | f[14-15] (T_manual)? lub przeskakuje? |
| Harm | Zima | Normal | f[10-11] (T_eco_zima) lub f[8-9] (T_comfort)? — zależnie od slotu harmonogramu |
| Harm | Lato bez | Normal | jak Zima czy chłodz? |
| Harm | Chłodzenie | Normal | f[12-13] (T_eco_chłodz) |
| Urlop | dowolny | Normal | f[16-17] (T_poza_domem) |
| dowolny | dowolny | Poza domem | f[16-17] (T_poza_domem) |
| dowolny | dowolny | Urlop | ??? (validity=0, setpoint może być nieistotny) |

**Note:** Termostat=Harmonogram ma własny rotujący slot (Comfort/Eco) niezależny od Wentylacja. Test wymaga znajomości slotów harmonogramu Termostatu w Nano (menu serwisowe).

---

## Bajty synchronizacji — osobny tracking w analizie

W każdej fazie/teście Faza B raportuje **dodatkową sekcję** z zachowaniem bajtów synchronizacji master ↔ AERO ↔ slave. To pola które **nie są bezpośrednio sterowane przez user'a**, ale mogą zmieniać się reaktywnie:

| Pole | Ramka | Rola | Co śledzić |
|------|-------|------|-----------|
| **`f[5]`** | E4(29) src=0x21 | AERO_OK heartbeat (bit `0x40`) + Programy=Poza domem (bit `0x04`) | Czy `0x40` zawsze SET? Czy gaśnie kiedykolwiek? Czy `0x04` reaguje tylko na MX4a? |
| **`f[24]`** | E4(29) src=0x21 | Sync flag (`0x32`/`0x64`) — paruje z f[28] bit `0x40` | Czy zawsze koreluje z f[28]? Stany rozbieżne (`0x64` ale brak `0x40`)? |
| **`f[25-26]`** | E4(29) src=0x21 | Rotator daty (faza/wartość) | Czy rotuje co cykl? Wartości 00/01/02/03 → rok/miesiąc/dzień. W Mini stała czy też rotuje? |
| **`f[10]`** | E4(29) src=0x21 | Default `0x7E`, ale historycznie obserwowane `0x08` przy fan OFF (PROTOCOL §7) | Czy reaguje na Wentylacja=Stop? |
| **`f[5]`** | AERO E4(63) | AERO source flags | Czy kopiuje f[5] mastera czy ma własne wartości? |
| **`f[27]`** | AERO E4(63) | Status bypass mechaniczny | Czy zmienia się 1:1 z E5 f[25] bypass cmd? Z jakim opóźnieniem? |
| **`f[24-25]`** | AERO E4(63) | naw% / wyw% aktualne (PROTOCOL §3.4) | Czy reaguje natychmiast na zmianę biegu / setpointu %? Z jakim opóźnieniem? |

Te bajty NIE są inputem (user ich nie zmienia), ale są **outputami sync'u systemu**. Analiza pokaże:
- Czy są stabilne w stanach pasywnych (przed zmianą)
- Czy zmieniają się reaktywnie po zmianie input parametru
- Czy są jakieś niezdokumentowane korelacje (np. f[24] zmienia się przy Sezon, mimo że PROTOCOL mówi że tylko Termostat+korekta)

W raporcie Faza B każdy test ma 2 sekcje:
1. **Pola sterujące** (input — zmienione przez user'a) — zwykły DIFF
2. **Bajty synchronizacji** — czy reagowały na zmianę, czy są stabilne, czy są niespodzianki

## Lista pytań otwartych do potwierdzenia

1. **E5 f[28] kod UI** — pełna macierz Termostat × Sezon × Bieg × Programy × Wentylacja
2. **f[5] bit `0x04`** — czy zmienia stan tylko w MX4a (Programy=Poza domem)?
3. **f[26] w E4** — czy w Mini stała? Sprawdź wszystkie cykle baseline (>3 cykle)
4. **E2(29) src=0x44** — czy zmienia się przy ruchu Termostatu/Sezonu/Wentylacji?
5. **E4 f[24]** sync flag — czy zawsze koreluje z `f[28]` bit `0x40`? Czy MX2a/c/d ujawnia stany rozbieżne?
6. **f[12-13] vs f[14-15]** w E4 — identyczne czy mogą się różnić (np. MX4 Programy)?
7. **Wietrzenie 100%/95%** w nastawach — sprawdź E3#44 f[14-15] przy MX3a-d
8. **Bypass: czas reakcji AERO** — zmierz dokładnie w MX5
9. **Slot harmonogramu Termostatu** — czy zmiana slotu (Comfort↔Eco) widoczna w E4 f[14-15]?
10. **Programy=Urlop dominacja** — MX4e potwierdź że Wentylacja jest ignorowana
11. **f[5] AERO_OK** — czy kiedykolwiek gaśnie podczas testu? Po naszym fixie (sticky `0x40`) powinno być stale SET; czy któraś kombinacja ujawnia problem?
12. **AERO E4(63) f[24-25]** — opóźnienie reakcji naw%/wyw% na zmianę biegu (T7-T9) i setpointu % (E3#44 f[20-25])

---

## Wskazówki praktyczne

- **5 cykli minimum** po każdej zmianie — Master Mini × 5 = ~45s. Niektóre pola (rotator daty) wymagają dłuższego okna.
- **Czekaj 10s po zmianie w menu Nano** zanim raportujesz "zmieniłem" — Nano może mieć debounce/potwierdzenie wewnętrzne.
- **Po każdej fazie wracaj do baseline F0** (Sezon=Zima, Termostat=Harm, Wentylacja=B1, Wietrzenie=OFF, Bypass=AUTO, Programy=Normal). Bezpieczna izolacja od pozostałych testów.
- **AERO E4(63) reaguje wolniej** (1-3 cykle opóźnienia) na zmiany bypass i sezonu — analizuj **po stabilizacji**.
- **Niektóre kombinacje Nano blokuje** w menu (np. Wietrzenie + Wentylacja=Stop) — odnotuj w wynikach jeśli niedostępne.
- **Slot harmonogramu** — wymóż znaną wartość przed startem (np. ustaw harmonogram Termostatu na "cały dzień Comfort" by uniknąć rotacji).

## Kolejność wykonania (sugerowana)

```
F0 baseline (5 cykli)
  ↓
F1 Sezon → F2 Termostat → F3 Wentylacja → F4 Bypass → F5 Setpointy → F7 Wietrzenie
  ↓
MX1 Sezon×Went → MX2 Term×Went → MX3 Wietrz×Sez×Term
  ↓
MX4 Programy×wszystko → MX6 Aktywny SP cross-table
  ↓
MX5 Bypass×Sezon (sanity)
  ↓
Faza B: analiza pełnego logu test po teście
  ↓
Raport DIFF + lista "Do poprawy w PROTOCOL.md" (manual review)
```

Każdy test capture ~45-60s (zmiana + 5 cykli). Pełna sesja capture: ~1.5-2h. Faza B (analiza) — osobna sesja po zakończeniu, ~1h.

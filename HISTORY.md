# Historia debugowania C14 / ESP

Zapisane bugi, fałszywe tropy i lekcje z drogi. Dla bieżącej dokumentacji protokołu → [PROTOCOL.md](PROTOCOL.md).

## Wietrzenie z ESP-master — diagnostyka (2026-05-12 wieczór)

**Setup:** ESP=Master, Nano=Slave id=2 (Faza A4 testu Nano Slave Sync). Cel: weryfikacja Wietrzenia w każdym sezonie.

**Stan początkowy:** Wietrzenie ON w ESP → AERO milczy we wszystkich sezonach.

### Fix #1: bugfix #14 E3(29) zsynchronizowana z #2

Druga ramka E3 trigger (#14, tylko w Master Full) miała **starą logikę stable bit `0x40`** (Manual+Zima only), pominiętą przy fixie z commit `8c0a7ea` (który usunął stable z #2). W Master Mini #14 nie leciało, więc bug nie był widoczny — ujawniłby się przy Master Full+Manual+Zima.

**Fix:** #14 lambda przepisana 1:1 z #2 (bez stable bit, z obsługą Programy=Urlop/Poza domem).

### Fix #2: f[24] sync flag warunkowy per sezon

**Empiria z log 1228 (Nano-master, 560 ramek E4):**
- Sezon=**Chłodz** → Nano ZAWSZE wysyłał `f[24]=0x00` (nie tylko w Wietrz)
- Sezon=Zima/Lato bez → Nano `f[24]=0x32` baseline, `0x64` tylko w Manual+B1/B2/B3+Normal (~5% ramek, "trusted master" z fabrycznym sparingiem)

**ESP poprzednio:** hardcoded `f[24]=0x32` zawsze (per fix 2026-05-11 wieczór). To było bezpieczne ale nie matchowało Nano w Chłodz.

**Fix:** `f[24] = (sezon == Chłodz) ? 0x00 : 0x32`. Reverted previous "always 0x32" approach. ESP nadal nie wysyła `0x64` (patrz Test #3 niżej).

### Odkrycie #1: AERO waliduje % wietrzenia (E3 f[14-15])

**Wzór z testu manualnego:**

| wyw | naw | AERO |
|-----|-----|------|
| 30 | 30 | ✓ |
| 33 | 30 | ✓ |
| 30 | 33 | ✓ |
| 33 | 33 | ✗ silent |
| 32 | 32 | ✓ |

AERO ma cache % wietrzenia z poprzednich Nano sesji (30/30). ESP może zmieniać **jeden parametr na raz** — wtedy AERO akceptuje. Zmiana obu jednocześnie → odrzut. Hipoteza: rate-limited trust mechanism (analogicznie do bit `0x40`).

**Konsekwencja:** ESP z UI HA defaultowo wysyłał 33/33% → milczenie w każdym sezonie. Po zmianie na 30/30 → Zima i Lato bez działają. Chłodz wciąż silent.

### Odkrycie #2: zmiana biegu B1→B2 z aktywnym Wietrz wybija AERO

Test: Lato bez+Wietrz+B1+32/32 działa, zmiana biegu na B2 (Wietrz wciąż ON) → AERO milknie. Auto-toggle Wietrz off→on nie pomaga (user empirycznie sprawdził).

Hipoteza: każda zmiana parametru (sezon, bieg, oba %) podczas aktywnego Wietrz traktowana przez AERO jako "untrusted update". Rate-limit na max 1 zmiana per cykl.

### Odkrycie #3: E5 f[28] — kod UI bieg × term × sezon (nieudokumentowany w PROTOCOL §3.7)

Analiza 545 ramek E5 z log 1228 ujawniła **14 unikalnych wartości f[28]** (PROTOCOL podaje tylko proste 0/1/2/3).

**Pełna lista (f[27]|f[28] z log 1228):**

| Sezon (f[27]) | f[28] obserwowane |
|---------------|-------------------|
| `0x00` Zima | `0x00`, `0x01`, `0x02`, `0x03`, `0x04`, `0x05`, `0x0B`, `0x0E`, `0x15`, `0x16` |
| `0x0A` Lato bez | `0x00`, `0x01`, `0x16` |
| `0x14` Chłodz | `0x00`, `0x01`, `0x04`, `0x05`, `0x0B`, `0x14`, `0x15`, `0x16`, `0x18`, `0x19` |

**Dekodowanie bitów:**

| Bit | Maska | Znaczenie |
|-----|-------|-----------|
| 0-1 | `0x03` | bieg (`00`=Stop, `01`=B1, `10`=B2, `11`=B3) |
| 2 | `0x04` | overlay Termostat=Manual |
| 3 | `0x08` | ? (występuje w `0x0B`/`0x0E`/`0x18`/`0x19` — może Wentylacja=Harm-Urlop?) |
| 4 | `0x10` | overlay Sezon=Chłodz UI |

**Wzór dla Manual+Chłodz:**
- B1 → `0x15` (`0x10|0x04|0x01`)
- B2 → `0x16` (`0x10|0x04|0x02`)
- B3 → `0x17` (`0x10|0x04|0x03`)

**Wzór dla Harm+Chłodz:** prosty bieg `0x01`/`0x02`/`0x03` — bez overlay.

**Status:** ESP w [esp02.yaml:639](esp02.yaml:639) wysyła zawsze prosty bieg `0x00`-`0x03`. Próbny fix (Manual+Chłodz → `0x14|bieg`) **nie odblokował** Chłodz+Wietrz (revert). Pozostaje do dalszej analizy — bit 3 nieznany, pełna macierz term×sezon×wentylacja niezweryfikowana.

**Note 2026-05-12:** kod NIE jest dla slave Nano (slave nie wyświetla nic o biegach — potwierdzone empirycznie przez Piotra). Co to za "UI code" — niejasne. Może wewnętrzny stan AERO, master EEPROM tracking, albo artefakt historyczny.

### Odkrycie #4: % per bieg w E3 f[20-25] — ESP ≠ Nano

W całej sesji Nano log 1228 % per bieg były stałe (Nano zawsze nadawał te same wartości):

| Pole | Nano (log 1228) | ESP (current UI) |
|------|------------------|-------------------|
| f[20] wyw B1 | `0x20` (32%) | `0x1E` (30%) |
| f[21] wyw B2 | `0x23` (35%) | `0x1F` (31%) |
| f[22] wyw B3 | `0x22` (34%) | `0x20` (32%) |
| f[23] naw B1 | `0x23` (35%) | `0x1E` (30%) |
| f[24] naw B2 | `0x25` (37%) | `0x1F` (31%) |
| f[25] naw B3 | `0x23` (35%) | `0x20` (32%) |

**Status:** w Zima/Lato bez+Wietrz różnica nie wpływa (AERO odpowiada), ale **potencjalnie powiązane z Chłodz+Wietrz silent** lub z walidacją per-bieg (analogicznie do % wietrzenia, max 1 zmiana per cykl).

**Do sprawdzenia w następnej sesji:** ustawić w UI HA wartości Nano (32/35/34 wyw, 35/37/35 naw), retest Chłodz+Wietrz. Jeśli zacznie działać → AERO ma cache per-bieg podobnie do cache wietrzenia. Jeśli nie → różnica jest neutralna.

### Test #3: replikacja Nano "trusted master" wzoru w EXACT Manual+Zima — OBALONA

**Hipoteza usera:** może ESP powinien wysyłać `f[24]=0x64` + `f[28]|0x40` ale **tylko w wąskim wzorze Nano** (Manual+Zima+B1/B2/B3+Normal), nie zawsze. Może AERO akceptuje "trusted" przy spełnieniu dokładnego wzorca.

**Test:** ESP nadawał `f[24]=0x64`, `f[27]=0x02`, `f[28]=0x43` (E4) i `0x53` (E3) w Manual+Zima+B1+Normal. **Bytewise identyczne** z Nano log 1228 12:57:48.

**Wynik:** **AERO milknie natychmiast.** Po rewercie do `f[24]=0x32` bez stable bit — AERO wrócił do odpowiadania w ciągu cyklu.

**Wniosek:** factory pairing nie jest "right moment" zależny — jest binarne. AERO odrzuca `0x64+0x40` od ESP niezależnie od kontekstu/wzoru/sezonu. Potwierdza HISTORY 2026-05-11 wieczór: ESP musi pozostać "untrusted master" (`f[24]∈{0x00,0x32}`, brak stable bit) na zawsze.

### Status końcowy 2026-05-12

| Sezon | Wietrz | Nano | ESP |
|-------|--------|------|-----|
| Zima | OFF | ✓ | ✓ |
| Zima | ON | ✓ | ✓ |
| Lato bez | OFF | ✓ | ✓ |
| Lato bez | ON | ✓ | ✓ (po fix %=30/30) |
| Chłodz | OFF | ✓ | ✓ |
| Chłodz | ON | ✓ | **✗ wciąż silent** |

**Otwarte:** Chłodz+Wietrz milczy mimo bytewise-identycznych ramek (po fix #1+#2). To NIE encoding ani sync flag — wszystkie stałe header pasują, f[27]/f[28] pasują, f[24]=0x00 jak Nano. Hipotezy do późniejszej eksploracji: rate-limit % cache per sezon (Chłodz może wymagać innych wartości niż 30/30), interakcja z setpointami w E5, sticky stan AERO po wcześniejszych nieudanych próbach.

### Pełna analiza ramek

`tests/2026-05-10_nano_master_mini/Analiza_ramek_2026-05-12.md` — unique values per byte position w E4 #1 i E3 #2 z całego log 1228, szczegóły f[24]=0x64 occurrences.

---

## Bit 0x40 to "trusted master" assertion, NIE "stable config" (2026-05-11 wieczór)

**Drugie odkrycie krytyczne tego dnia** — kontynuacja "AERO TX off" debugowania.

**Objaw:** Po rannym fixie (stable bit warunkowo: Manual+Zima only) AERO odpowiadał w Lato bez i Chłodzeniu. ALE po zmianie Sezon na Zima (gdy ESP zaczynał wysyłać `f[28]=0x43/0x45` stable+B1/B2, plus `f[24]=0x64` SYNCED) — AERO natychmiast milkł. Testowane B1, B2 — oba milkły.

**Diagnostyka:** Sprawdzenie wczorajszego logu `log_esp02_202605101228.log` ujawniło że Nano w 12:45:46-55 wysyłał **dokładnie te same ramki** (Manual+Zima+B2+stable, `f[28]=0x45`, `f[24]=0x64`) — i AERO **odpowiadał** non-stop. Identyczne bajty f[3]/f[5]/f[24]/f[27]/f[28] — ale Nano dostaje odpowiedź, ESP nie.

**Wniosek:** Bit `0x40` w f[28] + `f[24]=0x64` (synced flag) wymagają **fabrycznego pairingu/handshake** z AERO który Nano-master ma a ESP-master nie. To NIE "stable config" jak myśleliśmy (PROTOCOL §3.2 i §3.3) — to **"Trusted Master" assertion**:
- Nano: zainstalowany razem z AERO, ma sparowanie → AERO ufa bit 0x40 → odpowiada
- ESP: dodany "po fakcie", brak sparowania → AERO traktuje bit 0x40 jako naruszenie autorytetu → service mode TX off

**Fix (commit po sesji):** ESP-master NIGDY nie wysyła:
- bit `f[28] 0x40` (E4 i E3 — usunięte warunkowe ustawianie)
- `f[24]=0x64` (zawsze `0x32` — unsynced)

ESP nadaje minimum potrzebne do działania (bieg + sezon + setpointy + bypass cmd). AERO toleruje "unsynced master" stan na wszystkich sezonach.

**Empirycznie potwierdzone (2026-05-11 23:37):** ESP w Manual+Zima+B1 wysyła `f[28]=0x03`, `f[24]=0x32` — AERO odpowiada non-stop. Sezon Lato bez/Chłodz/Zima — wszystkie działają.

**Hipotezy dlaczego AERO różnicuje Nano vs ESP** (do późniejszej inwestygacji):
1. Timing/jitter ESP32 vs Nano kwarc
2. Brak sekwencji boot handshake (AERO sparowany z Nano przy instalacji)
3. Rotator daty ESP zaczyna od `f[25]=0x00` po reboot — Nano nigdy nie reboot'uje
4. Inny bajt którego nie zauważyliśmy (D0-D5, E2, heartbeats)

**Konsekwencje PROTOCOL.md §3.2 / §3.3:**
- Bit `0x40` należy reinterpretować — to NIE "stable config" lecz **"Trusted Master flag"**
- `f[24]=0x64` to NIE "synced state" lecz **"fresh AERO heartbeat / trusted master mode"**
- ESP-master implementacja MUSI używać tylko `f[24]=0x32` i `f[28]` bez `0x40`
- Nano-master jako "fabrycznie sparowany" ma right do tych flag — opis pozostaje OK dla Nano

**Funkcjonalność po fixie:**
- ✅ Komendy biegu — działają
- ✅ Bypass (OFF/AUTO/ON) — działają
- ✅ Programy (Normal/Poza domem/Urlop) — działają
- ✅ Cross-table active SP (Term × Sezon × Programy) — działa
- ✅ Telemetria AERO (T.Czerpnia, T.Nawiew, T.Wyrzut, T.Wywiew, %, bypass status) — działa
- ⚠ ESP-master działa w trybie "untrusted master" — wszystkie funkcje OK, brak `synced` state w protokole (nie wpływa na działanie)

---

## AERO TX off (service mode) — błędna wymuszone f[28] |= 0x40 zawsze (2026-05-11)

**Objaw:** AERO przez >24h nie nadawał odpowiedzi E4(63) na E3(29)_44 trigger. **RX działał** (komendy biegu wykonywał fizycznie, zmieniał obroty wentylatorów), ale **TX zablokowany** — `<<< AERO E4(63)` nie pojawiało się w logu. Power-cycle AERO + zmiana parametrów + 24h ciągłej komunikacji ESP master nie pomagały. Nano w roli slave id=2 odpowiadał normalnie na AA wake-up — czyli bus elektrycznie działał. Tylko AERO milczał.

**Diagnostyka:** Wstępna hipoteza pinningu po `f[3]` obalona (zmiana ID ESP 1→2 nie obudziła AERO). Hipoteza "kolizji" obalona (zero fragmentów RX = AERO nic nie nadawał, nie kwestia zniekształcenia). Hipoteza "service mode wymaga stable bit zawsze" (z HISTORY 2026-04-28) doprowadziła do **odwrotnego** błędu — wymuszania `f[28] |= 0x40` we wszystkich warunkach.

**Root cause (znaleziony przez porównanie log Nano-master z poprzedniego dnia):**

Z log_esp02_202605101228.log 12:28-12:36 (Nano-master z Manual+Lato bez+B2):
```
E4: ...,14,32,02,05,0A,05,23  ← f[24]=0x32, f[27]=0x0A, f[28]=0x05 (BEZ stable!)
E3: ...,20,09,15,23           ← f[27]=0x09, f[28]=0x15 (BEZ stable!)
```

I AERO odpowiadał **non-stop** (każdy cykl). Czyli **stable bit `0x40` NIE jest "magic key" wymagany zawsze** — wręcz przeciwnie, jego wymuszanie w stanach gdzie Nano go nie wysyłał (Lato bez, Chłodz, Harm) prowadzi AERO do "service mode" gdzie blokuje TX.

**Fix (commit `95b208e`):** stable bit `0x40` w E4 f[28] i E3 f[28] dodawany **TYLKO** gdy spełnione wszystkie:
- Term=Manual
- Sezon=Zima
- Wentylacja ∈ {Stop, B1, B2, B3} (NIE Harm-Urlop)

Inaczej: `f[28]` BEZ `0x40`, `f[24]=0x32` (unsynced). To replikuje dokładnie zachowanie Nano-master z empirii.

**Weryfikacja:** Po flashu + ustawienie ESP w Sezon=Lato bez+Term=Manual+Went=B2+Bypass=AUTO (identyczny stan jak Nano 12:28 wczoraj) — AERO **natychmiast** zaczął odpowiadać na E3 trigger.

**Lekcje:**
1. **HISTORY 2026-04-28** stwierdzała "Bit 0x40 WYMAGANY do resync AERO ... Master powinien zawsze wysyłać f[28] |= 0x40". To było **uproszczeniem** w stanie pomyłki — w faktycznie AERO toleruje brak `0x40` w trybach gdzie Nano go nie wysyła. PROTOCOL.md §3.3 wymaga korekty.
2. **Wczorajszy fix #3** (Manual+Zima only, z Faza B testu Master Mini) okazał się **poprawny** — moje cofnięcie dziś rano było pomyłką. Empiria > intuicja.
3. **AERO "service mode"** — gdy master przez dłuższy czas wysyła stable bit niezgodnie z konwencją Nano (zawsze SET, nie zależny od trybu), AERO blokuje TX. Stan persistent przez power-cycle. Wybudzanie: master musi wysyłać dokładnie jak Nano (warunkowy stable).

**Status PROTOCOL.md:** §3.3 wymaga korekty uwagi o `0x40 zawsze SET` — fałszywa. Patrz commit obok.

---

## Test Nano Master Mini — systematyczna weryfikacja protokołu (2026-05-10)

**Cel:** systematyczne empiryczne mapowanie pól E4/E3/E5/AERO E4(63) wg planu w `TEST_NANO_MASTER_MINI.md`. Każdy test = 1 zmiana w menu Nano + marker + ≥3 cykle obserwacji. Łącznie ~50 testów (T1-T31 część liniowa + MX1-MX6 krzyżowe).

**Setup:** ESP02 jako passive observer (Rola=OFF, Forward=ON), Nano Color CTP jako Master Mini, AERO 3B. Logi z `esphome logs` capture przez SSH do pliku, markery wstawiane przez `cat >> logfile`.

**Plik raportu:** `FazaB_Analiza_2026-05-10.md` (pełen DIFF + lista propozycji P1-P13).

### Główne odkrycia

**Co potwierdzone (bez zmian PROTOCOL):**
- Sezon enums w E4 f[27] / E3 f[27] sezon-bity / E5 f[27]
- Wentylacja biegi B1/B2/B3/Stop w f[28] mastera
- Bypass enum E5 f[25] (`0x60`/`0x61`/`0x62`) i reakcja AERO E4(63) f[28]
- Wszystkie 5 setpointów temp (T16-T25) — encoding 100% zgodny
- Setpoint cross-table (Term × Sezon × Programy) — generalnie spójna z §5.6
- T15c Faza 4b: hipoteza "auto-bypass w Chłodzeniu = decyzja AERO" potwierdzona

**Korekty / uzupełnienia PROTOCOL.md:**
1. **§3.3 E3 f[27]** — przeformułowane: `(sezon_szyld) | (bypass_cmd 2-bit) | wietrz`. Wcześniejsze "bit 0 zawsze SET" obalone (T13 OFF → bit 0 CLEAR).
2. **§3.3 E3 f[28]** — dodano overlay `+0x08` Chłodzenie (analogicznie do E4 f[28]) — wcześniej nie wymieniony.
3. **§3.2 E4 f[24]** — dodana 3. wartość `0x00` (Sezon=Chłodz + brak stable). Korelacja: f[24]=`0x00` ⇔ Chłodz AND f[28] bit `0x40` CLEAR.
4. **§3.2 E4 f[28] bit `0x40` (stable)** — uściślone warunki: Term=Manual + Wentylacja ∈ {Stop,B1-B3} (NIE Harm/Harm-Urlop) + korekta=0 + Sezon=Zima. **Bit "lepkie"** — raz utracony nie wraca samoczynnie (test power-cycle do zrobienia).
5. **§3.4 AERO E4(63) f[27]** — dodano wartość `0x0A` = Wietrzenie aktywne (`0x08|0x02`).
6. **§3.4 AERO f[20-27]** — w pełnym Stop zerowane (f[20] z `0x7E` na `0x00`).
7. **§3.7 E5 f[28] kod UI** — tabela przepisana, wcześniejsze wartości (Manual+Zima=`0x19`, Urlop+Zima=`0x05`) były niezgodne z empirią (`0x15` i `0x0B`).
8. **§3.2/§5.5 Programy=Urlop** — `f[28]=0x00` (NIE `0x40` jak wcześniej PROTOCOL twierdził). Test MX4d.
9. **§5.6 Termostat=Urlop** — używa Eco wg sezonu (Zima→Eco_zima, Chłodz→Eco_chłodz), NIE Poza domem. Wcześniej PROTOCOL łączył to z Programy=Urlop.
10. **§5.7 Auto-bypass logic** — nowa tabela: AUTO+Lato bez=otwarty, AUTO+Chłodz+cooling_demand=otwarty, AUTO+Zima=zamknięty.
11. **§5.3 Wentylacja=Harm vs Harm-Urlop** — w E4/E3 f[28] **NIEROZRÓŻNIALNE** (oba bieg ze slotu, oba bez `0x40`). Różnica tylko w E5 f[28] (`0x05` vs `0x04`).

### Fałszywe tropy

- **Stable bit `0x40` = "Manual+korekta=0"** — częściowo prawda. Empirycznie wymaga DODATKOWO: Sezon=Zima + Wentylacja manualna (NIE Harm) + "świeży" cykl. Lepkość bita była przegapiona — F0 baseline miał stable=SET mimo Term=Harm (artefakt z poprzedniej sesji), co wprowadzało w błąd.
- **Programy=Urlop f[28]=`0x40`** — błędna hipoteza w PROTOCOL od początku. Empirycznie `f[28]=0x00`.
- **Termostat=Urlop+Zima→Poza domem setpoint** — błędne stwierdzenie w §5.6. Test T5: aktywny SP=Eco_zima.

### Otwarte pytania po teście

Patrz PROTOCOL §7 #16-21:
- Lepkość stable bit (test power-cycle)
- Slot Comfort harmonogramu — kiedy aktywny
- Wietrzenie auto-exit timeout
- AERO E4(63) f[27] bit `0x08` w innych stanach
- MX1d AERO bypass utrzymany w Stop+Chłodz

---

## E3(29)_44 f[27] hardcoded zamiast dynamicznego z g_season (2026-04-28)

**Objaw:** po naprawie f[28] AERO odpowiada, ale **fizyczny Nano slave id=5 nie aktualizuje sezonu na wyświetlaczu** po zmianie z UI ESP master. Wczoraj działało (Sezon=Zima), dziś po zmianie na Lato bez slave ignoruje aktualizację.

**Architektura slave Nano (przypomnienie z commit ba5ff0d):**
- Slave nie ma własnego biegu (AERO reaguje globalnie)
- Display slave pokazuje **sezon** kopiowany z mastera
- Termostat i setpointy slave ma w EEPROM (zarządzanie wyłącznie z Nano)

**Przyczyna:** w `esp02.yaml` lambda E3(29)_44 (oba triggery #2 i #14) miała **hardcoded `f[27]=0x01`** w default vector, **niezależnie od `g_season`**. Per PROTOCOL §3.3 E3 f[27] powinno mieć bity 3-4 dla sezonu (`0x08` Lato, `0x10` Chłodz) plus bit 5 (`0x20`) dla wietrzenia.

E5(29) f[27] był prawidłowo dynamiczny (linia 602-605, mapowanie `0x00`/`0x0A`/`0x14`). E4(29) f[27] też dynamiczny (linia 440-444). **Tylko E3(29)_44 f[27] pozostał statyczny z domyślnego vectora** — przegapione przy implementacji sezonu.

**Dlaczego nie zauważone wcześniej:** default value `0x01` przypadkowo odpowiada Sezon=Zima, więc dopóki user był w Zimie (większość czasu development) ramka była przypadkowo poprawna. Po zmianie na Lato bez (28.04) slave wykrył niezgodność: E4 f[27] bity 3-4 = `0x08` (Lato bez), E3 f[27] = `0x01` (twierdzi Zima). Slave odrzucił aktualizację.

**Fix:** w obu triggerach E3(29)_44:

```cpp
uint8_t v27 = 0x01;
if (id(g_season) == 1) v27 |= 0x08;        // Lato bez
else if (id(g_season) == 2) v27 |= 0x10;   // Chłodzenie
if (id(g_wietrz_on)) v27 |= 0x20;
f[27] = v27;
```

Po flashu slave id=5 zaczął prawidłowo aktualizować sezon na display.

**Lekcja:** każde pole które ma być dynamiczne (zależne od stanu user-controlled) powinno być explicitly ustawiane w lambdzie, nie zostawione na default vector. Statyczny default w `std::vector<uint8_t> f = {...}` jest pułapką gdy user zmieni odpowiednią konfigurację — bug pozostaje ukryty dopóki user nie odejdzie od domyślnego stanu.

## AERO desync — wymóg bitu `0x40` w E3(29)_44 f[28] (2026-04-28)

**Objaw:** ESP master działał stabilnie ~17h od flasha 2026-04-27 22:40 (5200 odpowiedzi AERO E4(63)). Dziś o 15:32 PL counter `g_aero_resp_total` zatrzymał się — AERO przestał odpowiadać mimo że master cykl szedł dalej (`>>>` ramki w logu, zero `<<<`).

**Verification że AERO żyje:** użytkownik bypass'em fizycznie podpiął AERO bezpośrednio do Nano (omijając ESP) — Nano czytał normalnie. Potem wrócił MITM z Nano w trybie master — AERO odpowiedział od pierwszego cyklu (Nano TX → forward ESP → AERO → ESP RX). Jednoznacznie: hardware OK, AERO żyje, problem tylko gdy ESP=master.

**Fałszywe tropy (kolejność diagnozy):**

1. **HW-0519 #1 (uart_aero) padł** — odrzucone testem Nano-master (uart_aero RX odbierał odpowiedź AERO normalnie)
2. **`f[5]=0x40` AERO_OK heartbeat w E4(29)** — wczoraj poprzednia logika `(g_last_aero_rx_ms < 120000) ? 0x40 : 0x00` mogła wpadać w spiralę śmierci (cisza AERO >120s → bit CLEAR → AERO interpretuje "master mnie nie widzi" → milczy dalej). Zmienione na sticky `0x40` zawsze, zgodnie z Nano. Niepotrzebne dla rozwiązania głównego, ale i tak poprawne (Nano też zawsze SET).
3. **Bridge Forward ON + Master ON kolizja** — `RESTORE_DEFAULT_ON` na switchu Forward + master TX na oba UART → potencjalne forward TX z uart_nano echo na uart_aero w oknie odpowiedzi AERO. Wyłączenie Forward nie przywróciło odpowiedzi.
4. **Termostat=Manual+B1 wymagany** — przełączenie z Harm na Manual ustawiło `f[24]=0x64` (synced) i `f[27]=0x02` (Manual) zgodnie z Nano. AERO nadal milczał.
5. **Kolejność cyklu E4 vs E3** — pierwsza analiza Nano logu sugerowała że Nano kończy E4(29) na końcu cyklu (vs ESP który zaczyna). Re-analiza z timestamp'ami pokazała że capture Nano złapał środek cyklu (zaczął od E3#44 = #2), a E4(29) na końcu to #1 NASTĘPNEGO cyklu — kolejność identyczna w obu masterach.

**Root cause:** ESP wysyłał `f[28] = bieg | 0x10` w E3(29)_44 (bez bitu `0x40` stable). Zgodnie z PROTOCOL §3.2 oryginalna konwencja "bit 0x40 SET ⇔ Termostat=Manual AND korekta=0" oznaczała że w trybie Harmonogram master legalnie wysyła `0x13`. Wczoraj `0x13` działało (5200 odpowiedzi). Dziś — nie.

**Hipoteza zachowania AERO:** AERO trzyma wewnętrzny stan "synced z masterem" z timeoutem. Dopóki sync świeży, akceptuje E3#44 z dowolnym `f[28]` zawierającym bieg + znacznik `0x10`. Po dłuższej ciszy/przerwaniu sync (dziś ~13:32 PL ESP coś przerwało, dokładny moment nieznany), AERO przechodzi w stan **wymaga ramki deterministycznej konfiguracji** — `f[28]` z bitem `0x40`. Bez `0x40` AERO ignoruje trigger.

Nano master zawsze wysyła `f[28] |= 0x40` (Nano user trzyma Termostat=Manual, więc warunek z PROTOCOL §3.2 zawsze SET). Stąd Nano nigdy nie spotyka tej pułapki.

**Fix:** w `esp02.yaml` w **obu** triggerach E3#44 (#2 ~linia 535 oraz #14 ~linia 747 dla Master Full):

```cpp
// PRZED:  f[28] = v28 + 0x10;
// PO:     f[28] = v28 | 0x10 | 0x40;  // zawsze stable bit
```

Pierwszy fix dotykał tylko #2 — po flashu AERO odpowiedział na #2 ale w Master Full milczał na #14 (bo tam nadal `+ 0x10` bez `0x40`). Drugi flash naprawił też #14, AERO odpowiada 2× per cykl Full zgodnie z PROTOCOL §2.

**Lekcja:** "konwencja Nano" (bit `0x40` zależny od trybu termostatu) NIE jest tym samym co "wymaganie AERO" (bit `0x40` zawsze). Master implementacja powinna trzymać bit SET niezależnie od logicznego trybu, żeby uniknąć desync śmierci po dłuższej przerwie. Aktualizacja PROTOCOL §3.3 — patrz tabela f[28] z uwagą o bit `0x40`.

**Timeline z HA recorder DB (post-mortem, czas lokalny PL):**

```
15:32:49  C14 Cycles 2600                                ← cykl szedł normalnie
15:32:51  number nawiew_bieg_2 → 37.0 (slider)           ← user zaczyna spam-edycję
15:32:56  number wywiew_bieg_2 → 38.0
15:32:58  C14 AERO Responses 5200                        ← OSTATNIA odpowiedź AERO
15:32:59  number wywiew_bieg_2 → 35.0 (korekta)
15:33:09  C14 Cycles 2601                                ← cykl bez odpowiedzi
15:33:09  bus_naw_b2=37, bus_wyw_b2=35 (z nowego E3#44)
15:33:14  number nawiew_bieg_3 → 45.0 (kolejne korekty)
15:33:46  select wentylacja → "Bieg 2"                   ← zmiana biegu PO zamilknięciu
15:33:55  Bus: Bieg aktualny → "Bieg 2"
... AERO już nie odpowiada
```

Slidery `number.*` mają `set_action: lambda: 'id(g_naw_b2) = x'` — zmieniają tylko globalną, nie wywołują TX ramki. Następny cykl master_cycle wysyła E3#44 z nowymi wartościami w normalnym slocie. Bezpośrednia kolizja TX-podczas-odpowiedzi-AERO wykluczona. Zmiana biegu (B1→B2) nastąpiła **57s PO** zatrzymaniu AERO — konsekwencja, nie przyczyna.

Co konkretnie wytrąciło AERO z sync między cyklem 2600 a 2601 — nieznane. ESPHome nie persystuje device-side logów do pliku, w bazie HA brak anomalii poprzedzających 15:32:58 (T-sensory gładkie, brak rebootów, brak warningów). Ostatnia odpowiedź AERO bajt po bajcie zwykła. Możliwe że AERO ma własny watchdog/timeout który okazjonalnie powoduje przejście w "service state" — wtedy wymóg bitu `0x40` wraca w grę.

**Selektywny silent mode (potwierdzone obserwacją usera):** o 15:33:46 user zmienił bieg w UI na "Bieg 2" — wentylator fizycznie zareagował (zmiana obrotów). Czyli AERO **nadal przyjmował komendy** z E4(29) src=0x21 (RX OK), tylko **przestał odpowiadać** ramką E4(63) na trigger E3(29)_44 (TX off). User nie zorientował się od razu o problemie — komenda biegu działała normalnie, tylko T-sensory i `Nawiew %` zamarzły w HA.

To zachowanie ("RX OK, TX off") dokładnie pasuje do hipotezy że AERO wymaga ramki "deterministycznej konfiguracji" (`f[28]` z bitem `0x40`) żeby **wznowić TX odpowiedzi** — nie jest to disconnect całego protokołu, tylko gating odpowiedzi.

**Trop: setpointy poniżej Nano-min (eksperyment 2026-04-27 23:39-23:40):**

User pamiętał że "zmienił procenty nawiewu poniżej 20%" co Nano normalnie blokuje (min 30%). DB potwierdza eksperyment — ale tylko częściowo:

```
23:39:44  wywiew_bieg_1: 32 → 29        (16s aktywne)
23:39:49  wywiew_bieg_1: 29 → 30
23:40:01  nawiew_bieg_1: 37 → 24        (16s aktywne, NAJNIŻSZA wartość w DB)
23:40:17  nawiew_bieg_1: 24 → 29
23:40:22  nawiew_bieg_1: 29 → 30
```

Najniższa zarejestrowana wartość: **nawiew_b1=24%** (poniżej Nano-min 30, ale powyżej 20). Wartości <20 brak w DB (recorder zapamiętuje pełne stany — jeśli user kliknął np. 15 i szybko cofnął, pewnie został złapany; możliwe że tylko subiektywnie pamięta "<20").

**Important:** te niskie wartości były aktywne tylko **16s każda**. Od 23:40:22 wczoraj do 15:32:58 dziś (~16h) slidery B1 były z powrotem na 30/30, w tym czasie AERO wygenerował **5200 odpowiedzi normalnie**. Bezpośredniej kauzalności "niskie % → AERO stop" więc tu nie ma — AERO zamilkł 16h *po* eksperymencie.

Hipotetyczna delayed reaction (np. "AERO licznik nieprawidłowych setpointów × cykle aż do timeout") — niepotwierdzone, brak dowodów. Otwarte do badania jeśli scenariusz się powtórzy.

**Praktyczna lekcja:** trzymaj slidery `naw_b1` i `wyw_b1` **≥30%** (zgodnie z Nano-min). Niższe wartości technicznie wysyłają się przez RS-485, ale mogą prowadzić do nieprzewidzianych stanów AERO. Niski próg menu serwisowego Nano (30) to prawdopodobnie nie kaprys interfejsu, a fizyczne ograniczenie urządzenia.

**Drugi trop: gwałtowna obniżka wszystkich setpointów B2/B3 (15:32-33 dziś):**

Setpointy B2/B3 były **stabilne 42/42 i 50/50** od 2026-04-26 09:49 (~2 dni bez zmian). 28.04 w oknie 15:32:51-15:33:31 user wprowadził **7 zmian w 40s**:

| Czas | Slider | Zmiana | Δ |
|------|--------|--------|---|
| 15:32:51 | naw_b2 | 42→37 | −5 |
| 15:32:56 | wyw_b2 | 42→38 | −4 |
| **15:32:58** | — | **AERO SILENT** | **2s po zmianie wyw_b2** ⚠ |
| 15:32:59 | wyw_b2 | 38→35 | −3 |
| 15:33:09 | naw_b3 | 50→46 | −4 |
| 15:33:14 | naw_b3 | 46→45 | −1 |
| 15:33:26 | wyw_b3 | 50→41 | −9 |
| 15:33:31 | wyw_b3 | 41→40 | −1 |

**Korelacja czasowa 2s** między zmianą wyw_b2 (15:32:56) a zamilknięciem (15:32:58) jest pojedynczym data-pointem, ale jednoznacznie wskazuje na **scenariusz bardziej prawdopodobny** niż delayed reaction po B1<30 (sprzed 16h):

**Hipoteza:** AERO ma wewnętrzny watchdog "rapid setpoint change". Przy gwałtownej obniżce wielu setpointów w krótkim czasie (w typowym użyciu Nano user-zmiany są powolne — każdy setpoint w menu serwisowym osobno z potwierdzeniami) AERO przechodzi w **safe / service mode**: TX odpowiedzi off, RX komend dalej działa (wentylator nadal reaguje na bieg/bypass). Wyjście z tego stanu — ramka deterministycznej konfiguracji `E3(29)_44 f[28]` z bitem `0x40` — nasz fix, który wymusza ten bit zawsze.

Spójność z obserwacją:
- Stabilne 5200 odpowiedzi przed eksperymentem (wartości niezmienione od 26.04)
- Silent mode aktywuje się **w trakcie spam-zmian** (15:32:58 = 2s po wyw_b2)
- Selektywny silent (RX OK, TX off) — AERO "się obraził" defensively, nie zerwał
- B1 niskie 16h wcześniej (24/29) były **krótkotrwałe** (16s każde) i **pojedyncze** zmiany — AERO toleruje pojedyncze, nie tolerue wielokrotnych w krótkim czasie

To dalej hipoteza, nie dowód — ale spójna ze wszystkimi obserwacjami z DB.

**Praktyczna lekcja #2:** zmiany setpointów rób **powoli** (kilka sekund-minut przerwy między każdym sliderem) ALBO **batch'em** (wszystkie zmiany w UI, potem jedno TX po np. 10s debounce). Aktualnie ESP wysyła zmiany w każdym cyklu master_cycle (~22s) z bieżącymi globalnymi — gdy user spam-edytuje, AERO dostaje multiple drastyczne zmiany pod rząd. Rozważ dodanie debounce w `set_action` slidera (np. delay 5s przed pushem nowej wartości do `g_*`).

## Config push do slave id=2 — Test1+Test2 (2026-04-26 22:41-23:29)

Cel: zweryfikować strukturę ramki E4(29) src=0x2A (config push do slave id=2) — czy bajty są pre-cached w EEPROM mastera, czy generowane on-the-fly z bieżących nastaw.

**Setup:** ESP02 w Rola=Slave, VS id=3 włączony (echo'uje pola mastera), Forward ON. Nano master + Nano slave id=2 (fizyczny) na busie.

**Test1 — kontrola bez zmian nastaw:**

Power-cycle Nano mastera bez zmian w menu. Porównanie 2 config push z odstępem 35 min:

```
22:41:20:  E4,2A,60,29,0D,01,05,28,1C,2A,00,1E,01,17,1E,1E,18,14,00,24,20,21,22,25,24,23,20,01,53,23
23:16:03:  E4,2A,60,29,0D,01,05,28,1C,2A,00,1E,01,17,1E,1E,18,14,00,24,20,21,22,25,24,23,20,01,53,23
```

**Bajt-w-bajt identyczne, włącznie z CRC f[2]=0x60.** Stabilność potwierdzona.

**Test2 — zmiana % naw B1: 37→35 w menu Nano serwisowym:**

```
przed (23:16:03): E4,2A,60,29,0D,01,05,28,1C,2A,00,1E,01,17,1E,1E,18,14,00,24,20,21,22,25,24,23,20,01,53,23
po (23:28:55):    E4,2A,5E,29,0D,01,05,28,1C,2A,00,1E,01,17,1E,1E,18,14,00,24,20,21,22,23,24,23,20,01,53,23
                     ↑↑                                                          ↑↑
                     CRC                                                        f[23]
                     0x60→0x5E                                                  0x25→0x23
```

f[23] zmieniło się 0x25→0x23 (37→35) **dokładnie zgodnie ze zmianą w menu**. CRC liniowy: różnica -2 w f[23] → 0x60-2 = 0x5E ✓. Pozostałe pola niezmienione. **f[4-13] mimo zmian w menu = niezmienne** (firmware constanty).

**Wnioski:**

1. **Config push to żywy snapshot** generowany w momencie wysyłki — nie pre-cached config z EEPROM
2. **f[14-28] = mirror E3(29) src=44 w momencie wysyłki** — slave dostaje aktualne nastawy mastera
3. **f[4-13] = firmware constanty** (`0D,01,05,28,1C,2A,00,1E,01,17`) — niezmienne między sesjami i niezależne od nastaw user. Pewnie identyfikator firmware lub kalibracja AERO której user nie modyfikuje
4. **Stara hipoteza** (PROTOCOL.md historyczny tabela) "f[14-15]=T setpoint" była **błędna** — różnice między sesją 2026-04-23 a obecną wynikały z innych nastaw user, nie z innego znaczenia bajtów

**Lekcja debugowania:** porównywanie pojedynczego config push z różnych sesji bez kontroli nastaw mastera prowadziło do błędnych hipotez (każda zmiana nastawy w menu = inny config push). Test parami (no-change vs change) izolował co jest stałe a co zmienne.

## Side observation: AERO 162s milczenia po power-on Nano (2026-04-26)

Powtarzalne w obu power-cycle Test1/Test2: Nano master po power-on zaczyna nadawać E3(29) src=44 (query do AERO) zaraz, ale AERO przez **162-180 sekund nie odpowiada** — w logu ESP cisza po stronie uart_aero. Dopiero po ~3min pierwsza ramka E4(63) (czasem z desync prefiksem `0x23`).

Hipoteza: power-cycle Nano przerywa bus przez ESP MITM (HW-0519 idą w hi-Z), AERO wykrywa "bus down", przechodzi w resync mode z wewnętrznym watchdogiem ~3min. Wcześniejsze sesje (przed Forward auto-on) prawdopodobnie miały ten sam objaw, ale nie był testowany systematycznie — nieobserwowany bo zmiany nastaw + pomiary robiło się bez reboot Nano.

Wcześniejszy bug w ESP forward (warunki `&& !g_master_on` + `g_forward_on=false` default) został naprawiony 2026-04-26 — auto-on Forward w Rola=Slave + ESP TX zawsze na oba uarty (filozofia "ESP = przezroczysty most").

## Test slave id=2 → id=3 (2026-04-24)

**Setup:** Nano slave jako id=2 (f[3]=0x2A), zmieniono id=3 (f[3]=0x2B) na wyświetlaczu + power cycle. ESP master z `g_slave_ack=true` wysyłający E5(29) f[26]=0x50.

**Obserwacje z ~1h logu:**
- **f[3] = 0x28+id**: potwierdzone (id=2→0x2A, id=3→0x2B).
- **Zmiana id w locie** (bez restartu) — slave od razu zaczął nadawać z nowym f[3], bez 80 boot.
- **Power off/on** wygenerował pojedyncze `80(2B) src=44` (boot announcement) → ESP master wykrył i wysłał config push E4(29) src=0x2B w nast. cyklu. Mechanizm działa dla dowolnego id.
- **Nano slave "się nie ustawił" na id=3** — mimo że nadaje ramki z 2B i dostał config push, wyświetlacz/logika wewnętrzna nie potwierdza pełnej synchronizacji z masterem. Nasz ESP-master prawdopodobnie nie wysyła wszystkiego, czego slave potrzebuje do "zatwierdzenia" swojej konfiguracji (np. brak jakiegoś handshake `D0`/`D1`?).
- **E5(29) f[26]=0x50** stabilne przez cały czas — nie powoduje zmiany zachowania slave (ani gdy id=2, ani id=3).

**Korekta poprzedniej hipotezy (f[7] = id slave):** FAŁSZ. W tej sesji slave z id=2 miał f[7]=0x03 (poprzednio 0x02). f[7] nie jest id — to inna wartość (liczba urządzeń w systemie / wersja konfigu / coś pamiętanego między reboot'ami). id slave jest tylko w f[3].

## Mapowanie f[25-26] = data (2026-04-26)

Wcześniej myśleliśmy że f[25-26] w E4(29) src=0x21 to "rotator" 3-fazowy z hardcoded wartościami (`01,14 / 02,01 / 03,03`). FAKTYCZNIE to **3-fazowa transmisja daty** (rok/miesiąc/dzień).

**Empirycznie zweryfikowane:**
- 3 sty 2020 (Pt) → fazy: `01,14` (rok 20) / `02,01` (sty) / `03,03` (dzień 3)
- 3 sty 2022 (Pn) → `01,16` / `02,01` / `03,03`, f[7]=0x00
- 15 sty 2022 (Sob) → `01,16` / `02,01` / `03,0F`, f[7]=0x05
- 15 maj 2022 → `01,16` / `02,05` / `03,0F`

Konsekwencja: nasza implementacja ESP master miała **hardcoded fałszywą datę 3 sty 2020**. Po fixie wstawia datę z SNTP (ESPHome `t.year/month/day_of_month`).

## f[4] u Nano master = stała 0x0A (2026-04-26)

Wcześniej (z analizy ESP master gdzie wpisaliśmy `f[4]=t.day_of_month`) myśleliśmy że f[4] = day_of_month. FAŁSZ — Nano master ma `f[4]=0x0A` zawsze, niezależnie od daty (sprawdzone na 3 sty 2020 → 15 sty 2022). Hipoteza: model device / wersja protokołu.

## Slave SYNC — od kiedy potwierdzamy (2026-04-26)

Wcześniejsza ramka PROTOCOL.md zawierała stwierdzenie "slave nie sync zegar z mastera" — **błędne**. Wynikało z analizy starych ramek z czasów gdy slave nie zdążył jeszcze zsynchronizować po przełączeniu trybu (np. po power cycle widziano "8:49 pt" mimo faktycznie 23:21 sob).

Faktyczna obserwacja (po fixie ESP master daty + dłuższym oczekiwaniu): slave w pełni odbiera godzinę, dzień tygodnia i datę od mastera w 1-3 cyklach.

Komunikat w menu Nano "godzinę ustawia Nano 1" jest poprawny — master id=1 dostarcza zegar przez f[8-9] + datę przez f[25-26].

## Wnioski (sweep id=2..6 + per-id wake-up):

1. Nasza detekcja boot announcement 80(src=0x44) z f[3]=0x2X + config push E4(29) src=0x2X działa generycznie.
2. Config push E4(29) sam nie wystarcza żeby slave uznał się za zsynchronizowany — brakuje czegoś jeszcze w dialogu master↔slave (do zbadania w kolejnym teście).
3. E5(29) f[26]=0x50 — nic nie wnosi widocznego w zachowaniu slave. Pozostawić jako "obserwowane u prawdziwego mastera", ale NIE kluczowe dla sync.

### ☆ BREAKTHROUGH: per-id wake-up (2026-04-24)

**Odkrycie:** każde id slave'a ma dedykowaną ramkę wake-up w cyklu Master Full:

| Wake-up | Odbiorca |
|---|---|
| `AA,44,08,29,...` (#22) | slave id=2 |
| `AB,44,09,29,...` (#24) | slave id=3 |
| `AC,44,0A,29,...` (#26) | slave id=4 |
| ... | ... |

**Wzór: f[0] = 0xA8 + id**, f[2] CRC rośnie liniowo o +1 per id.

**Dowody (cross-reference log 21:28-21:32):**
- Nano slave z id=2 odpowiada tylko po `#22_AA,44` (delay ~280ms), IGNORUJE `AB,44`, `AC,44`
- Nano slave z id=3 odpowiada tylko po `#24_AB,44` (delay ~250-300ms), IGNORUJE `AA,44`
- Konsystentne przez kilkadziesiąt cykli

**Znaczenie:**
- **Slave'y nie potrzebują synchronizacji między sobą** — każdy słucha TYLKO swojego wake-up'a, nie ma kolizji
- ESP może emulować N slave'ów jednocześnie — każdy na swoim wake-up, bezkolizyjnie
- Master wysyła 6 wake-up'ów w cyklu Full: `AA/AB/AC × src=0x44/0x56` — prawdopodobnie 2 kanały (0x44=dane RS-485, 0x56=?). Ramki src=0x56 mają f[4..]=0x00 zamiast 0x7E — inny format payload.

**Do zbadania:** czy wake-up skaluje się dalej (`AD` dla id=5, ..., `BC` dla id=20)? Czy master sam dynamicznie generuje wake-up'y po wykryciu nowego slave, czy zawsze nadaje wszystkie 20?

## Sweep id=2..6 (2026-04-24 22:17-23:18)

Test: Nano w trybie slave, manualna zmiana id w menu Nano, zapis reakcji magistrali. Log: `id_sweep_2026-04-24.log`, markery: `id_markers_2026-04-24.txt`.

**Wyniki per id:**

| id | f[3] | Wake-up needed | Nano cyclic E4? | 80 boot po power-on? |
|----|------|----------------|-----------------|----------------------|
| 2  | 0x2A | AA,44,08,29   | ✓ (122 ramek) | nie testowano |
| 3  | 0x2B | AB,44,09,29   | ✓ (1 ramka — krótki pobyt) | nie |
| 4  | 0x2C | AC,44,0A,29   | ✓ (9 ramek) | nie |
| 5  | 0x2D | AD,44,0B,29 (BRAK w master) | ✗ cisza | ✓ `80(2D) f[2]=0x62` |
| 6  | 0x2E | AE,44,0C,29 (BRAK w master) | ✗ cisza | ✓ `80(2E) f[2]=0x63` |

**Wzory potwierdzone:**
- `f[3] = 0x28 + id` (dla id=2-6, ekstrapolowane do 20)
- Wake-up: `f[0] = 0xA8 + id`, `f[2] = 0x06 + id` (CRC w src=0x44)
- 80 boot CRC: `f[2] = 0x5F + (id - 2)` (0x5F dla id=2, 0x62 dla id=5, 0x63 dla id=6)
- Config push ESP master działa dla każdego id (wykryto 80(2D) i 80(2E) → wysłano E4(29) src=0x2D/0x2E automatycznie)

**Obserwacje "zaskakujące":**

1. **Powrót do id=2 po sweepie przez id=3,4,5,6 — pierwsza próba cisza, druga próba OK.** Nano zachowuje się jakby "pamiętało" stan; druga zmiana id=2 zadziałała bez problemu. Hipoteza: Nano ma wewnętrzny debounce lub czeka na kolejny cykl master by się "włączyć".

2. **Przerwa AERO 22:21:31 → 22:27:09 (~5:40 min)** w trakcie sweepa (przy id=5,6). Początkowo hipoteza "AERO milknie gdy slave id nieobsługiwany" — **ODRZUCONA** przy 4tej próbie id=5 (AERO odpowiadało normalnie). Prawdziwa przyczyna prawdopodobnie: zawieszenie wątku nasłuchu w ESP master po wielokrotnych config push'ach (pomógł restart ESP).

3. **f[7] = 0x03 stałe dla wszystkich id w tej sesji** (wcześniej 0x02). Nie zależy od id slave'a. Zmienia się między sesjami — nieokreślony parametr Nano pamiętany w EEPROM.

4. **Stan unsynced slave po zabawach z ESP master:**
   - f[28] = 0x03 (brak flagi sync 0x40 — master "nieuznany")
   - f[24] = 0x32 (50% fan, tryb fallback) zamiast 0x64 (100%)
   - Nasz ESP master nie ma pełnej sekwencji handshake by przełączyć slave w synced. Config push E4(29) src=0x2X to za mało.

**Implementacja:** rozszerzyć cykl Master Full o wake-up AD..BC (id 5-20) × src=0x44 (16 par ramek). Zwiększa cykl z ~22s do ~35s ale pozwala obsłużyć pełen zakres id zgodnie ze specyfikacją Nano (id=1-20).

**TODO po sesji:** nie zaimplementowane jeszcze — yaml zmiana + compile + flash po następnym kontakcie.

## Virtual Slaves + Nano master (2026-04-24/25)

Test z Nano w roli master, ESP jako 4 niezależne virtual slave'y (switche VS id=2..5). Log: `vs_test.log`.

### Potwierdzone (H1 — wake-up sztywne)

- **Wake-up per-id zweryfikowane empirycznie dla id=2,3,4:** Nano master nadaje `AA,44,08,29` (id=2) / `AB,44,09,29` (id=3) / `AC,44,0A,29` (id=4) × src=44 i src=56 (6 wake-up'ów/cykl).
- **VS2 + VS3 + VS4 aktywne jednocześnie** odpowiadają bez kolizji — każdy słyszy wyłącznie swój wake-up.
- **VS5 (id=5) ignorowany przez Nano mastera** — 80(2D) boot leci ale master nie dodaje AD wake-up. Mistrz ma **statyczną listę zarejestrowanych slave'ów** z menu, nie dynamiczną rejestrację po 80.
- Hipoteza H2 (wake-up rotuje AA=pierwszy/AB=drugi) — **ODRZUCONA**. Potwierdzone przy jednym aktywnym id=5 — Nano master NIE nadał AA.

### Odkrycia w ramkach Nano master

**f[5] w E4(29) src=21 = flaga AERO_OK:**
- 0x40 = master widzi odpowiedzi AERO (live sync)
- 0x00 = brak komunikacji z AERO (master krzyczy "brak komunikacji")
- Reaguje dynamicznie (obserwowane przełączenie 0x40↔0x00 w trakcie testu)

**f[24] i f[28] w E4(29) src=21 — NIE reagują na live bus** (hipoteza sync master↔slave ODRZUCONA):
- f[24]=0x32 (prawdop. tryb fan awaryjny 50%) trwałe w pamięci
- f[28]=0x03 (brak flagi 0x40) trwałe
- Nie zmieniają się mimo AERO OK, mimo VS synced, mimo power cycle

Prawdopodobnie stan menu Nano (sezon/harmonogram/tryb mocy) zapisany w EEPROM.

**E3(29) src=44 ma 2 warianty** różniące się tylko f[28]: 0x13 vs 0x53 (flaga 0x40 toggle — może "cycle phase").

**f[24] w E3(29) src=44 = 0x2D** (id=5) — prawdopodobnie max slave id lub "highest registered slave" z menu Nano. Nie zmienia się po 80 boot od innych id.

**D0-D5 payload identyczny** u Nano master (i naszego ESP master): `53,4B,41,07,68,07,04,00,6E,00,5A` — 6× broadcast config (nie per-slave).

### Topologia bus (erratum 2026-04-25)

**Początkowa błędna hipoteza:** "VS zakłóca AERO przez multi-drop bus" — odwołana po znalezieniu luźnej masy RS-485.

**Rzeczywistość potwierdzona po naprawie:** z dobrym bus'em **VS2/3/4 + AERO współistnieją bez konfliktu**:
- AERO Responses rośnie stabilnie (co ~10s, zgodnie z cyklem Nano mastera)
- Wszystkie cztery VS aktywne, każdy odpowiada na swój wake-up
- Brak utraty ramek, brak zamrożenia AERO

**Morał:** przy diagnostyce bus RS-485 najpierw sprawdź fizykę (masy, zasilanie, terminacja), potem software. Nasze całe "VS zakłóca AERO" w poprzedniej sesji było efektem luźnego połączenia GND.

### Log startowy z VS id=2 i id=3 (2026-04-25 ~18:23)

Plik: `log_startowy_slave_2_3.log` (4916 linii, 2 power-on Nano master).

**Setup:** ESP w roli slave z aktywnymi VS id=2 (cyclic E4 na AA wake-up) i VS id=3 (cyclic E4 na AB wake-up). Nano master power-cycle.

**Kluczowe obserwacje:**

1. **Pierwsza ramka po power-on** = `E4(29) src=21` (broadcast standardowy), nie żadna init/handshake.
2. **f[5]=0x40, f[24]=0x64, f[28]=0x43 od pierwszej ramki** — synced state odzyskany z EEPROM, nie wymaga "rozgrzewki".
3. **Config push leci 23s po power-on** w pozycji #1 drugiego cyklu Master Full, ZASTĘPUJĄC standardowe `E4(29) src=21` w tej pozycji.
4. **Config push tylko do id=2** — choć VS3 cyklicznie odpowiada na AB wake-up.
5. W menu Nano **NIE ma listy slave'ów** ani "liczby slave" — jedynie własne id urządzenia. Master nie posiada explicite listy zarejestrowanych slave'ów w UI.
6. Skąd więc lista do której idzie config push? **Niewiadome empirycznie:** może EEPROM-pamięć "ostatnio widziany slave" (jeden slot, ostatnio aktywne id=2 z wczorajszego sweepu), może zapis przy zaobserwowaniu E4(2X) przez minimalny czas, może coś innego. **Wymaga testów rozdzielczych** by ustalić warunek auto-rejestracji.

### Test rozstrzygający (2026-04-25 18:42-18:48)

**Setup:** ESP slave z VS id=2 i VS id=3 aktywne, Nano master id=1.

**Test 1 (18:42, oba VS aktywne, reboot Nano):**
- VS2 = 25 odpowiedzi, VS3 = 64 odpowiedzi przed power-off
- Power-off Nano 18:41:17, power-on 18:42:20
- Config push o 18:42:43 → **TYLKO src=2A** (do id=2)
- Brak config push do id=3 mimo aktywnego VS3

**Test 2 (18:48, VS wszystkie OFF, reboot Nano):**
- Bus pusty (żadne VS nie odpowiadają)
- Power-on Nano
- Config push o 18:48:50 → **JEDNAK src=2A** (do id=2)
- Master wysyła config do id=2 mimo nieobecności slave'a

**Wniosek empiryczny:** id=2 jest **zaszyte w EEPROM Nano mastera** (lub wynika z logiki master_id+1 = 1+1 = 2). Wysyłka config push **NIE zależy od:**
- Aktywności slave'a na busie
- Liczby slave'ów odpowiadających
- Luki w numeracji id

**Hipoteza H "luki w id" — odrzucona.**
**Hipoteza I "ignorowanie przez cyklic AA/AB" — odrzucona.**
**Hipoteza J "id=2 zaszyte" — potwierdzona.**

**Niewiadome do dalszych testów:**
- Jak zarejestrować nowe id w master EEPROM? (potencjalne procedury: serwisowe menu, factory reset, sekwencja klawiszy)
- Czy zmiana id mastera (np. na id=2) zmienia adresata config push (na id=3 = master+1)? Test wymaga zmiany id mastera w jego menu.
6. Master nadaje wake-up'y `AA/AB/AC × src=44/56` niezależnie od zarejestrowanych slave'ów (statyczna lista, nie dynamiczna).

**Konsekwencja dla naszej emulacji:**
- ESP master **wysyłający config push reaktywnie na 80** to dodatkowa funkcjonalność ponad protokół Nano (Nano nie reaguje na 80 od slave w trybie pracy)
- Slave po power-on w realnym scenariuszu czeka aż **master się zrebootuje** żeby dostać świeży config push, lub liczy się z tym że sam musi wybierać konfigurację z broadcastów (E4 src=21, E5, D0-D5)

### Status szablonu VS

Szablon VS nadaje: f[7]=0x02, f[24]=0x64, f[28]=0x43 (skopiowane z synced Nano slave). Drobne potencjalne ulepszenia (niepilne):
- Rotator f[25-26] stały `01,14` (realny Nano rotuje `01,1A / 02,01 / 03,02` cyklicznie)
- Zegar f[8-9] działa OK (SNTP)

### Nierozstrzygnięte pytania

1. **Jak Nano master dodaje nowy slave id do listy wake-up'ów?** 80 boot nie wystarcza. Może menu UI + potwierdzenie w innym urządzeniu?
2. **Jakie konkretnie ustawienia menu Nano mastera ustawiają f[24]/f[28] w E4(29)** na 0x64/0x43 vs 0x32/0x03?
3. **Czy fizyczne rozdzielenie bus'u przez ESP MITM** pozwoli uniknąć zakłócania AERO przez VS?

## ESP8266 SW serial — fantomowe `0xFF`

**Objaw:** Pierwotny sniffer na `wemos04` (ESP8266, software serial GPIO12/13) pokazywał ramki **31 bajtów** kończące się sekwencją `0x23,0xFF`. Skill i stara dokumentacja zapisywały to jako "terminator 0x23+0xFF".

**Prawdziwa przyczyna (odkryte 2026-04-14 dual-snifferem ESP32 z `debug.delimiter:[0x23]`):**
- W C14 nie ma `0xFF` w ogóle.
- Wszystkie ramki to **30 bajtów**.
- Po `0x23` natychmiast zaczyna się następna ramka (brak idle gap).
- ESP8266 software serial **czyta stop bit (zawsze `1`) jako dodatkowy bajt `0xFF`** przy szybkim strumieniu.

**Lekcja:** nie ufaj ESP8266 software serial przy ≥9600 bps i burst-mode protokole. Do sniffingu RS-485 używaj **hardware UART** (ESP32 UART1/UART2).

## Kolizja E4(63) w slocie mastera

**Objaw:** `esp02.yaml` (wersja sprzed 2026-04-14) działał w trybie master, wysyłał pełny 11-ramkowy cykl, ale `g_aero_resp_count` wynosił **zawsze 0** — AERO nie odpowiadało.

**Przyczyna:** Stary YAML (linie 247-256) wysyłał **statyczną ramkę E4(63) w slocie #3** — dokładnie w oknie, w którym AERO chce odpowiedzieć swoją E4(63). Kolizja na busie niszczyła odpowiedź AERO.

**Dodatkowe mylenie:** Ramkę E4(63) nadaje **TYLKO AERO** — to jej unikalna odpowiedź. Master nie powinien nigdy jej symulować. `byte[1]` we wszystkich obserwowanych ramkach E4 to **typ ramki** (0x21 dla komend mastera, 0x63 dla odpowiedzi AERO), nie adres źródłowy.

**Fix:** w slocie odpowiedzi AERO master **MUSI MILCZEĆ** i nasłuchiwać. ESP-master w aktualnym esp02.yaml rezerwuje 800ms slot po ramce triggera (E3(29)_44) — AERO odpowiada w ~400ms.

## rx_buffer 256 B — dane przesunięte

**Objaw:** `wemos04_restore_backup_ab.yaml` pokazywał `B28=0x03` dla Biegu 1 (a powinno być `0x43`/`0x03` — właściwa wartość zależy od trybu). Skrypt wnioskował: "B28 to bieg z rozkodowanym LSB". Cały model protokołu poszedł w złą stronę.

**Przyczyna:** `rx_buffer_size: 256` w `uart:` był za mały dla cyklu 11 ramek × 30 B = 330 B wysyłanych burstem przez Nano. Bufor się przepełniał między odczytami `interval: 50ms`, dane przesuwały się o losową liczbę bajtów. Parser widział `f[28]=0x03` zamiast `f[28]=0x43` bo dekodował `f[26]` jako `f[28]`.

**Fix:** `rx_buffer_size: 512` (minimum dla 11 ramek + margines). Od tej zmiany B28 czyta się stabilnie.

**Lekcja:** przy UART debugowaniu zawsze sprawdzić rozmiar bufora vs rozmiar burst'u. ESPHome default 256 B jest za mały dla protokołów typu C14.

## Nie przepisuj parsera wemos04

W jednej iteracji próbowałem "uprościć" parser detekcji ramki — zamiast sprawdzać `0x23 && byte >= 0x80` zacząłem szukać `0xAA && byte >= 0xE0`. Efekt:
- Ramki `0x81` (heartbeat Nano), `0xD0-D2` (slave config) były pomijane bo `0x81 < 0xE0`.
- Bajt `0xAA` wewnątrz danych niektórych ramek resetował bufor, tracąc pół cyklu.

**Lekcja:** oryginalna logika (`detekcja po 0x23 + pierwszy bajt >= 0x80`) jest sprawdzona dla pełnego zestawu 11 ramek Master Mini. Nie zmieniać bez powodu. Jeśli zmiana konieczna — zweryfikować na wszystkich typach ramek (E2, E3, E4, E5, F0, 81, D0-D2) osobno.

## 5 podejść do sterowania biegiem (chronologicznie)

| # | Podejście | Platforma | Wynik |
|---|-----------|-----------|-------|
| 1 | Button wstrzykujący ramkę E4(29) | wemos04 (ESP8266) | AERO reagowała chwilowo, Nano natychmiast nadpisywało |
| 2 | Periodic sender co 3s | wemos04 | AERO oscylowała między biegami (konflikt z Nano cyklem) |
| 3 | Reactive TX 50ms (po E4(29) Nano) | wemos04 | Działało częściowo, ESP8266 SW serial niepewny |
| 4 | iNext emulacja (odpowiada jako 0x56) | planowane, nieprzetestowane | - |
| 5 | **ESP32 sole master** (esp02, Nano=slave) | ESP32 | **AKTUALNE** — działa po fixach checksum i kolejności ramek |

**Lekcja:** dopóki Nano jest masterem, ESP może tylko podsłuchiwać i wtrącać komendy — ale Nano natychmiast je nadpisuje w następnym cyklu. Sole master (ESP zamiast Nano) to jedyne stabilne podejście do sterowania.

## Fałszywe podejrzenia "AERO nie odpowiada na ESP-master"

Przez 3 dni (2026-04-12 do 2026-04-14) zakładaliśmy, że problem jest w **hardware/timing**:
- Voltage level (ESP32 3.3V vs Nano 5V RS-485)
- Auto-direction moduł zbyt wolny
- DE/RE pin potrzebny
- AERO wymaga handshake/cold-start

**Okazało się** (2026-04-19): wszystko było **w danych ramki**:
- Stary E4(63) w slocie #3 → kolizja (fix 2026-04-14)
- Checksum E3(29)_44 i E5(29) z błędnym K `0x23` zamiast `0xA3` → AERO ignorowała trigger jako uszkodzony (fix 2026-04-19)

**Lekcja:** nim zabierzesz się za hardware, zweryfikuj **bajt po bajcie** że twoja ramka jest identyczna z Nano (poza oczywistymi zmiennymi jak zegar). Checksum przelicz ręcznie na minimum 2-3 różnych ramkach z obserwacji.

## Checksum K=0xA3 (nie 0x23 jak myślano)

Przez pierwsze dni miałem zapisane w memory dwie wartości K:
- K=0xA3 dla E4, E2, F0, E3(56)
- K=0x23 dla E3(44), E5, 81, D0-D5

Podstawa: pierwotna iteracja esp02.yaml używała 0x23 dla E5/E3(44) i **czasami** AERO odpowiadała — więc zakładałem że K jest różny dla ramek.

**Zweryfikowałem 2026-04-19** licząc na 3 różnych obserwacjach ramek Nano E3(29)_44 i E5(29) — wszystkie dają **K=0xA3**. Dawne "czasem AERO odpowiadała" to prawdopodobnie mylny wniosek z okien gdy Nano nadal miał resztkowy autorytet na busie.

**Lekcja:** nie ufaj wcześniejszym zapisom K w memory bez weryfikacji. Checksum to jedna z pierwszych rzeczy do re-walidacji przy debugowaniu protokołu.

## Debug workflow który się sprawdził

1. **Bridge MITM z osobnymi UART-ami** (esp02 z 2× HW-0519, fizyczne rozcięcie A/B) — pozwala widzieć ruch w obie strony niezależnie
2. **Live streaming logów** (`esphome logs --device IP`) zamiast czekania na flush
3. **Zmiana jednego pola na Nano → obserwacja różnic w ramkach** — systematyczne mapowanie setpointów, trybów, bypass
4. **Test triggera button-per-frame** — ekskluzywna weryfikacja która ramka wywołuje odpowiedź AERO (odkryło że E3(29)_44 jest jedynym triggerem)

## Odkrycie triggera przez button-per-frame test (2026-04-15)

Przez tygodnie zakładaliśmy, że AERO odpowiada ramką E4(63) na pełny cykl mastera, a nie pojedynczy trigger. Próba izolowania konkretnej ramki-triggera była niemożliwa bo wszystkie 10 ramek Nano leciały w cyklu non-stop.

**Rozwiązanie:** osobny yaml `esp32_test.yaml` z 10 switchami HA — każdy switch generuje jedną konkretną ramkę (z hardcoded bajtami z snapshota Nano). Reszta ramek cyklu wyłączona. Obserwacja odpowiedzi AERO:

| Włączone | AERO reaguje? |
|----------|---------------|
| Wszystkie OFF (baseline) | Nie, cisza |
| Pojedynczo: E3(56), E2, E5, F0, 81, D0, D1, D2 | Nie |
| Pojedynczo: E4(29) | Nie (AERO zmienia wentylator mechanicznie, ale nie odpowiada ramką) |
| Pojedynczo: **E3(29) src=0x44** | **TAK — E4(63) w ~400ms** |

To była kluczowa weryfikacja że E3(29)_44 jest jedynym triggerem. Pozostałe ramki są broadcastami dla innych urządzeń (iNEXT, Nano-slave, EX4) i AERO je ignoruje.

**Lekcja:** jeśli protokół ma wiele ramek, izolować każdą niezależnie zamiast wnioskować z korelacji w pełnym cyklu.

## Dekodowanie programów — Normal/Poza Domem/Urlop (2026-04-22)

Nano ma 3 programy w menu TRYB PRACY: harmonogram / poza domem / urlop. Z wizualizacji użytkownika wyglądają jak 3 różne tryby, ale test bridge MITM ujawnił zaskakujące zachowanie:

1. **Normal** — ramki E4(29) f[5]=0x44, f[28]=0x03 (baseline)
2. **Poza Domem włączone** — **ramki identyczne jak Normal**, żadna zmiana w protokole
3. **Urlop włączone** — f[5]=0x40 (bit 2 reset), f[28]=0x02 — jedyna programowa zmiana

**Wniosek:** Poza Domem to **tylko lokalny override na Nano** — Nano wewnętrznie zmienia aktywny setpoint temperatury na "Poza Domem" (np. 20°C), ale protokołowi C14 nic nie komunikuje. Harmonogram dalej się wykonuje, tylko z niższą temperaturą celu.

**Urlop** jest właściwym broadcastem "ignore schedule" — AERO widzi f[5]&0x04=0 i przełącza się w tryb utrzymania stałego setpointu.

**Lekcja:** nie wszystko co jest w UI jest w protokole. Część logiki może być lokalna w jednostce sterującej i nie być transmitowana. Przed szukaniem "brakującego bitu" zawsze sprawdzić czy w ogóle coś się zmienia na magistrali.

## Master Full budzi Nano slave (2026-04-22)

Po dodaniu trybu Master Full do ESP (27 ramek zamiast 10) zauważyliśmy że Nano w trybie slave id=2 **zaczyna nadawać E4(2A) i inne ramki**, podczas gdy w Master Mini był całkowicie cichy.

**Hipoteza robocza:** jedna z 17 ramek Full jest "wake-up" dla Nano slave. Kandydaci:
- D3/D4/D5 — slave config rozszerzony
- 8B/9F/82/8C/8D/8E/95 — heartbeaty dla rzadkich slave ID
- AA/AB/AC × (src=0x44 + src=0x56) — broadcasty dual-address

**Analogia do odkrycia triggera AERO:** Nano slave też czeka na konkretną ramkę zanim się aktywuje, podobnie jak AERO czeka na E3(29)_44.

**Rozstrzygnięcie (2026-04-22 wieczór):** zamiast testu połówkowego z grupami, bezpośrednio zredukowaliśmy Full do Mini + jednej konkretnej ramki. Test z **tylko AA(29) src=0x44** (ramka #22 z Full) + Mini 10 ramek → **Nano slave aktywuje się**. Potwierdzone: to ta jedna ramka jest wake-upem, pozostałe 16 ramek Full to enumeration dla innych typów urządzeń (EX4, dodatkowe Nano, iNEXT expansion) — w naszym setupie niepotrzebne.

**Praktyczna implikacja:** "Lean Master" (11 ramek: Mini + AA(29)_44) daje te same wyniki co Full (27 ramek) — Nano slave aktywny, AERO odpowiada — przy 2-3× krótszym cyklu (~9s zamiast ~22s).

**Lekcja:** jeśli odkryjesz jedną ramkę-trigger (typu AA/44, E3/44), sprawdź czy dalsze ramki w cyklu są w ogóle potrzebne. Protokoły enumeracji często mają wiele "pytań o typy" które odpadają jeśli masz znane wąskie grono urządzeń.

## Hipoteza: E5(29) f[26] = Slave ACK flag (2026-04-23 wieczór)

Podczas testu ESP w roli Slave + Nano master, po wciśnięciu **Slave Boot 80(2A)** i aktywacji reactive E4(2A) na AA(44), zauważyliśmy że Nano master **zmienił f[26] w E5(29) z `0x00` na `0x50`**.

- We wszystkich wcześniejszych logach (przed dzisiejszym testem) E5(29) f[26] = `0x00` stale
- W logach `slave_boot_test.log` (dzisiejszy test) pojawiła się wartość `0x50` po aktywacji slave

**Hipoteza:** `f[26]=0x50` to flaga "slave acknowledged" — Nano master ustawia ją gdy wykryje aktywnego slave na busie. To byłaby alternatywa do dedykowanej ramki ACK (którą my obserwowaliśmy rano jako E4(29) src=0x2A config push, ale nasz fake 80 dzisiaj jej nie wywołał).

**Niepewne:**
- Timing zmiany vs BOOT — pierwszy 0x50 ~22 min po pierwszym BOOT, nie natychmiast
- Może korelacja z innym zdarzeniem (np. nasze reactive E4(2A) na AA przez dłuższy czas)

**Do weryfikacji:** obserwacja power cycle slave'a w izolowanym teście bez historii wcześniejszych interakcji.

## Master config push do slave — E4(29) src=0x2A (2026-04-23)

Po wczorajszym odkryciu ramki slave-boot 80(2A), dziś zrobiliśmy kolejny power-cycle Nano slave id=2 (Nano master id=1, ESP w roli slave). W logach pojawiła się **unikalna, nigdy wcześniej nie widziana** ramka:

```
E4,2A,43,29,0D,01,05,28,1C,2A,00,1E,01,17,5F,64,18,14,00,24,20,28,46,25,2D,4B,20,01,53,23
```

Kluczowe cechy:
- f[1] = 0x2A — dedykowane adresowanie do slave id=2 (nietypowe, normalnie broadcasty mają 0x21/0x44/0x56)
- f[3] = 0x29 — subtyp master-mode
- Wystąpiła **tylko 1 raz**, ~16s po power-on slave
- Od f[14] do f[29] — identyczne jak w E3(29)_44 query (nastawy % per bieg)
- f[4-13] — 10 bajtów nieznanej konfiguracji (może zawierać datę?)

**Interpretacja:** to "master → slave config push" — master po wykryciu aktywnego slave (ESP wysyła E4(2A) w odpowiedzi na AA(44)) wysyła mu jednorazowo pełną konfigurację. To wyjaśnia zachowanie Nano slave widoczne wczoraj (zmiana encoding f[28] 0x43→0x03 po 80(2A)) — slave otrzymał config i zaktualizował stan.

**Konsekwencja dla naszego ESP-master:** żeby Nano w roli slave dostało pełną synchronizację po boot, nasz ESP powinien wysyłać E4(29) src=0x2A (z aktualnymi setpointami + datą) w odpowiedzi na 80(2A). Obecny ESP-master nie robi tego — dlatego Nano slave nie synchronizuje RTC i trzyma stary czas.

**TODO:** zmiana daty na Nano master + power cycle slave → porównanie różnic w f[4-13] identyfikuje które pole jest datą.

## Slave boot announcement — 80(2A) (2026-04-22 wieczór)

Podczas testu z Nano slave id=2 + power cycle zaobserwowaliśmy nową ramkę której wcześniej nie widzieliśmy w żadnym cyklu master:

```
80,44,5F,2A,7E×26,23
```

Kluczowe cechy:
- **Jednorazowa** (przez całą sesję testową 4+ minut tylko 1 wystąpienie)
- Pojawiła się ~3s po power-on Nano
- Struktura identyczna z `81(29)` (Nano master heartbeat) ale z `f[0]-1` i `f[3]+1` — sugeruje rodzinę frame ID: 0x80=slave_hb, 0x81=master_hb
- f[2]=0x5F identyczna jak 81(29) heartbeat — to te same bajty po prostu z innym `f[3]`

**Po 80(2A) Nano slave zmienił encoding E4(2A):**
- f[28] z `0x43` (stare B1 manual) → `0x03` (nowe B1 — jak nasz ESP master)
- Rotator zresetowany

Interpretacja: 80(2A) to pewnie "slave ready / boot complete" announcement. Tłumaczy komunikat UI "DATĘ USTAWIA NANO NR 1" — slave po tym oczekuje synchronizacji daty od mastera. Nasz ESP-master takiej synchronizacji nie wysyła (nie znamy formatu odpowiedzi), więc Nano slave zachowuje własny RTC.

**TODO:** zarejestrować co master (Nano nr 1) wysyła ~400ms po otrzymaniu 80(2A) — prawdopodobnie jest jakaś odpowiedź z datą. To wymagałoby testu z Nano master + Nano slave + ESP tylko jako sniffer.

**Aktualizacja 2026-04-23:** zebrane 3 obserwacje 80(2A) na różnych pozycjach cyklu master (#5-6, #27-1, #10-11) **potwierdzają losowy timing** — Nano slave wysyła ramkę gdy tylko zakończy boot, w pierwszą dostępną lukę na busie. NIE jest to ramka na specific slot. Sam "master response" E4(29) src=0x2A pojawia się natomiast zawsze w najbliższym cyklu master na pozycji #1 (zastępując E4(29) src=0x21).

## Data nie jest transmitowana przez C14 (2026-04-22)

Test zmiany daty/godziny na Nano master w trakcie logu bridge:

| Zmiana | Skutek w E4(29) Nano |
|--------|----------------------|
| Dzień 22→24 | Brak zmian |
| Miesiąc 04→02 | f[7] z `0x01/02` → `0x05` (może przeliczony day_of_week) |
| Rok 2026→2024 | Brak zmian |
| Godzina 17→19 | f[8] z `0x11` → `0x13` ✓ |
| Minuta 14→10 | f[9] z `0x0E` → `0x0A` ✓ |

**Wniosek:** tylko godzina i minuta transmitowane na C14. Dzień/miesiąc/rok Nano trzyma lokalnie (dla wyświetlacza i harmonogramu). AERO nie dostaje daty — wystarcza mu czas dnia.

Sprawdzone wszystkie 27 ramek Master Full — pozostałe 25 (oprócz E4(29) i E5(29)) **stałe bajt-w-bajt** przez cały test (tylko cksum się zmienia). Brak ukrytego pola z datą.

---

## Co zostało otwarte (do przyszłych sesji)

- **E5(29) f[18-19]** (`00,30` stałe) — nie reaguje na lato/zima/chłodzenie ani bypass. Może parametr konfiguracyjny (histereza, korekta temperatury)?
- **E4(29) f[24]** — wariabilne (`0x32`/`0x64`/`0x00`), brak prostej korelacji ze stanem
- **Rotator E4(29) f[25-26]** c=3 — obserwowane `0x0E`/`0x0F`/`0x13` w różnych sytuacjach
- **E5(29) f[28]** — pełny enum kodów UI Nano (wyjściowe `0x00/01/03/05/16/18/19`, brak wzoru)
- **Cold-start handshake** — czy istnieje sekwencja inicjalizacyjna przy starcie AERO? ESP-master jej nie robi i działa, ale to może być powód wcześniejszych niestabilności.

---

## 2026-04-26: Test 12-krokowy menu Nano (Wentylacja / Termostat / Programy)

Systematyczny test wszystkich pozycji 3 menu w Nano master, każda zmiana weryfikowana na 4-5 cyklach Master Full. Sezon=Zima, schedule (eco=B1 początkowo, później eco=B2; poza-domem=Stop).

### Test A — Wentylacja (Term=Manual stały, Prog=Normal):

| Wentylacja | f[28] | f[24] |
|-----------|-------|-------|
| Manual Stop | `0x41` | `0x64` |
| Manual B1 | `0x43` | `0x64` |
| Manual B2 | `0x45` | `0x64` |
| Manual B3 | `0x47` | `0x64` |
| Harmonogram (slot=B1) | `0x43` (== Manual B1) | `0x64` |
| Harm-Urlop (slot=B1) | `0x03` (== B1 bez stable) | `0x32` |
| Harm-Urlop (slot=B2 po edycji harm) | `0x05` | `0x32` |

**Odkrycia:**
- Wentylacja=Harmonogram protokołowo identyczne z Manual+slot_bieg (slave nie odróżni)
- Wentylacja=Harm-Urlop też rotuje wg harmonogramu (zmiana eco→B2 natychmiast zmieniła `f[28]` z `0x03`→`0x05`)
- Harm-Urlop różni się od Manual jedynie brakiem bitu `0x40` w f[28] + `f[24]=0x32`

### Test B — Termostat (Went=Manual B1, Prog=Normal):

| Termostat | f[27] bity 0-1 | f[14-15] | f[28] | f[24] |
|-----------|----------------|----------|-------|-------|
| Manual | `0x02` | 25°C (Manual setpoint) | `0x43` (B1+stable) | `0x64` |
| Harmonogram | `0x00` | 21°C (eco_zima) | `0x03` (no stable) | `0x32` |
| Urlop | **`0x01`** | 21°C (eco_zima, jak Harm) | `0x03` (no stable) | `0x32` |

**Odkrycia:**
- **Termostat=Urlop ma własny kod `0x01`** w f[27] bity 0-1. Wcześniejsza hipoteza (HISTORY 2026-04-25) "Urlop=Harm protokołowo identyczne, oba `0x00`" była **błędna** — bazowała na nieczystym teście (Nano w trybie slave ze starym EEPROM).
- Bit `0x40` w f[28] + `f[24]=0x64` = flaga **Termostat=Manual** (CLEAR dla Harm/Urlop). Wcześniejsza hipoteza "stable=Manual+Zima" była zbliżona, ale Sezon nie jest niezbędny.
- Setpoint Term=Urlop+Zima = eco_zima (21°C, taki sam jak Harm) — Nano nie zmienia setpointu między Harm a Urlop. Wcześniejsza hipoteza "Urlop+Zima → poza_domem" była błędna.

### Test C — Programy (Term=Manual, Went=Manual B1, schedule poza-dom=Stop):

| Program | f[5] | f[14-15] | f[28] |
|---------|------|----------|-------|
| Normal | `0x40` | 25°C (wg Termostatu) | `0x43` (Manual B1+stable) |
| Poza domem | **`0x44`** (bit `0x04` SET) | **20°C (poza_domem)** | **`0x41`** (Stop ze slotu poza-dom!) |
| Urlop | `0x40` | 20°C (poza_domem) | **`0x40`** (validity=0, bieg=0) |

**Odkrycia:**
- Bit `0x04` w f[5] = **"Programy=Poza domem aktywne"** (NIE "harmonogram aktywny" jak doc wcześniej). Aktywny tylko w Poza domem; Normal i Urlop → CLEAR.
- Programy=Poza domem ≠ Programy=Normal **protokołowo różne** (wcześniejsza hipoteza "identyczne, override lokalnie" była błędna): bieg, setpoint i `f[5]` różne.
- Programy=Urlop daje `f[28]=0x40` (validity=0, sam bit stable). Wcześniejszy doc mówił `f[28]=0x02` — błąd.
- Programy nadpisują Wentylacja menu (Wentylacja=Manual B1, ale w Poza domem `f[28]` pokazuje slot poza-domem = Stop).
- Programy nadpisują setpoint Termostatu (Term=Manual 25°C, ale w Poza domem/Urlop f[14-15]=20°C poza_domem).

### Programy=Urlop vs Wentylacja=Harm-Urlop — różne mechanizmy:

| | Programy=Urlop | Wentylacja=Harm-Urlop |
|----|----------------|------------------------|
| f[28] | `0x40` (validity=0) | bieg z slotu, bez `0x40` |
| f[24] | wg Termostatu | `0x32` |
| f[5] bit `0x04` | CLEAR | bez wpływu |
| Setpoint | poza_domem (override) | wg Termostatu |

Programy=Urlop = "wyłącz wentylację". Wentylacja=Harm-Urlop = "tryb minimalny, ale rotuj harmonogram".

### Korekty PROTOCOL.md po teście:
- §3.2 f[27] bity 0-1: dodany `0x01`=Urlop
- §3.2 f[28]: bit `0x40` = "Termostat=Manual" (NIE "stable Manual+Zima")
- §3.2 f[28]: `0x02` usunięte z opisu Urlop (faktycznie `0x40` dla Programy=Urlop)
- §3.2 f[5] bit `0x04`: "Poza domem aktywne" (NIE "harmonogram aktywny")
- §4.1 Termostat: Urlop ma własny kod
- §4.3 Wentylacja: 6 opcji rozszyfrowane
- §4.5 Programy: pełna tabela 3 stanów

---

## 2026-04-26: Test edycji harmonogramu (Q13)

Nano master, edycja menu "Harmonogram" (sloty czasowe gdzie ma być aktywne comfort/poza-domem; eco implicite w pozostałym czasie):
- 8 linii w menu: Pn/Wt/Śr/Cz/Pt/Sob/Nd + Święto (wszystkie identyczne w teście)
- Każdy dzień: 2 zakresy comfort + 1 zakres poza-domem
- Interwał edycji 15 min

**Procedura:** baseline (30 ramek = ~1 cykl Master Full) → zmiana 3 slotów (comf1: 0-0→10-18, comf2: 0-0→20-21, poza: 24-6→24-5) → after (30 ramek).

**Wynik:** wszystkie 22 typy ramek cyklu identyczne przed/po:
- 81, 82, 8B, 8C, 8D, 8E, 95, 9F, AA, AB, AC, D0, D1, D2, D3, D4, D5, E2, E3, F0 — bajt-w-bajt taka sama
- E4(29)_21 — tylko rutynowe różnice (cksum, f[8-9] zegar +1min, f[12-13] room temp drift, f[25-26] rotator daty)
- E5(29)_21 — tylko cksum + f[7] CZERPNIA temp drift 1 LSB

**Wniosek:** harmonogram trzymany w EEPROM lokalnie każdego Nano (master i slave). NIE broadcastowany na C14. Konsekwencja: slave nie zna harmonogramu mastera — widzi tylko aktualny setpoint w `f[14-15]` i bieg w `f[28]`. Każdy Nano w trybie slave ma własną kopię harmonogramu (do osobnej edycji).

---

## 2026-04-26: Rozszyfrowanie D0-D5 (parametry serwisowe AERO)

Test menu serwisowego Nano master, zmiany pojedynczych parametrów + porównanie ramek przed/po.

### Korekta termostatu (-10..+10°C)
Wpływa na **E4 f[12-13]** (Temp pokojowa Nano) — Nano dodaje offset lokalnie do raw sensora przed wysłaniem. Zmiana 0→+4 dała diff `f[12-13]: 11,20 (20.8°C) → 11,4D (25.3°C)`. Nie odrębne pole, tylko kalibracja.

### Bit 0x40 w f[28] — uściślenie
Przy korekta=+4 Nano przeszedł w `f[28]=0x03`/`f[24]=0x32` (CLEAR bitu `0x40`) mimo Term=Manual. Po wróceniu korekty na 0 → `f[28]=0x43`/`f[24]=0x64`. Pełna reguła:

**bit `0x40` SET ⇔ (Termostat=Manual) AND (korekta termostatu = 0)**

Wcześniejsza hipoteza "Manual+Zima" była niepełna. Sezon nieistotny, ale każda kalibracja sensora = bit CLEAR.

### Histereza termostatu — lokalna
Zmiana 0.5→2.5 nie wpłynęła na żadną ramkę. Trzymana w EEPROM.

### Informacja główna (selektor wyświetlacza Nano) — lokalna
Zmiana "pomieszczenia" → "nawiew wentylacji" — tylko rutynowe diff E4. Lokalne ustawienie display.

### Rozdzielacz - chłodzenie / PWM checkboxy — lokalne
Zmiana ON/OFF dla "praca z funkcja chłodzenia" i "praca z funkcja pwm" — żadna ramka się nie zmienia. Te checkboxy ukrywają opcje w menu (np. blokują dostęp do Sezon=Chłodzenie), ale nie wpływają na protokół.

### D0-D5 — parametry serwisowe rekuperatora ☆

**Główne odkrycie:** D0/D1/D2/D3/D4/D5 zawierają identyczny payload z parametrami serwisowymi z menu Nano. Wcześniejsza interpretacja `f[4-6]=53,4B,41` jako ASCII "SKA" była błędna — `0x4B` to przypadkowo kod 'K' bo domyślny próg osuszania = 75%.

| Bajt | Parametr | Encoding | Test |
|------|----------|----------|------|
| f[5] | Start osuszania - przekroczona wilgotność % | uint8 dec | 75→100 (`0x4B→0x64`), 100→50 (`0x64→0x32`) |
| f[6] | Stop osuszania % | uint8 dec | 65→55 (`0x41→0x37`) |
| f[7-8] | Start wietrzenia CO2 ppm (0-2000) | HH*128 + LL%128 (jak temperatura, bez offsetu) | 1000→945 (`07,68→07,31`) |
| f[9-10] | Stop wietrzenia CO2 ppm | jak f[7-8] | 900→850 (`07,04→06,52`) |
| f[11-12] | Start wietrzenia VOC (0-1000) | jak f[7-8] | 110 (`00,6E`) |
| f[13-14] | Stop wietrzenia VOC | jak f[11-12] | 90 (`00,5A`) |

Pozostałe stałe w D0-D5 (do identyfikacji w przyszłych testach):
- f[4]=`0x53` (83)
- f[6]=`0x41` (65) — drugi osuszania
- f[15-28]=`0x7E` filler

**Encoding 2-bajtowy CO2/VOC** używa tej samej formuły co temperatura (`HH*128 + LL%128`), tylko bez offsetu `-2000`. Predykcja stop CO2: 900ppm → `07,04` (7*128+4=900) potwierdzona ramką przed zmianą; 850ppm → `06,52` (6*128+82=850) potwierdzona po.

### Edycja harmonogramu — lokalna (zamknięcie Q13)
Zmiana 3 slotów (comf1, comf2, poza-domem) — żadna ramka się nie zmienia. Każdy Nano (master/slave) ma własną kopię w EEPROM.

# Historia debugowania C14 / ESP

Zapisane bugi, fałszywe tropy i lekcje z drogi. Dla bieżącej dokumentacji protokołu → [PROTOCOL.md](PROTOCOL.md).

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
| f[6] | Drugi parametr osuszania % (nazwa nieznana) | uint8 dec | 65→55 (`0x41→0x37`) |
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

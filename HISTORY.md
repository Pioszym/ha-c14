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

**Wnioski:**
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

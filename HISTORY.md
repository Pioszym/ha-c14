# Historia debugowania C14 / ESP

Zapisane bugi, fałszywe tropy i lekcje z drogi. Dla bieżącej dokumentacji protokołu → [PROTOCOL.md](PROTOCOL.md).

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

## Co zostało otwarte (do przyszłych sesji)

- **E5(29) f[18-19]** (`00,30` stałe) — nie reaguje na lato/zima/chłodzenie ani bypass. Może parametr konfiguracyjny (histereza, korekta temperatury)?
- **E4(29) f[24]** — wariabilne (`0x32`/`0x64`/`0x00`), brak prostej korelacji ze stanem
- **Rotator E4(29) f[25-26]** c=3 — obserwowane `0x0E`/`0x0F`/`0x13` w różnych sytuacjach
- **E5(29) f[28]** — pełny enum kodów UI Nano (wyjściowe `0x00/01/03/05/16/18/19`, brak wzoru)
- **Cold-start handshake** — czy istnieje sekwencja inicjalizacyjna przy starcie AERO? ESP-master jej nie robi i działa, ale to może być powód wcześniejszych niestabilności.

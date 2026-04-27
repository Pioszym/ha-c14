# ha-c14

ESP32 jako master/bridge/slave na magistrali C14 (COMPIT/PRO-VENT) do rekuperatora AERO 3B z panelem pokojowym Nano Color CTP.

## Pliki

- **[PROTOCOL.md](PROTOCOL.md)** — pełna dokumentacja reverse engineering protokołu C14 (mapa ramek, kodowanie, checksum, timing)
- **[HISTORY.md](HISTORY.md)** — historia debugowania, fałszywe tropy, lekcje (ESP8266 phantom 0xFF, kolizja slotu, bufor, checksum K)

## Hardware

- ESP32-WROOM-32
- 2x RS485 HW-0519 (3.3V, auto-direction)
- UART2 GPIO16/17 = strona AERO
- UART1 GPIO4/18 = strona NANO (Nano Color CTP)

## Status

Reverse engineering w toku. Większość kluczowych pól rozszyfrowana — ESP-master działa i steruje centralą. Szczegóły w [PROTOCOL.md](PROTOCOL.md).

## Disclaimer

Ten projekt to **niezależny reverse-engineering** w celu integracji rekuperatora COMPIT C14 / Prodmax z Home Assistant. Wszystkie obserwacje techniczne wykonane na sprzęcie będącym własnością autora.

- Projekt **nie jest** powiązany, sponsorowany ani autoryzowany przez COMPIT Sp. z o.o. ani Prodmax
- "COMPIT", "C14", "Nano CTP", "AERO", "Prodmax" są znakami towarowymi ich właścicieli — używane wyłącznie opisowo (*nominative fair use*) dla wskazania kompatybilności sprzętu
- Publikacja w oparciu o:
  - Dyrektywę UE 2009/24/WE (prawo do reverse engineering w celu interoperabilności)
  - Art. 75 polskiej Ustawy o prawie autorskim i prawach pokrewnych
  - Wyrok TSUE *SAS Institute v. WPL* (C-406/10) — RE dla interoperabilności jest dozwolony
- Format ramek RS-485 to **fakty techniczne** (nie utwór chroniony) — opisalność na równi z formatami JSON, MIDI, ASCII
- Kod firmware ESP32 to **oryginalny utwór autora** (lambdy ESPHome), nie kopia firmware COMPIT
- **Użycie na własne ryzyko** — autor nie ponosi odpowiedzialności za ewentualne uszkodzenia sprzętu lub awarię systemu wentylacji

### Licencje

- **Dokumentacja** (PROTOCOL.md, HISTORY.md, README.md): [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- **Kod firmware** (esp02.yaml, ESPHome lambdas): [MIT](https://opensource.org/licenses/MIT)

### Uwaga dla użytkowników

Modyfikacja sterownika rekuperatora może spowodować utratę gwarancji producenta. Sprawdź warunki gwarancji przed podłączeniem ESP32 do magistrali C14.


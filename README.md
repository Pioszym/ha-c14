# ha-c14

ESP32 jako master/bridge/slave na magistrali C14 (COMPIT/PRO-VENT) do rekuperatora AERO 3B z panelem pokojowym Nano Color CTP.

## Pliki

- **[PROTOCOL.md](PROTOCOL.md)** — pełna dokumentacja reverse engineering protokołu C14 (mapa ramek, kodowanie, checksum, timing)
- **[HISTORY.md](HISTORY.md)** — historia debugowania, fałszywe tropy, lekcje (ESP8266 phantom 0xFF, kolizja slotu, bufor, checksum K)
- **[esp02.yaml](esp02.yaml)** — user-level template (substitutions, esphome name, esp32 board, api/ota, uart piny). To kopiujesz/edytujesz dla swojego urządzenia.
- **[packages/c14_core.yaml](packages/c14_core.yaml)** — silnik C14: globals, scripts, cykl Mastera, parser ramek 30B, encje HA (switch/select/number/sensor). Bez ruszania, traktować jak bibliotekę.

## Hardware

- ESP32-WROOM-32 (lub kompatybilny)
- 1x RS485 HW-0519 (3.3V, auto-direction), wpięty równolegle do A1/B1 magistrali Nano↔AERO
- Domyślnie RX/TX = GPIO16/17 (zmienisz w `esp02.yaml` jeśli inne piny)

## Instalacja

1. Wgraj zawartość repo do `/config/esphome/` (lub klonuj). Powinieneś mieć `esp02.yaml` + `packages/c14_core.yaml`.
2. Edytuj `esp02.yaml`:
   - `substitutions:` — `device_name`, `friendly_name`
   - `uart:` — sprawdź piny `rx_pin`/`tx_pin`. **NIE zmieniaj `id: uart_bus`** — `c14_core.yaml` używa tego ID.
   - usuń `esp32_ble_tracker`/`bluetooth_proxy` jeśli nie potrzebujesz
   - `packages:` — `wifi`/`device_base` zastąp własnymi pakietami (lub usuń i wpisz `wifi:` bezpośrednio)
3. `secrets.yaml`: klucz API ESPHome, hasło OTA, hasło Wi-Fi
4. `esphome compile esp02.yaml && esphome upload esp02.yaml`
5. Po podłączeniu do HA encje pojawią się jako `switch.<device>_master_on`, `select.<device>_termostat` itd.

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


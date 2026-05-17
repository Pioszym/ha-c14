# ha-c14

ESP32 jako master/bridge/slave na magistrali C14 (COMPIT/PRO-VENT) do rekuperatora AERO 3B z panelem pokojowym Nano Color CTP.

## Pliki

- **[PROTOCOL.md](PROTOCOL.md)** — pełna dokumentacja reverse engineering protokołu C14 (mapa ramek, kodowanie, checksum, timing)
- **[c14.example.yaml](c14.example.yaml)** — przykładowy user-template. Skopiuj, dostosuj substitutions + piny UART + secrets, gotowe.
- **[packages/c14_core.yaml](packages/c14_core.yaml)** — silnik C14: globals, scripts, cykl Mastera, parser ramek 30B, encje HA (switch/select/number/sensor). User nie kopiuje — ściąga się sam przez github-package.

## Hardware

- ESP32-WROOM-32 (lub kompatybilny)
- 1× RS485 HW-0519 (3.3V, auto-direction), wpięty **równolegle** do A1/B1 magistrali Nano↔AERO (single-bus tap — ESP słucha cały ruch i może nadawać własne ramki)
- Domyślnie RX/TX = GPIO16/17 (zmienisz w swoim `*.yaml` jeśli inne piny)

## Instalacja

1. Skopiuj `c14.example.yaml` z tego repo do swojego `/config/esphome/` jako np. `c14.yaml`
2. Edytuj swój plik:
   - `substitutions:` — `device_name`, `friendly_name`
   - `uart:` — sprawdź piny `rx_pin`/`tx_pin`. **NIE zmieniaj `id: uart_bus`** — `c14_core.yaml` używa tego ID jako kontraktu.
3. `secrets.yaml` w `/config/esphome/`:
   ```yaml
   wifi_ssid: "twoje_ssid"
   wifi_password: "haslo"
   api_key: "wygenerowany_klucz_esphome"
   ota_password: "haslo_ota"
   ```
4. `esphome compile c14.yaml && esphome upload c14.yaml`
   - Przy pierwszej kompilacji ESPHome sklonuje to repo do `.esphome/packages/<hash>/` i wczyta `c14_core.yaml`
5. Po podłączeniu do HA encje pojawią się jako `switch.<device>_master_on`, `select.<device>_termostat`, `select.<device>_wentylacja` itd.

## Wersjonowanie

`c14.example.yaml` domyślnie używa `ref: v1.0` — zamrożony stable release. Tagi releasów są tutaj: https://github.com/Pioszym/ha-c14/tags

Chcesz bleeding-edge? Zmień `ref: v1.0` → `ref: main` w swoim YAML. Pamiętaj że main bywa eksperymentalny.

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

- **Dokumentacja** (PROTOCOL.md, README.md): [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- **Kod firmware** (c14.example.yaml, packages/c14_core.yaml, ESPHome lambdy): [MIT](https://opensource.org/licenses/MIT)

### Uwaga dla użytkowników

Modyfikacja sterownika rekuperatora może spowodować utratę gwarancji producenta. Sprawdź warunki gwarancji przed podłączeniem ESP32 do magistrali C14.


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


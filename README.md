# ha-c14

ESP32 jako master/bridge na magistrali C14 (COMPIT/PRO-VENT) do rekuperatora AERO 3B z panelem pokojowym Nano Color CTP.

## Pliki

- **[PROTOCOL.md](PROTOCOL.md)** — pełna dokumentacja reverse engineering protokołu C14 (mapa ramek, kodowanie, checksum, timing)
- **[HISTORY.md](HISTORY.md)** — historia debugowania, fałszywe tropy, lekcje (ESP8266 phantom 0xFF, kolizja slotu, bufor, checksum K)
- `esphome/esp02.yaml` — ESP32 master + bridge (wdrożone na HA jako `esp02`)
- `esphome/esp02_bridge.yaml` — czysty bridge MITM (diagnostyka, bez master TX)

## Hardware

- ESP32-WROOM-32 (IP 192.168.88.206)
- 2x RS485 HW-0519 (3.3V, auto-direction)
- UART2 GPIO16/17 = strona AERO
- UART1 GPIO4/18 = strona NANO (Nano Color CTP)

## Status

Reverse engineering w toku. Większość kluczowych pól rozszyfrowana — ESP-master działa i steruje centralą. Szczegóły w [PROTOCOL.md](PROTOCOL.md).

## Kontrolki HA (aktualne)

### Tryby i biegi
- `select.bieg` — Stop/B1/B2/B3 (manual encoding `0x01/03/05/07`)
- `select.sezon` — Zima/Lato bez/Chłodzenie
- `select.bypass` — OFF/AUTO/ON
- `switch.wietrzenie` — overlay ON/OFF

### Setpointy temperatur
- `number.temp_comfort`, `temp_eco`, `temp_chlodzenie`, `temp_reczna`, `temp_poza_domem`

### Sliders % wentylatora per bieg
- `number.nawiew_bieg_{1,2,3}`, `number.wywiew_bieg_{1,2,3}`
- `number.nawiew_wietrzenie`, `number.wywiew_wietrzenie`

### Switche sterujące
- `switch.c14_master_on` — włącz cykl master
- `switch.bridge_forward` — passive bridge AERO↔Nano (bez master)
- `switch.log_nano`, `log_esp`, `log_aero` — kontrola logowania ramek

### Sensory
- 4× temperatura (czerpnia/nawiew/wyrzut/wywiew)
- Aktualny nawiew/wywiew % (z AERO)
- `text_sensor.bieg_aktualny`, `bypass_aktualny`
- `binary_sensor.wentylator`
- `sensor.c14_cycles`, `c14_aero_responses` (diagnostyka)

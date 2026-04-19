# ha-c14

ESP32 jako master/bridge na magistrali C14 (COMPIT/PRO-VENT) do rekuperatora AERO.

## Pliki

- `esphome/esp02.yaml` — ESP32 master + bridge (wdrozone na HA jako `esp02`)
- `esphome/esp02_bridge.yaml` — czysty bridge MITM (diagnostyka, bez master TX)

## Hardware

- ESP32-WROOM-32 (IP 192.168.88.206)
- 2x RS485 HW-0519 (3.3V, auto-direction)
- UART2 GPIO16/17 = strona AERO
- UART1 GPIO4/18 = strona NANO (Nano Color CTP)

## Status

Reverse engineering w toku. Ramki C14 czesciowo rozszyfrowane, ESP-master dziala.

## Kontrolki HA

- `select.bieg` — Stop/B1/B2/B3
- `select.bypass` — OFF/AUTO/ON
- `number.nawiew_bieg_*` + `wywiew_bieg_*` — % per bieg (restore)
- `switch.c14_master_on` — wlacz cykl master
- `switch.bridge_enable`, `bridge_forward`
- `switch.log_nano` (green), `log_esp` (yellow), `log_aero` (red)

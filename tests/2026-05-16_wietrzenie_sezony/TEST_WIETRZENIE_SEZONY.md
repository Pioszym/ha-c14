# Test Wietrzenie w sezonach Chłodzenie + Lato bez — Nano Master Mini

**Data:** 2026-05-16
**Cel:** Świeża empiria zachowania Wietrzenia (overlay) w Sezonie **Chłodzenie** (priorytet, faktyczny problem) i **Lato bez ogrzewania**. Bez mieszania dotychczasowych hipotez (trusted bit / overlay / sticky bit) — patrzymy na bajty co rzeczywiście leci na bus.

**Hipotezy wstępne (do potwierdzenia LUB obalenia):**
- W Zimie: Wietrzenie ON → `f[27] +0x20` (potwierdzone wcześniej, T30/T31)
- W Chłodzeniu i Lato bez: **nieznane** — być może `+0x20` znika, być może bieg się zmienia, być może AERO ignoruje
- Hipoteza alternatywna: być może w Chłodzeniu Wietrzenie nie ma sensu (chłodzenie = pasywne otwarcie bypass, dodatkowy fan unbalanced wymianę powietrza)

## Setup

**Hardware:**
- Nano Color CTP (id=1) w trybie **MASTER MINI** (menu serwisowe: TRYB W SIECI C14 = MASTER MINI)
- ESP32 esp02 jako **observer**: `select.C14 Rola` = **OFF**, wszystkie `switch.VS id=2..5` = **OFF**
- Forward switch został usunięty (bus jest fizycznie wspólny — observer dostaje wszystkie ramki bez forwardingu)
- Capture przez `esphome logs` CLI (nie z UI)

**Setpointy bazowe** (zapisz aktualne z menu serwisowego Nano przed startem):
- Comfort: ____
- Eco zima: ____
- Eco chłodz: ____
- Manual: ____
- Poza domem: ____

## Capture — komenda

```powershell
ssh -i ~/.ssh/ha_ed25519 root@homeassistant `
  "docker exec addon_5c53de3b_esphome esphome logs /config/esphome/esp02.yaml --device 192.168.88.206" `
  > tests\2026-05-16_wietrzenie_sezony\log_esp02_$(Get-Date -Format yyyyMMdd_HHmm).log 2>&1
```

Zostaw okno otwarte — capture leci do końca sesji. Ctrl+C na końcu.

## Workflow

1. **Ty:** wykonujesz zmianę w menu Nano
2. **Ty:** piszesz: `zrobiłem` + krótki kontekst (np. `zrobiłem Wietrz ON`)
3. **Ja:** zapisuję marker do `markers.txt` z timestampem
4. **Ty:** czekasz **≥45 s** (5 cykli Master Mini), piszesz `ok` → ja podaję następny test
5. **Faza B** (analiza) po wszystkich testach — DIFF baseline ↔ test, per ramka

---

## Faza −1 — Pre-baseline (Nano Slave → Master Mini, nastawy %)

Stan startowy: **Nano jest w trybie Slave**, ESP=OFF, capture leci.

| Test | Stan przed | Akcja | Co logujemy |
|------|-----------|-------|-------------|
| **W−3** | Capture start, Nano=Slave | nic — pozwól lecieć **3 cykle** | Czy w ogóle coś jest na busie? (Slave nie powinien nadawać poll, ale może reagować na coś) |
| **W−2** | Nano=Slave | Zmień **Nano Slave → Master Mini** (menu serwisowe: TRYB W SIECI C14) | **KLUCZOWE** — co Nano dosyła na bus przy zmianie roli? Specjalna ramka init? Reset config? Cold-start sequence? |
| **W−1 spis** | Nano=Master Mini | Wejdź w menu serwisowe % i **spisz aktualne wartości** Naw/Wyw dla B1/B2/B3/Wietrzenie. Napisz mi je przed zmianą. | snapshot dotychczasowych nastaw |
| **W−1 set** | Nano=Master Mini | Zmień nastawy % na docelowe: **B1=30/30 · B2=31/31 · B3=32/32 · Wietrz=35/35** (Naw=Wyw dla obu) | E3#44 f[20-25] (B1/B2/B3) i f[14-15] (Wietrz?) powinny natychmiast pokazać nowe wartości |

> **Dlaczego zmiana %:** historycznie AERO przy włączeniu Wietrzenia (przez ESP-master) milkł na busie, ale fizycznie wietrzył **starymi nastawami z Nano cache**. To sugeruje że AERO trzyma własną pamięć nastaw %, niezależnie od bieżącej ramki E3. Ustawienie sensownych, rozróżnialnych nastaw (35/35 dla Wietrz vs 30-32 dla biegów) pozwoli w fazie A/B zobaczyć **kiedy** AERO bierze nowe nastawy i **co** się przełącza przy Wietrz ON.

## Faza 0 — Baseline F0 (Chłodzenie/Manual/B1/Wietrz=OFF)

| Test | Sezon | Termostat | Wentylacja | Wietrz | Bypass | Programy |
|------|-------|-----------|------------|--------|--------|----------|
| **W0** | **Chłodzenie** | **Manual** (SP=23°C, z Nano) | **B1** | **OFF** | **AUTO** | **Normal** |

> **Manual zamiast Harm:** Nano aktualnie ma Manual (T_zadana=23°C). Zostawiamy — Manual daje deterministyczny aktywny SP (bez slotów harmonogramu w EEPROM Nano). W trakcie sesji można dodać test Termostat=Harm w Fazie C jako zmienna.

> **Hipoteza bonus do W0:** f[28] aktualnie = 0x03 (bez chłodz overlay 0x08). T_pok=21.7°C < SP=23.0°C → cooling demand nieaktywne. Hipoteza: bit 0x08 = "cooling demand", nie "sezon=chłodz". Test pomocniczy: zmienić Manual na 18°C → jeśli f[28] przeskoczy na 0x0B, hipoteza potwierdzona.

> **Uwaga Chłodzenie:** AERO może autonomicznie otworzyć bypass jeśli ciepło na zewnątrz < temp pokojowa (free-cooling). To wpływa na E4(63) f[28] (bypass status) ale **nie powinno wpływać** na bity Wietrzenia w f[27]/f[28] mastera. W analizie odsiać reakcję bypass od reakcji Wietrz.

Capture 5+ cykli baseline jako punkt odniesienia.

---

## Faza A — Wietrzenie ON/OFF w 3 sezonach (one-at-a-time)

Cel: zobaczyć **per-sezon** jak zmienia się f[27]/f[28]/f[24]/E5/E3 po włączeniu Wietrzenia.

| Test | Z baseline | Zmiana | Co obserwujemy |
|------|------------|--------|----------------|
| **W1** | F0 (Chłodz) | Wietrz **OFF→ON** | **KLUCZOWE #1** — czy `+0x20` koegzystuje z chłodz overlay `0x08` w f[28]? Co dzieje się z biegiem? |
| **W2** | W1 stan | Wietrz **ON→OFF** | reset, czy stan baseline wraca w pełni |
| **W3** | W2 stan (Chłodz/OFF) | Sezon **Chłodz→Lato bez** | sezon bez Wietrz (tło) |
| **W4** | W3 stan (Lato/OFF) | Wietrz **OFF→ON** | **KLUCZOWE #2** — czy `+0x20` w Lato? f[28]? |
| **W5** | W4 stan | Wietrz **ON→OFF** | reset |
| **W6** | W5 stan (Lato/OFF) | Sezon **Lato→Zima** | sezon (znany) |
| **W7** | W6 stan (Zima/OFF) | Wietrz **OFF→ON** | Referencja — czy nadal `f[27] +0x20` w Zimie (potwierdzenie znanego) |
| **W8** | W7 stan | Wietrz **ON→OFF** | reset |

---

## Faza B — Wietrzenie × Wentylacja (w Chłodzeniu, priorytet)

Cel: czy bieg w momencie włączenia Wietrzenia wpływa na zachowanie (np. czy Wietrz nadpisuje bieg, czy się sumują, czy AERO przełącza tylko %)?

**Setup wspólny:** Sezon=**Chłodzenie**, Termostat=Harm, Programy=Normal, Bypass=AUTO.

| Test | Z baseline | Zmiana | Co obserwujemy |
|------|------------|--------|----------------|
| **W9 setup** | Po W8 (Zima) | Sezon **Zima→Chłodz**, Went=B1 | przygotowanie |
| **W9** | Chłodz/Harm/B1/OFF | Wietrz **OFF→ON** | powtórka W1 dla pewności |
| **W10 setup** | W9 stan | Wietrz **ON→OFF**, Went **B1→B2** | tło |
| **W10** | Chłodz/Harm/B2/OFF | Wietrz **OFF→ON** | Wietrz przy B2 |
| **W11 setup** | W10 stan | Wietrz **ON→OFF**, Went **B2→B3** | tło |
| **W11** | Chłodz/Harm/B3/OFF | Wietrz **OFF→ON** | Wietrz przy B3 |
| **W12 setup** | W11 stan | Wietrz **ON→OFF**, Went **B3→Stop** | tło |
| **W12** | Chłodz/Harm/Stop/OFF | Wietrz **OFF→ON** | **Czy Nano blokuje Wietrz przy Stop?** Jeśli tak — zanotuj |

---

## Faza C — Wietrzenie × Termostat (w Chłodzeniu)

Sprawdza czy tryb termostatu modyfikuje overlay Wietrzenia.

| Test | Z baseline | Zmiana | Co obserwujemy |
|------|------------|--------|----------------|
| **W13 setup** | Po W12 | Went **Stop→B1**, Wietrz=OFF | przygotowanie |
| **W13** | Chłodz/Manual/B1/OFF | Termostat **Harm→Manual**, czekaj 1 cykl, potem Wietrz **OFF→ON** | Wietrz + Manual + Chłodz (interakcja stable bit?) |
| **W14 setup** | W13 stan | Wietrz **ON→OFF**, Termostat **Manual→Urlop** | tło |
| **W14** | Chłodz/Urlop/B1/OFF | Wietrz **OFF→ON** | **Czy dozwolone w Urlop?** |

---

## Faza D — Wietrzenie w Lato bez (kombinacje)

| Test | Z baseline | Zmiana | Co obserwujemy |
|------|------------|--------|----------------|
| **W15 setup** | Po W14 | Term **Urlop→Harm**, Sezon **Chłodz→Lato bez**, Went=B1, Wietrz=OFF | przygotowanie |
| **W15** | Lato/Harm/B1/OFF | Wietrz **OFF→ON** | powtórka W4 dla pewności |
| **W16 setup** | W15 stan | Wietrz **ON→OFF**, Went **B1→B3** | tło |
| **W16** | Lato/Harm/B3/OFF | Wietrz **OFF→ON** | Wietrz+B3+Lato |
| **W17 setup** | W16 stan | Wietrz **ON→OFF**, Went **B3→Stop** | tło |
| **W17** | Lato/Harm/Stop/OFF | Wietrz **OFF→ON** | Lato+Stop+Wietrz — czy blokowane? |

---

## Powrót do baseline (koniec sesji)

| | Sezon | Term | Went | Wietrz | Bypass | Programy |
|---|-------|------|------|--------|--------|----------|
| **W99** | Zima | Harm | B1 | OFF | AUTO | Normal |

---

## Co śledzić w analizie (Faza B)

### Pola sterujące (input)
| Pole | Ramka | Hipoteza dotychczasowa (do weryfikacji) |
|------|-------|------------------------------------------|
| `f[27]` bit `0x20` | E4(29), E3(29) | Wietrz ON overlay |
| `f[27]` bity 3-4 | E4(29), E3(29) | Sezon (`0x08`=Lato, `0x10`=Chłodz) |
| `f[28]` bit `0x08` | E4(29), E3(29) | Chłodz overlay |
| `f[28]` bity 0-2 | E4(29), E3(29) | bieg (`0x03`=B1, `0x05`=B2, `0x07`=B3) |
| `f[28]` bit `0x40` | E4(29) | "stable" / trusted — sprawdzamy interakcję z Wietrz |
| `f[24]` | E4(29) | sync flag (`0x00`/`0x32`/`0x64`) |
| `f[14-15]` E3#44 | E3(29) src=0x44 | wietrzenie naw%/wyw% (zamiast f[20-25] biegów?) |
| `f[28]` E5 | E5(29) | kod UI |

### AERO E4(63) — reakcja fizyczna
| Pole | Co śledzić |
|------|-----------|
| `f[24]` (naw%) | Czy przeskakuje na **35%** (Wietrz) gdy ON, **30/31/32%** (B1/2/3) gdy OFF? |
| `f[25]` (wyw%) | jw. — różnicowanie po nastawach z W−1 set |
| `f[28]` (bypass status) | Czy się zmienia przy Wietrz ON w Chłodzeniu? (odsiać od auto-bypass) |

**Po co rozróżnialne nastawy %:** dzięki **B1=30 · B2=31 · B3=32 · Wietrz=35** (każda inna wartość) widać w E4(63) f[24-25] dokładnie który "tryb" % aktualnie AERO realizuje, nawet jeśli ramki master mówią coś innego. Jeśli AERO trzyma własny cache, zobaczymy lag (np. ramki mówią `0x20`+B1=30%, ale AERO dalej dmucha 35% z poprzedniego Wietrz).

### Pytania kluczowe sesji
1. **(W−2)** Co Nano dosyła na bus przy zmianie Slave → Master Mini? Init sequence? Cold-start handshake?
2. **(W−1 set)** Czy zmiana nastaw % w menu serwisowym widoczna od razu w E3#44 f[20-25]? AERO ją bierze natychmiast (E4(63) f[24-25]) czy z lagiem?
3. Czy bit `0x20` w f[27] jest SET w Chłodzeniu **i** w Lato bez (jak w Zimie)?
4. Czy w Chłodzeniu Wietrz ON + bieg=B1 daje `f[28] = 0x03 | 0x08 | 0x40?` lub coś innego?
5. Czy AERO faktycznie przełącza % na **35%** (Wietrz) niezależnie od sezonu? Czy w Lato/Chłodz pozostaje przy biegu (lag/blokada)?
6. Czy istnieje **kombinacja blokowana** przez Nano UI (np. Wietrz + Stop)?
7. Czy bit "stable" (`0x40`) zachowuje się przewidywalnie czy mamy nową niespodziankę?
8. Czy AERO E4(63) f[28] (bypass) zmienia się synchronicznie z Wietrz ON, czy niezależnie (auto-bypass cooling)?

---

## Wskazówki

- **≥45s między testami** (5 cykli Master Mini × 8.5s)
- **Po zmianie menu czekaj ~10s** zanim raportujesz "zrobiłem" (debounce Nano)
- **Notuj UI Nano:** jeśli ikonka wietrzenia zniknęła / pojawiła się alert / panel zachowuje się dziwnie
- **AERO E4(63) ma 1-3 cykle opóźnienia** — naw%/wyw% nie zmienia się natychmiast
- **Jeśli Nano blokuje opcję** (np. Wietrz przy Stop) — zanotuj zamiast siłować
- **Auto-bypass w Chłodzeniu** — AERO może otworzyć bypass autonomicznie (free-cooling). Wpływa na E4(63) f[28], **nie** na bity Wietrzenia w master frame

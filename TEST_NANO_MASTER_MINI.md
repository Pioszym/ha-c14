# Test Nano Master Mini — empiryczne mapowanie pól

Plan systematycznego testu cyklu Master Mini z **Nano jako master** (mniej ramek niż Master Full → łatwiej obserwować). Cel: potwierdzić bajt po bajcie które pola w których ramkach kodują:
- Set temp (Comfort / Eco zima / Eco chłodz / Manual / Poza domem) i aktywny setpoint
- Sezon (Zima / Lato bez / Chłodzenie)
- Termostat (Harmonogram / Urlop / Manual)
- Wentylacja (Stop / B1 / B2 / B3 / Wietrzenie / Harm-Urlop)
- Wietrzenie ON/OFF (overlay)
- Bypass (OFF / AUTO / ON)

## Setup

**Hardware:**
- Nano Color CTP w trybie **MASTER MINI** (menu serwisowe: TRYB W SIECI C14 = MASTER MINI)
- ESP32 esp02 jako **observer**: Rola=OFF, Forward=ON (passive bridge), `log_nano`=ON, `log_aero`=ON
- Nano slave id=5 odpięty (żeby nie zakłócał jako emiter dodatkowych ramek) — ALBO: zostawiony dla weryfikacji syncu sezonu/zegara, ale wtedy filtruj `[NANO>] f[1]==0x21` od f[3]==0x2D z parsera

**Capture:**
```bash
ssh -i ~/.ssh/ha_ed25519 root@homeassistant \
  "docker exec addon_5c53de3b_esphome esphome logs /config/esphome/esp02.yaml --device 192.168.88.206" \
  | tee test_nano_master_mini_$(date +%Y%m%d_%H%M).log
```

Zostaw streamujące, każdą zmianę poprzedź wpisem do tego samego loga przez `echo "=== T<N>: Zima→Lato ==="` w osobnym terminalu (sync przez `script` na HA jeśli logger nie ma znacznika).

**Cykl Master Mini Nano (~8.5s):**
```
#1 E4(29) src=0x21 — komenda biegu + sezon + termostat + zegar + aktywny SP
#2 E3(29) src=0x44 — TRIGGER AERO + nastawy % per bieg + znacznik biegu
   AERO E4(63) src=0x21 — odpowiedź AERO (~400ms po #2)
#3 E3(29) src=0x56 — iNEXT slot (zera)
#4 E2(29) src=0x44 — status broadcast (nieznane)
#5 E5(29) src=0x21 — 5 setpointów temp + bypass + sezon enum
#6 F0(29) src=0x44 — heartbeat
#7 81(29) src=0x44 — heartbeat
#8-10 D0/D1/D2(29) src=0x44 — slave config (statyczne ASCII "SKA")
```

Pola dynamiczne pojawiają się głównie w **#1 E4**, **#2 E3**, **#5 E5** + **AERO E4(63)**.

## Format zapisu — tabela bajtów

Dla każdego testu zapisz:
```
=== T<N>: <opis zmiany> ===
PRZED:
  E4: E4,21,XX,29,...,YY,23
  E3: E3,44,XX,29,...,YY,23
  E5: E5,21,XX,29,...,YY,23
PO:
  E4: E4,21,XX,29,...,YY,23
  E3: E3,44,XX,29,...,YY,23
  E5: E5,21,XX,29,...,YY,23
DIFF: f[N] zmiana XX→YY (oczekiwane: ...)
```

## Faza 0 — Baseline

Ustaw na Nano:
- Sezon=**Zima**
- Termostat=**Harmonogram**
- Wentylacja=**B1** (Manual? Harm? — patrz F2/F3, ważne by ustabilizować)
- Wietrzenie=**OFF**
- Bypass=**AUTO**

Capture **3 pełne cykle** (~25s). Wybierz reprezentatywny cykl jako referencyjny "BASELINE". Zapisz wszystkie ramki E4/E3/E5/AERO_E4_63 z baseline.

Parametry pomocnicze: Comfort=23.0°C, Eco zima=21.0°C, Eco chłodz=18.0°C, Manual=25.0°C, Poza domem=20.0°C (lub aktualne — ważne by je znać przed F6).

---

## Faza 1 — Sezon (3 stany, dotyka E4+E3+E5)

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T1 | Zima → **Lato bez** | E4 f[27] bit `0x08` SET · E3 f[27] z `0x01` na `0x09` · E5 f[27] z `0x00` na `0x0A` |
| T2 | Lato bez → **Chłodzenie** | E4 f[27] bity `0x10` (clear `0x08`) · E3 f[27] na `0x11` · E5 f[27] na `0x14` · E4 f[28] **+`0x08`** (Chłodz overlay na bieg) |
| T3 | Chłodzenie → **Zima** (powrót do baseline) | wszystkie sezon bity CLEAR |

Capture po każdej zmianie: 1 cykl (~9s).

**Oczekiwany boczny efekt T2 (Sezon=Chłodzenie):** aktywny setpoint może przeskoczyć z Eco zima (E5 f[10-11]) na Eco chłodz (E5 f[12-13]) — sprawdź E4 f[14-15].

---

## Faza 2 — Termostat (3 stany, głównie E4)

Wymóg: wróć do baseline (Sezon=Zima) przed F2.

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T4 | Harm → **Manual** | E4 f[27] bity 0-2: `0x00`→`0x02` · E4 f[28] **+`0x40`** (stable, jeśli korekta=0) · E4 f[24] z `0x32` na `0x64` · E4 f[14-15] zmiana na T_manual (E5 f[14-15]) |
| T5 | Manual → **Urlop** | E4 f[27] bity 0-2: `0x02`→`0x01` · E4 f[28] **−`0x40`** (clear stable) · E4 f[24] z `0x64` na `0x32` · E4 f[14-15] na T_poza_domem (E5 f[16-17])? — do potwierdzenia |
| T6 | Urlop → **Harm** (powrót) | sprawdź czy wszystkie wartości wracają do baseline F0 |

Capture po każdej zmianie: 1 cykl.

---

## Faza 3 — Wentylacja (6 stanów, głównie E4 f[28] + E5 f[28])

Per PROTOCOL §5.3 menu Wentylacja Nano ma 6 opcji: **Harmonogram / Harm-Urlop / B3 / B2 / B1 / Stop**. (Wietrzenie to **osobne menu** Nano, overlay — testowane w F7, NIE w Wentylacji.)

Zmieniaj sekwencyjnie:

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T7 | B1 → **B2** | E4 f[28] bity 0-2: `0x03`→`0x05` (Master encoding) · E5 f[28] zmiana (kod UI) · E3 f[28] bity 0-2 zmiana |
| T8 | B2 → **B3** | E4 f[28]: `0x05`→`0x07` · pozostałe analogicznie |
| T9 | B3 → **Stop** | E4 f[28]: `0x07`→`0x01` |
| T10 | Stop → **Harmonogram** | E4 f[28] bieg ze slotu harmonogramu (np. `0x03` jeśli aktualny slot=B1) · zachowanie wg PROTOCOL §5.3: identyczne jak Manual+bieg_z_slotu (slave nie odróżnia) · zmienia się dynamicznie wraz z rotacją slotu |
| T11 | Harmonogram → **Harm-Urlop** | E4 f[28] **−`0x40`** (clear stable, jeśli było SET) · E4 f[24] na `0x32` (unsynced) · bieg dalej rotuje wg harmonogramu — patrz §4 PROTOCOL `g_harm_urlop` |
| T12 | Harm-Urlop → **B1** (powrót do baseline) | sprawdź pełen reset |

**Note:** Wentylacja=Harmonogram i Wentylacja=Harm-Urlop oba **rotują bieg wg harmonogramu** (zmiana slotu eco z B1→B2 natychmiast zmienia `f[28]` z `0x03`→`0x05`). Różnią się tylko bitem `0x40` + `f[24]`. Capture po T10 i T11 musi trwać dłużej (~2-3 cykle minimum) by zaobserwować rotację albo wymusić zmianę slotu w Nano.

---

## Faza 4 — Bypass (3 stany, E5 f[25])

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T13 | AUTO (`0x61`) → **OFF** | E5 f[25] z `0x61` na `0x60` · po cyklu AERO E4(63) f[28] na `0x40` (zamknięty) |
| T14 | OFF → **ON** | E5 f[25] na `0x62` · AERO f[28] na `0x60` (otwarty) |
| T15 | ON → **AUTO** (powrót) | E5 f[25] na `0x61` |

Capture: 1 cykl Mini + 1 cykl AERO E4(63) reaction (po zmianie ~5s opóźnienie zanim AERO mechanicznie zareaguje na bypass).

---

## Faza 5 — Setpointy temperatur (E5 f[8-17])

Każdy z 5 setpointów osobno. Zmiana o 0.5°C w obie strony żeby zaobserwować zmianę bajtu.

Wymóg: zacznij z baseline, znaj aktualne wartości.

| Test | Setpoint | Zmiana | Oczekiwane pole E5 |
|------|----------|--------|---------------------|
| T16 | Comfort | 23.0 → **22.5** | E5 f[8-9] zmiana o `−0x05` (T = ((H*128+L%128)−2000)/10) |
| T17 | Comfort | 22.5 → **23.0** (powrót) | f[8-9] +`0x05` |
| T18 | Eco zima | 21.0 → **20.5** | E5 f[10-11] zmiana |
| T19 | Eco zima | 20.5 → 21.0 | f[10-11] reset |
| T20 | Eco chłodz | 18.0 → **17.5** | E5 f[12-13] zmiana |
| T21 | Eco chłodz | 17.5 → 18.0 | f[12-13] reset |
| T22 | Manual | 25.0 → **24.5** | E5 f[14-15] zmiana |
| T23 | Manual | 24.5 → 25.0 | f[14-15] reset |
| T24 | Poza domem | 20.0 → **19.5** | E5 f[16-17] zmiana |
| T25 | Poza domem | 19.5 → 20.0 | f[16-17] reset |

**Encoding temperatury (potwierdzić):**
```
T = ((H * 128) + (L % 128) - 2000) / 10
```
Np. 23.0°C → `(23.0*10 + 200) = 430` → H=`0x11`, L=`0x36` → `0x11,0x36`.

---

## Faza 6 — Aktywny setpoint (E4 f[12-13] + E4 f[14-15])

Aktywny setpoint w E4(29) jest **kopią** odpowiedniego setpointu z E5 zależnie od Termostat × Sezon. Cross-tabela do potwierdzenia:

| Termostat | Sezon | Oczekiwane E4 f[14-15] = |
|-----------|-------|--------------------------|
| Manual | dowolny | E5 f[14-15] (T_manual) |
| Harm | Zima | E5 f[10-11] (T_eco_zima)? lub E5 f[8-9] (T_comfort)? |
| Harm | Lato bez | ??? |
| Harm | Chłodzenie | E5 f[12-13] (T_eco_chłodz)? |
| Urlop | dowolny | E5 f[16-17] (T_poza_domem) |

Test:
- T26: Termostat=Manual + Sezon=Zima → ustaw Manual=25.5, sprawdź E4 f[14-15] = E5 f[14-15]
- T27: Termostat=Harm + Sezon=Zima → ustaw Comfort=23.5, sprawdź E4 f[14-15] (czy = E5 f[8-9]?)
- T28: Termostat=Harm + Sezon=Chłodzenie → ustaw Eco chłodz=17.5, sprawdź E4 f[14-15]
- T29: Termostat=Urlop → ustaw Poza_domem=19.5, sprawdź E4 f[14-15]

**Dodatkowo:** E4 f[12-13] vs f[14-15]. PROTOCOL §3.2 nie precyzuje czy są identyczne. Sprawdź w każdej kombinacji.

---

## Faza 7 — Wietrzenie ON/OFF jako overlay (jeśli osobne od Wentylacja=Wietrzenie)

Wymóg: Wentylacja=B1 (lub inna ≠ Wietrzenie).

| Test | Zmiana | Oczekiwane DIFF |
|------|--------|------------------|
| T30 | Wietrz overlay=OFF → **ON** | E4 f[27] **+`0x20`** · E3 f[27] **+`0x20`** · E5 f[27]? · E4 f[28] bez zmian (bieg dalej) · E3#44 nastawy % przełączają z B1 na Wietrzenie (f[14-15] %wiet zamiast f[20-25] %B1)? |
| T31 | Overlay=ON → OFF | reset wszystkich bitów `0x20` |

---

## Faza 8 — Programy (Normal / Poza domem / Urlop) — opcjonalne

| Test | Zmiana | Oczekiwane |
|------|--------|------------|
| T32 | Normal → **Poza domem** | E4 f[5] **+`0x04`** · setpoint na T_poza_domem |
| T33 | Poza domem → **Urlop** | E4 f[28] = `0x40` (validity=0, sam stable bit) · wentylator Stop |
| T34 | Urlop → Normal (powrót) | reset f[5] i f[28] |

---

## Format wyników

Po każdej fazie zapisz w osobnej sekcji `RESULTS_<faza>.md` lub w jednym pliku z anchor'ami:

```markdown
## T1: Zima → Lato bez (godz HH:MM:SS)

PRZED (baseline):
  E4: E4,21,1F,29,0A,40,00,01,12,30,7E,00,11,36,11,36,7E,7E,7E,7E,7E,7E,7E,14,32,01,1A,00,03,23
  E3: E3,44,25,29,32,00,05,0A,28,1C,2A,1E,01,17,1E,1E,18,14,00,24,20,21,22,23,24,23,20,01,53,23
  E5: E5,21,49,29,00,00,10,32,11,36,11,22,11,04,11,4A,11,18,00,30,7E,00,7E,00,00,61,00,00,15,23

PO:
  E4: ...
  E3: ...
  E5: ...

DIFF:
  E4 f[27]: 0x00 → 0x08 ✓ (oczekiwane: bit 3 SET dla Lato bez)
  E3 f[27]: 0x01 → 0x09 ✓
  E5 f[27]: 0x00 → 0x0A ✓
  E4 f[14-15]: bez zmian (Termostat=Harm, sezon nie wpływa na active SP w tej kombinacji?)

WNIOSKI: ...
```

## Lista pytań otwartych do potwierdzenia testem

1. **E5 f[28] kod UI** — PROTOCOL §3.7 / §7 wspomina obserwowane wartości `0x00`-`0x1F`. Pełen mapping zależy od Termostat × Sezon × Bieg × Wentylacja. Test F1+F2+F3 + F8 da macierz.
2. **f[5] bit `0x04`** — Programy=Poza domem (PROTOCOL §3.2). Potwierdź F8 T32.
3. **f[26] w E4** — w cyklu Master Full rotuje (rok/miesiąc/dzień). W Mini stała? Sprawdź wszystkie cykle baseline.
4. **E2(29) src=0x44** — payload niemal stały. Czy zmienia się przy ruchu Termostatu / Sezonu? Sprawdź F1+F2.
5. **E4 f[24]** (`0x32`/`0x64`) — sync flag. Czy zawsze ścisle koreluje z `f[28]` bit `0x40`? Czy są stany rozbieżne?
6. **f[12-13] vs f[14-15]** w E4 — czy zawsze identyczne (kopia setpointu) czy mogą się różnić?
7. **Wietrzenie 100%/95% domyślne** w nastawach — czy są stałe Nano czy konfigurowalne?
8. **Bypass: czas reakcji AERO** po zmianie E5 f[25]. Zmierz dokładnie (T13/T14).

## Wskazówki praktyczne

- Cykl Master Mini ~8.5s — zostaw przynajmniej **15s** między zmianami żeby złapać 2 pełne cykle (przed/po).
- Zmieniaj **jedną zmienną na raz** — zmiana 2+ jednocześnie miesza diff.
- Niektóre kombinacje są zabronione w menu Nano (np. Sezon=Lato bez + Wietrzenie ON może być niedozwolone) — odnotuj jeśli Nano nie pozwoli.
- Po każdej fazie wracaj do baseline (Faza 0) — bezpieczna izolacja od pozostałych faz.
- AERO E4(63) reaguje wolniej (1-2 cykle opóźnienia) na zmiany bypass i biegu — mierz **po** stabilizacji.

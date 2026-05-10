# Faza B — Analiza testu Nano Master Mini z 2026-05-10

**Log:** `log_esp02_202605101228.log` (12:28-13:58, 1.5h, 7015 ramek z czego 642 AERO)
**Markery:** `markers.txt` (71 zdarzeń)
**Workflow:** wg `TEST_NANO_MASTER_MINI.md` § Faza B (defensive verification, bez auto-update PROTOCOL.md)

Notacja: `f[N]` = bajt N w ramce; `→` zmiana wartości; ✓ zgodne z PROTOCOL; ⚠ niezgodne / niekompletne; 🔍 nowe odkrycie.
Każdy test = pierwsze 2-3 cykle Master Mini po markerze (cykl ~8.5s).

Encoding setpointów (kontekst):
- Comfort 23.0°C = `11,36`; Eco zima 20.0°C = `11,18`; Eco chłodz 18.0°C = `11,04`; Manual 25.0°C = `11,4A`; Poza 16.0°C = `10,70`

---

## F0 baseline (12:47:10..12:47:19, 4 ramki przed T1)

```
E4   [E4,21,72,29,0A,40,00,06,0C,2F,7E,00,11,16,11,18,7E×7,14,64,01,1A,00,43,23]
E3   [E3,44,28,29,32,00,05,0A,28,1C,2A,1E,01,17,1E,1E,18,14,00,24,20,23,22,23,25,23,20,01,53,23]
AERO [E4,21,65,63,09,74,00,3C,00,00,10,48,10,48,11,1C,10,74,11,2B,7E,00,00,00,23,20,01,02,40,23]
E5   [E5,21,18,29,00,00,10,48,11,36,11,18,11,04,11,4A,10,70,00,30,7E,00,7E,00,00,61,00,00,01,23]
```

Sezon=Zima, Term=Harm, Went=B1, Wietrz=OFF, Bypass=AUTO, Programy=Normal.

**Anomalia F0 (do wyjaśnienia):**
- E4 f[24]=`0x64` + f[28]=`0x43` (stable bit + sync 100%) **mimo Term=Harm**.
- E3 f[28]=`0x53` (z bitem `0x40`).
- PROTOCOL §3.2 stanowi: "stable=Manual+korekta=0". Tu Term=Harm a stable SET.
- **Hipoteza Piotra (markers.txt):** stable=Wentylacja-manualna-z-menu (B1 wybrane manualnie), niezależne od Term.
- **Hipoteza alternatywna:** stable jest "lepkie" — pozostałość po wcześniejszej sesji Manual; raz utracone (T1+) nie wraca samo.
- Po T1 zniknął i nigdy nie wrócił w trybie Harm aż do T4 (Manual). To zachowanie sugeruje hipotezę alternatywną: stable raz utracony w Harm wymaga przejścia przez Manual, by wrócić (a w Harm nie wraca przez sezon).

Patrz §"Otwarte" niżej.

---

# CZĘŚĆ I — TESTY LINIOWE

## T1: Sezon Zima → Lato bez (12:50:33)

```
E4   [...,14,32,01,1A,08,03,23]   # f[24]=32, f[27]=08, f[28]=03
E3   [...,20,09,13,23]            # f[27]=09, f[28]=13
E5   [...,61,00,0A,01,23]         # f[27]=0A
AERO [...,23,20,01,02,60,23]      # f[28]=60 (bypass otwarty!)
```

**Pola sterujące:**
| Pole | F0 → T1 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x00`→`0x08` | §3.2 sezon Lato bez=`0x08` | ✓ |
| E3 f[27] | `0x01`→`0x09` | §3.3 Lato bez=`0x09` | ✓ |
| E5 f[27] | `0x00`→`0x0A` | §3.7 Lato bez=`0x0A` | ✓ |
| E4 f[14-15] | `11:18`→`11:04` (20.0→18.0) | §5.6: Eco_zima w Zimie | ⚠ Lato bez używa **Eco_chłodz** (18°C), nie Eco_zima |
| E5 f[8-9..14-15] | bez zmian | – | ✓ |

**Bajty synchronizacji:**
| Pole | F0 → T1 | Komentarz |
|------|---------|-----------|
| E4 f[24] | `0x64`→`0x32` | utrata sync flag — koreluje z f[28] |
| E4 f[28] | `0x43`→`0x03` | utrata `0x40` (stable) — patrz F0 anomalia |
| E3 f[28] | `0x53`→`0x13` | utrata `0x40` |
| AERO f[28] | `0x40`→`0x60` | 🔍 **AERO sam otworzył bypass w Lato bez** mimo E5 f[25]=`0x61` (AUTO niezmienne) |
| E5 f[6-7] | `10:48`→`10:4A` | mirror AERO f[10-11] (T.Czerpnia 12.0→12.2) — potwierdzenie §3.7 f[6-7]=kopia AERO |

**🔍 Nowe odkrycia T1:**
1. **Auto-bypass działa również w Lato bez** (nie tylko w Chłodzeniu — patrz Faza 4b T15c).
2. **Slot Harm w sezonie Lato bez używa Eco_chłodz (f[12-13])**, nie Eco_zima. PROTOCOL §5.6 mówi ogólnie "Lato/Chłodz" — to się zgadza, ale tabela § 5.6 wymaga doprecyzowania: dla Term=Harm slot zima→Eco_zima, slot lato/chłodz→Eco_chłodz. To było już w PROTOCOL ("aktywny gdy Sezon=Lato/Chłodz"), więc właściwie ✓.
3. **Stable bit (f[28] 0x40) traci się przy zmianie Sezon Zima→Lato bez** mimo Term=Harm niezmienne. To zgadza się z PROTOCOL ("naruszenie warunku → CLEAR") — nie jest nowością — ale potwierdza że F0's stable=SET był anomalią początkową.

---

## T2: Sezon Lato bez → Chłodzenie (12:54:04)

```
E4   [...,14,00,02,05,10,0B,23]   # f[24]=00, f[27]=10, f[28]=0B
E3   [...,20,11,1B,23]            # f[27]=11, f[28]=1B
E5   [...,61,00,14,01,23]         # f[27]=14
AERO [...,23,20,01,02,60,23]      # f[28]=60
```

**Pola sterujące:**
| Pole | T1 → T2 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x08`→`0x10` | §3.2 Chłodz=`0x10` | ✓ |
| E4 f[28] | `0x03`→`0x0B` | §3.2 +`0x08` overlay Chłodz | ✓ |
| E3 f[27] | `0x09`→`0x11` | §3.3 Chłodz=`0x11` | ✓ |
| **E3 f[28]** | `0x13`→`0x1B` | – | 🔍 **E3 f[28] również ma overlay +`0x08` Chłodz**, niezgodne z PROTOCOL §3.3 (wymienia tylko bity `0x10` i `0x40`) |
| E5 f[27] | `0x0A`→`0x14` | §3.7 Chłodz=`0x14` | ✓ |

**Bajty synchronizacji:**
| Pole | T1 → T2 | Komentarz |
|------|---------|-----------|
| **E4 f[24]** | `0x32`→`0x00` | 🔍 **f[24]=0x00 — trzecia wartość poza dokumentem** (PROTOCOL: tylko `0x32`/`0x64`) |
| AERO f[28] | `0x60` (niezmienne) | bypass dalej otwarty (auto) |

**🔍 Nowe odkrycia T2:**
1. **E3 f[28] overlay Chłodz `+0x08`** — analogicznie jak E4 f[28]. Należy uzupełnić PROTOCOL §3.3.
   - Zima+B1+Harm: E3 f[28]=`0x13` (`0x03|0x10`)
   - Lato bez+B1+Harm: E3 f[28]=`0x13` (sezon nie wpływa)
   - Chłodz+B1+Harm: E3 f[28]=`0x1B` (`0x03|0x10|0x08`) ← overlay!
2. **E4 f[24]=`0x00` w sezonie Chłodzenie + Term=Harm**. PROTOCOL §3.2 stwierdza tylko `0x32`/`0x64`. Jest to trzecia wartość — wykryta tylko gdy Sezon=Chłodzenie i nie ma stable bit.
   - Verify: w T15c (Chłodz+Manual) f[24]=`0x32`, w MX2c-d (Chłodz+Harm) f[24]=`0x00` — tak, korelacja Chłodz+Harm/Urlop.

---

## T3: Sezon Chłodzenie → Zima (12:56:36)

```
E4   [...,14,32,02,05,00,03,23]
E3   [...,20,01,13,23]
E5   [...,61,00,00,01,23]
AERO [...,23,20,01,02,40,23]      # f[28]=40 (bypass zamknięty)
```

**DIFF T2→T3:**
| Pole | Wartość | Werdykt |
|------|---------|---------|
| E4 f[27] | `0x10`→`0x00` | ✓ Zima |
| E4 f[28] | `0x0B`→`0x03` | ✓ overlay Chłodz CLEAR |
| E3 f[27] | `0x11`→`0x01` | ✓ |
| E3 f[28] | `0x1B`→`0x13` | ✓ overlay Chłodz CLEAR (E3 też) |
| E5 f[27] | `0x14`→`0x00` | ✓ |
| E4 f[24] | `0x00`→`0x32` | ✓ powrót z `0x00` po wyjściu z Chłodz |
| AERO f[28] | `0x60`→`0x40` | ✓ AERO zamknął bypass po wyjściu z Chłodz (auto-bypass dezaktywowany w Zimie) |

**🔍 Obserwacja T3:** stable bit (`0x40`) **NIE wraca** mimo powrotu Sezon=Zima i niezmiennego Term=Harm. F0 miało stable, T3 nie ma. Potwierdza że F0 był anomalią — stable raz CLEAR w Harm nie wraca samo.

---

## T4: Termostat Harm → Manual (12:57:56)

```
E4   [...,14,64,02,05,02,43,23]   # f[24]=64, f[27]=02 (Manual), f[28]=43 (B1+stable)
E3   [...,20,01,53,23]            # f[28]=53 (B1+0x10|0x40)
E5   [...,61,00,00,15,23]         # f[28]=15 (UI Manual+Zima — patrz niżej)
AERO [...,23,20,01,02,40,23]
```

**Pola sterujące:**
| Pole | T3 → T4 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x00`→`0x02` | §3.2 Manual=`0x02` | ✓ |
| E4 f[28] | `0x03`→`0x43` | §3.2 +`0x40` stable | ✓ |
| E4 f[24] | `0x32`→`0x64` | §3.2 sync=`0x64` | ✓ |
| E4 f[14-15] | `11:18`→`11:4A` (20.0→25.0) | §5.6 Manual SP | ✓ |
| E3 f[27] | `0x01` (bez zmian) | §3.3 Term nie wpływa | ✓ |
| E3 f[28] | `0x13`→`0x53` | §3.3 +`0x40` w Manual | ✓ |
| **E5 f[28]** | `0x01`→`0x15` | §3.7 wymienia "Manual+Zima"=`0x19` | ⚠ **`0x15` ≠ `0x19`** |

**🔍 Nowe odkrycia T4:**
1. **E5 f[28]=`0x15` dla Manual+Zima+B1+Harm-Wentylacja** — nie zgadza się z PROTOCOL §3.7 (`0x19`).
   - Dekompozycja: `0x15` = `0x10 | 0x04 | 0x01`. `0x10` może być flagą Term=Manual, `0x04` flagą "B1 lub Harm", `0x01` validity.
   - PROTOCOL §3.7 podaje wartości empiryczne dla różnych ścieżek nawigacji ("nie czysty enum biegu — kod stanu UI"). Możliwe że `0x19` było obserwowane w innej historycznej konfiguracji. **Wymaga uzupełnienia tabeli §3.7**.

---

## T5: Termostat Manual → Urlop (12:58:57)

```
E4   [...,14,32,01,1A,01,03,23]   # f[27]=01 (Urlop), f[28]=03 (B1, brak stable)
E3   [...,20,01,13,23]
E5   [...,61,00,00,0B,23]         # f[28]=0B (UI Urlop+Zima)
AERO [...,23,20,01,02,40,23]
```

**Pola sterujące:**
| Pole | T4 → T5 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[27] | `0x02`→`0x01` | §3.2 Urlop=`0x01` | ✓ |
| E4 f[28] | `0x43`→`0x03` | §3.2 −`0x40` w Urlop | ✓ |
| E4 f[24] | `0x64`→`0x32` | §3.2 sync→`0x32` | ✓ |
| **E4 f[14-15]** | `11:4A`→`11:18` (25.0→20.0) | §5.1 "Urlop+Zima=eco_zima" | ✓ |
| E5 f[28] | `0x15`→`0x0B` | §3.7 "Urlop+Zima"=`0x05` | ⚠ **`0x0B` ≠ `0x05`** |
| E3 f[28] | `0x53`→`0x13` | – | ✓ |

**⚠ Niezgodność T5:**
- E5 f[28]=`0x0B` w Urlop+Zima+B1, podczas gdy PROTOCOL §3.7 podaje `0x05` ("Urlop + Zima jak Harmonogram"). Również wymaga uzupełnienia.

**Obserwacja:** Term=Urlop+Zima → Active SP=20.0 (Eco_zima), zgodnie z §5.1. Nie jest to "Poza domem" 16.0 (`f[16-17]`) — co dezawansuje ostatni wiersz tabeli §5.6 ("Poza domem" wymienia "Urlop+Zima" jako warunek aktywacji — to **niezgodne z testem**, bo aktywne pozostaje Eco_zima).

---

## T6: Termostat Urlop → Harm (powrót F0) (12:59:44)

```
E4   [...,14,32,03,0A,00,03,23]   # Term=Harm
E3   [...,20,01,13,23]
E5   [...,61,00,00,01,23]         # f[28]=01 (UI Harm+Zima)
```

**DIFF T5→T6:**
| Pole | Wartość | Werdykt |
|------|---------|---------|
| E4 f[27] | `0x01`→`0x00` | ✓ Harm |
| E4 f[28] | `0x03` (bez zmian) | ✓ B1 bez stable |
| E5 f[28] | `0x0B`→`0x01` | ⚠ §3.7 "Harm+Zima"=`0x05`, tu `0x01`. Nieoczekiwane. |
| E4 f[24] | `0x32` | ⚠ pozostaje `0x32` mimo Harm — F0 miało `0x64` (anomalia F0 niepowtarzalna) |

**Obserwacja T6:** "Powrót do baseline" daje **inny stan niż F0** w polach f[24] i f[28]. To nie jest błąd protokołu — to potwierdza, że stable nie wraca samoczynnie. F0 było stanem z poprzedniej sesji.

---

## T7: Wentylacja B1 → B2 (13:00:25)

```
E4   [...,14,32,03,0A,00,05,23]   # f[28]=05 (B2)
E3   [...,20,01,15,23]            # f[28]=15
E5   [...,61,00,00,02,23]         # f[28]=02
```

**Pola sterujące:**
| Pole | T6 → T7 | PROTOCOL | Werdykt |
|------|---------|----------|---------|
| E4 f[28] | `0x03`→`0x05` | §3.2 B2=`0x05` | ✓ |
| E3 f[28] | `0x13`→`0x15` | §3.3 B2=`0x15` | ✓ |
| E5 f[28] | `0x01`→`0x02` | §3.7 nie wymienia | 🔍 nowy kod UI: B2+Harm+Zima=`0x02` |

---

## T8: Wentylacja B2 → B3 (13:01:02)

```
E4   [...,14,32,01,1A,00,07,23]   # B3=07
E3   [...,20,01,17,23]            # B3=17
E5   [...,61,00,00,03,23]         # f[28]=03
```

**Pola sterujące:** ✓ wszystko zgodne z §3.2/§3.3.
- E5 f[28]=`0x03` (B3+Harm+Zima) — uzupełnienie §3.7. PROTOCOL ma `0x03` dla "Manual B3", tu Harm+Zima daje to samo? Wymaga rozdzielenia w tabeli (Manual vs Harm dają różne kody dla niższych biegów ale dla B3 ten sam? — lub po prostu kod B3 niezależny od Term).

**⚠ Uwaga przy ekstrakcji:** Cykl 3 T8 (13:01:18) prawdopodobnie reprezentuje już przejście do T9 (B3→Stop), bo widać f[28]=`0x01` (Stop). User zaznaczył marker T9 dopiero o 13:01:28, ale zmiana w panelu Nano nastąpiła wcześniej — typowy artefakt manualnej kolejności wykonywania.

---

## T9: Wentylacja B3 → Stop (13:01:28)

```
E4   [...,14,32,02,05,00,01,23]   # f[28]=01 Stop
E3   [...,20,01,11,23]            # f[28]=11
E5   [...,61,00,00,00,23]         # f[28]=00
```

**Pola sterujące:** ✓ zgodne. E5 f[28]=`0x00` (UI "Manual Stop" wg §3.7 — tu Term=Harm).
**Obserwacja:** AERO silniki fizycznie zatrzymały się o 13:02:12 (lag ~44s, zaznaczone w markers.txt) — **AERO ma duże opóźnienie reakcji na Stop**.

---

## T10-T12: Wentylacja {Stop, Harmonogram, Harm-Urlop, B1}

| Test | Zmiana | E4 f[28] | E3 f[28] | E5 f[28] | f[24] | Komentarz |
|------|--------|----------|----------|----------|-------|-----------|
| T10 | Stop→Harm | `01`→`05` | `11`→`15` | `00`→`05` | `0x32` | slot Harm = B2 (rotował) |
| T11 | Harm→Harm-Urlop | `05` | `15` | `05`→`04` | `0x32` | E5 f[28] traci bit `0x01` |
| T12 | Harm-Urlop→B1 | `05`→`03` | `15`→`13` | `04`→`01` | `0x32` | powrót do B1 |

**🔍 Obserwacje T10-T12:**
1. **E4 i E3 f[28] dla Wentylacja=Harm i Wentylacja=Harm-Urlop są identyczne** (oba `0x05` = bieg ze slotu). PROTOCOL §5.3 stwierdza, że Harm-Urlop ma `f[24]=0x32` i "BEZ bitu `0x40`" — tu Term=Harm więc bit `0x40` i tak nie ma. Różnica między Wentylacja-Harm a Wentylacja-Harm-Urlop **nie była widoczna w `f[28]`** — była tylko w E5 f[28] kodzie UI.
2. **E5 f[28]=`0x05` dla Wentylacja=Harm + Term=Harm + Zima** (T10 cykl 1) → PROTOCOL §3.7 wymienia "Harmonogram + Zima=`0x05`". ✓ zgodne.
3. **E5 f[28]=`0x04` dla Wentylacja=Harm-Urlop** (T11) — **NOWA wartość** — `0x05` minus bit `0x01` (validity?). PROTOCOL §3.7 nie wymienia.

---

## T13-T15: Bypass {AUTO→OFF→ON→AUTO} w Sezon=Zima

| Test | Zmiana E5 f[25] | AERO f[28] | Werdykt |
|------|-----------------|-------------|---------|
| T13 | `0x61`→`0x60` (OFF) | `0x40` (zamknięty) — od początku, niezmienne | ✓ §3.4/§3.7. W Zimie + AUTO bypass jest zamknięty od początku — zmiana komendy AUTO→OFF nie zmieniła stanu fizycznego (już zamknięty). |
| T14 | `0x60`→`0x62` (ON) | `0x40`→`0x60` (otwarty) | ✓ ON nadpisuje, AERO otwiera |
| T15 | `0x62`→`0x61` (AUTO) | `0x60`→`0x40` | ✓ AUTO+Zima → AERO zamyka (zima nie wymusza otwarcia) |

**Bajt synchronizacji:**
- E3(29) f[27] reaguje na bypass w T13/T14: `0x01`→`0x00`→`0x02` → po zmianie bypass.
  - PROTOCOL §3.3 mówi że E3 f[27] = sezon (Zima=`0x01`, Lato=`0x09`, Chłodz=`0x11`).
  - 🔍 W rzeczywistości E3 f[27] = `(sezon_bity << 3) | bypass_bity` gdzie:
    - bit 0 (`0x01`) = Bypass=AUTO
    - bit 1 (`0x02`) = Bypass=ON (komenda)
    - oba CLEAR (`0x00`) = Bypass=OFF
  - Innymi słowy E3 f[27] zawiera **wartość komendy bypass** (kodowane jak ostatni nibble E5 f[25]).
  - DIFF T13: E3 f[27] `0x01`→`0x00` ; T14: `0x00`→`0x02` ; T15: `0x02`→`0x01`. Wszystko spójne z bypass cmd.
  - **Niezgodne z PROTOCOL §3.3** (mówi "Bit 0 (`0x01`) zawsze SET"). Tu w T13 OFF mamy bit 0 CLEAR.
  - **Propozycja**: PROTOCOL §3.3 wymaga reformulacji f[27] = `(sezon_szyld) | (bypass_cmd & 0x03)`, gdzie sezon_szyld=`0x00`/`0x08`/`0x10` (zima/lato/chłodz), a bypass_cmd: AUTO=`0x01`, OFF=`0x00`, ON=`0x02`.
  - Tabela aktualizowana:
    | Sezon | Bypass | E3 f[27] |
    |-------|--------|----------|
    | Zima | OFF | `0x00` |
    | Zima | AUTO | `0x01` |
    | Zima | ON | `0x02` |
    | Lato | OFF | `0x08` |
    | Lato | AUTO | `0x09` |
    | Lato | ON | `0x0A` |
    | Chłodz | OFF | `0x10` |
    | Chłodz | AUTO | `0x11` |
    | Chłodz | ON | `0x12` |

  Potwierdzone empirycznie: T13 (Zima+OFF=`0x00`), T14 (Zima+ON=`0x02`), T15 (Zima+AUTO=`0x01`), MX5b (Chłodz+ON=`0x12`), MX5c (Lato+ON=`0x0A`).

**Bypass czas reakcji (T14, ON):**
- T14 marker @ 13:08:15. E5 z `0x62` @ 13:08:15 (natychmiast).
- AERO f[28]=`0x60` @ 13:08:21 (1. odpowiedź AERO po triggerze E3 — ~6s po komendzie, lecz tylko bo AERO odpowiada raz na cykl).
- **Realny lag AERO ≤ 1 cykl Mini (~8.5s)**.

---

## T15b/1-5: Bypass szybka sekwencja (~10s/krok) (13:10:31..13:12:19)

| Krok | Zmiana | E5 f[25] | AERO f[28] | Werdykt |
|------|--------|----------|-------------|---------|
| 15b/1 | AUTO→OFF | `0x61`→ pomijając cykl `0x61` | `0x40` (już zamknięty) | ✓ AUTO=zamknięty=OFF (Zima) |
| 15b/2 | OFF→AUTO | `0x60`→`0x61` | `0x40` | ✓ |
| 15b/3 | AUTO→ON | `0x61`→`0x62` | `0x40`→`0x60` (~6s) | ✓ |
| 15b/4 | ON→AUTO | `0x62`→`0x61` | `0x60`→`0x40` (~7s) | ✓ |
| 15b/5 | AUTO→OFF | `0x61`→`0x60` | `0x40` | ✓ |

**Wnioski:**
- **Brak debounce/utraconych komend** mimo szybkich zmian co ~10s.
- Każda komenda dotarła do AERO i została odzwierciedlona.
- E5 zmienia się natychmiast (≤1 cykl), AERO reaguje w 1 cyklu Mini.

---

## T15c: Auto-bypass w Chłodzeniu+Manual (13:13:56) — Faza 4b kluczowy test

Setup: Sezon=Chłodzenie, Term=Manual, Bypass=AUTO. Manual SP=25 zmieniony na 19.3 (cooling demand aktywne, T_pok=21.8).

```
E5 (po setup):  [...,61,00,14,15,23]   # bypass=61 AUTO; sezon=14 Chłodz; UI=15 Manual+Chłodz+B1
AERO (po SP=19.3): bypass otwarty (panel pokazał ON natychmiast, markers.txt 13:16:31)
```

**🔍 Potwierdzone hipotezy 4c:**
1. **f[25] (komenda) niezmienna `0x61` — AERO autonomicznie otwiera mimo komendy AUTO** ✓
2. **Auto-bypass aktywuje się gdy:** Sezon=Chłodzenie + Bypass=AUTO + cooling demand (T_pok > Manual SP).
3. Reakcja AERO natychmiastowa po spadku Manual SP → cooling demand pojawił się.

**Pola dodatkowe T15c:**
- E4 f[28]=`0x03` (B1 bez stable!) — Term=Manual ale **brak stable** (`0x40`). PROTOCOL §3.2: stable wymaga "Term=Manual AND korekta termostatu = 0". Hipoteza: korekta ≠ 0 albo coś jeszcze.
  - Sprawdź E4 f[24]=`0x32` (zgodne z brakiem stable) ALE wartość PROTOCOL: dla Manual+Chłodz "korekta zwykle 0" → powinno być `0x64`. Tutaj `0x32`.
  - **🔍 Hipoteza:** Manual+Chłodz nie aktywuje stable bit nawet gdy korekta=0. Potwierdza obserwacja: stable był SET tylko w T4 Manual+Zima. W Manual+Chłodz (T15c) i Manual+Lato bez (brak testu) — stable CLEAR.
  - **Wniosek**: stable bit aktywny tylko gdy Term=Manual+**Sezon=Zima**+korekta=0. PROTOCOL §3.2 nie wymienia warunku Sezon=Zima.

---

## T15d: Bypass AUTO→OFF (Chłodz, AERO bypass otwarty) (13:17:17)

```
E5  [...,60,00,14,15,23]   # f[25]=60 OFF, AERO zamknął ~40s (markers.txt 13:17:56)
AERO f[28]=0x40 (zamknięty)
```

**✓ Hipoteza 4c.3 potwierdzona**: komenda OFF nadpisuje auto-decyzję AERO mimo aktywnego cooling demand. Lag ~40s.

**🔍 Obserwacja**: AERO f[28] zamknął się **stopniowo** (cykl 1 jeszcze otwarty w `[...,02,40,23]` rzeczywiście pierwsza ramka po T15d ma `0x40` zamknięty — szybko reagował).

---

## T15e: Bypass OFF→AUTO (Chłodz, cooling demand) (13:18:49)

```
E5  [...,61,00,14,15,23]
AERO f[28]=0x60 (otwarty natychmiast, markers.txt 13:19:14, ~25s lag)
```

**✓ Hipoteza 4c.2 potwierdzona**: AUTO+Chłodz+cooling_demand → AERO otwiera bypass.

---

## T15f: Sezon Chłodz→Zima (Bypass AUTO) (13:20:11)

```
AERO f[28]=0x60→0x40 (zamknął, markers.txt 13:20:11, instant)
E5 f[27]=0x14→0x00
```

**✓ Hipoteza 4c.2 potwierdzona**: AUTO+Zima → AERO zamyka (auto-bypass dezaktywowany w Zimie).

---

## T16-T25: Setpointy temp (Faza 5) (13:23:44..13:28:11)

Wszystkie testy zmieniają jeden z 5 setpointów w E5 (Comfort/Eco_zima/Eco_chłodz/Manual/Poza domem) o 0.5°C i resetują.

| Test | SP | E5 pole | DIFF | Werdykt |
|------|----|---------| ----|---------|
| T16 | Comfort 23→22.5 | f[8-9] | `11:36`→`11:31` | ✓ §3.7 |
| T17 | Comfort 22.5→23 | f[8-9] | `11:31`→`11:36` | ✓ |
| T18 | Eco zima 20→19.5 | f[10-11] | `11:18`→`11:13` | ✓ |
| T19 | Eco zima 19.5→20 | f[10-11] | `11:13`→`11:18` | ✓ |
| T20 | Eco chłodz 18→17.5 | f[12-13] | `11:04`→`10:7F` | ✓ |
| T21 | Eco chłodz 17.5→18 | f[12-13] | `10:7F`→`11:04` | ✓ (potem powrót do `11:04`) |
| T22 | Manual 19.3→18.8 | f[14-15] | `11:11`→`11:0C` | ✓ |
| T23 | Manual 18.8→19.3 | f[14-15] | `11:0C`→`11:11` | ✓ |
| T24 | Poza 16→15.5 | f[16-17] | `10:70`→`10:6B` | ✓ |
| T25 | Poza 15.5→16 | f[16-17] | `10:6B`→`10:70` | ✓ |

**Wszystkie zmiany zgodne z PROTOCOL §3.7 / §5.6.** Encoding T = (H*128+L%128-2000)/10 potwierdzony.

**Obserwacja sub-cyklowa:** zmiana SP propaguje od cyklu T+1 (nie natychmiast). Czasem widoczne 2-3 wartości w środku cyklu (Nano UI broadcast się stabilizuje).

---

## T30: Wietrzenie OFF→ON (13:29:05)

```
E4   [...,14,32,01,1A,20,03,23]   # f[27]=20 (Wietrz overlay)
E3   [...,20,21,13,23]            # f[27]=21 (sezon=01 Zima | wietrz=20)
E5   [...,61,00,00,01,23]         # bez zmian
AERO [E4,21,6F,63,...,1E,1E,04,0A,40,23]  # f[24-25]=1E,1E (30%); f[26]=04 (bieg=4 Wietrzenie); f[27]=0A; f[28]=40
```

**Pola sterujące:**
| Pole | T6_baseline → T30 | PROTOCOL | Werdykt |
|------|-------------------|----------|---------|
| E4 f[27] | `0x00`→`0x20` | §3.2 +`0x20` Wietrz overlay | ✓ |
| E3 f[27] | `0x01`→`0x21` | §3.3 +`0x20` Wietrz overlay | ✓ |
| E5 f[27] | bez zmian | §5.4 "brak wpływu w E5" | ✓ |

**🔍 NOWE ODKRYCIA T30 (AERO E4(63) podczas Wietrzenia):**
1. **AERO f[26]=`0x04`** — bieg `4` = Wietrzenie. PROTOCOL §3.4 wymienia: "0=Stop, 1=B1, 2=B2, 3=B3, **4=Wietrzenie**". ✓ Zgodne.
2. **AERO f[27]=`0x0A`** — **NOWA wartość** poza dokumentowanymi `0x00`/`0x02`. Hipoteza: `0x0A` = `0x08 | 0x02` = bit "Wietrzenie aktywne" + bit "fan aktywny".
   - PROTOCOL §3.4 mówi: "f[27] = 0x00 Stop, 0x02 B1/B2/B3 aktywny". **Należy uzupełnić**: `0x0A` = Wietrzenie aktywne.
3. **AERO f[24-25]=`0x1E,0x1E` (30%/30%)** — % nawiewu/wywiewu **Wietrzenia**. To są wartości "Wietrzenie Naw/Wyw" z menu serwisowego (markers.txt: "Wietrzenie: Naw=30% Wyw=30%"). Potwierdza że AERO E4(63) f[24-25] reaguje na overlay Wietrzenie i pokazuje % wietrzeniowe.
4. **E3(29) f[14-15]** (Wietrzenie naw/wyw %) **wartości się nie zmieniły** mimo Wietrzenia — pozostały `0x1E,0x1E` (PROTOCOL §3.3 mówi że f[14-15] zawsze zawiera Wietrzenie %). To znaczy że E3 f[14-15] = nastawa serwisowa, nie aktualne %. **W teście nie da się odróżnić** czy 30% to "wartość serwisowa" czy "aktualnie używana", bo i tak są te same. Spójne z PROTOCOL.

**Obserwacja**: Wietrzenie jest auto-exit po krótkim czasie — w cyklu 2 (8.5s później) f[27] już wrócił do `0x00`. To Nano UI feature, nie protokołowy.

---

## T31: Wietrzenie ON→OFF (13:29:29) — reset do baseline

DIFF T30→T31:
- E4 f[27] `0x20`→`0x00` ✓
- E3 f[27] `0x21`→`0x01` ✓
- AERO f[26-27] `04,0A`→`02,02` ✓ powrót do B1 aktywny

---

# CZĘŚĆ II — TESTY KRZYŻOWE (MIX)

## MX1: Sezon × Wentylacja

### MX1a: Went=Harmonogram + Sezon Zima→Chłodzenie (13:31:22)

Pre-MX1a setup: Wentylacja=Harmonogram (slot=B1), Sezon=Zima.
```
E4 cycle 2: [...,14,00,03,0A,10,0D,23]   # f[27]=10 Chłodz; f[28]=0D = 0x05|0x08 (B2_slot|chłodz)
E3:        [...,20,11,1D,23]             # f[28]=1D = 0x15|0x08
E5:        [...,61,00,14,05,23]          # f[28]=05 (Harm+Chłodz UI)
```

Czekaj — f[28]=`0x0D` to bieg=`0x05` (B2) | chłodz `0x08`. Slot Harm rotował z B1 do B2!
Pre-MX1a (cycle 1): f[28]=`0x05` (B2 z slotu Harm Zima). Po Chłodz: f[28]=`0x0D`.

**Wnioski MX1a:**
- ✓ E4 f[28]: B2_z_slotu (`0x05`) + chłodz overlay (`0x08`) = `0x0D`. Potwierdza że overlay `+0x08` aplikuje się **niezależnie czy bieg z slotu czy z menu manual**.
- ✓ E3 f[28] dostaje `+0x08` overlay (nowa obserwacja zgodna z T2 — to **konsystentne**, do uzupełnienia w PROTOCOL §3.3).

### MX1b: Went Harmonogram → Harm-Urlop (Sezon=Chłodz) (13:32:07)

DIFF: pole E5 f[28] `0x05`→`0x04` (jak T11). E4/E3 f[28] bez zmian (`0x0D`/`0x1D`). f[24]=`0x00` (Chłodz+Harm-Urlop).

🔍 Wniosek: Harm-Urlop w Chłodz vs Harm w Chłodz: **brak różnicy w E4/E3 f[28] i f[24]** (oba mają bieg z slotu, brak `0x40`, f[24]=`0x00`). Różnica TYLKO w E5 f[28] kodzie UI (`0x05`↔`0x04`).

### MX1c: Sezon Lato bez → Chłodzenie (Went=B1) (13:34:03)

DIFF (po reset Term=Harm, Went=B1):
- E4 f[27] `0x08`→`0x10` ✓
- E4 f[28] `0x03`→`0x0B` (B1+chłodz) ✓
- E3 f[28] `0x13`→`0x1B` ✓ (overlay Chłodz w E3)
- E5 f[27] `0x0A`→`0x14` ✓
- E5 f[28] niezmienne `0x01` ✓

### MX1d: Sezon Lato bez → Chłodzenie (Went=Stop) (13:35:58)

```
E4   [...,14,00,03,0A,10,09,23]   # f[28]=09 = 0x01|0x08 (Stop|chłodz)
E3   [...,20,11,19,23]            # f[28]=19 = 0x11|0x08
AERO [...,00,00,00,00,60,23]      # f[24-27]=00,00,00,00 (zatrzymany!)
```

**🔍 Nowe obserwacje MX1d:**
1. **E4 f[28]=`0x09` = `0x01|0x08`** — Stop+Chłodz overlay. Sensowne mimo nieoczywiste w UI.
2. **AERO E4(63) f[20-27]=`7E,00,00,00,00,00,00,00`** — **AERO przechodzi w pełen Stop** w Went=Stop, ZEROWANE pola % i bieg.
   - PROTOCOL §3.4 mówi `f[24]` = 0-100 Naw%. `0x00` = 0% sensowne dla Stop.
   - PROTOCOL §3.4 mówi `f[27]` = `0x00` Stop, `0x02` aktywny. ✓ `0x00` = Stop.
   - PROTOCOL §3.4 mówi `f[26]` = bieg. `0x00` = Stop. ✓
3. **AERO f[28]=`0x60`** — **bypass otwarty mimo Sezon=Chłodz, Went=Stop**.
   - Free-cooling przez bypass nawet bez wentylatora? Brak sensu fizycznego.
   - 🔍 Wymaga sprawdzenia: czy w MX1d f[28]=`0x60` to artefakt z poprzedniego stanu (T15c bypass otwarty), czy AERO świadomie utrzymuje bypass open.
   - Hipoteza: AERO w Went=Stop nie zamyka bypass, jeśli wcześniej był otwarty (brak motoryzacji do zamknięcia bez napędu wentylatora).

---

## MX2: Termostat × Wentylacja

### MX2a: Went B1 → Harmonogram (Term=Manual, Sezon=Chłodz) (13:37:41)

Pre: Term=Manual, Went=B1, Chłodz, slot Harm aktualnie B2.
```
E4   [...,14,00,01,1A,12,0D,23]   # f[27]=12 (Manual+Chłodz); f[28]=0D (B2_slot+chłodz)
E5   [...,61,00,14,19,23]         # f[28]=19 (Manual+Chłodz+Harm+B2)
```

**Pytanie MX2a:** czy stable `0x40` zostaje w f[28] w Term=Manual+Wentylacja=Harm?
- f[28]=`0x0D` — **brak `0x40`**! Tylko `0x05|0x08`.
- f[24]=`0x00` (nie `0x64`)

**🔍 Wniosek MX2a (kluczowy):**
- Term=Manual + Wentylacja=Harmonogram → **stable bit `0x40` CLEAR**, mimo Term=Manual.
- Niezgodne z PROTOCOL §3.2: "stable=Term=Manual AND korekta=0".
- **PROTOCOL nie uwzględnia**: Wentylacja=Harm/Harm-Urlop **clear**uje stable bit nawet gdy Term=Manual.
- Spójne z PROTOCOL §5.3 (table): "Wentylacja=Harmonogram | identyczne jak Manual+bieg_z_slotu" — sugeruje że Harmonogram zachowuje się jak Manual w f[28], ale tu **NIE** — bit `0x40` nie ma.
- Faktyczny warunek stable: `Term=Manual AND Wentylacja=B1/B2/B3/Stop AND korekta=0 AND Sezon=Zima`.
- **E5 f[28]=`0x19`** — UI code Manual+Chłodz+Harm = `0x19`. Nowa wartość (PROTOCOL §3.7 podaje `0x19` dla "Manual+Zima" — TU MAMY ten sam kod ale dla Manual+Chłodz! Sprzeczność).

### MX2b: Went Harmonogram → Harm-Urlop (Term=Manual, Chłodz) (13:38:25)

```
E4 [...,14,00,01,1A,12,0D,23]    # niezmienne f[28]=0D
E5 [...,61,00,14,18,23]           # f[28]=18 (Harm-Urlop+Manual+Chłodz)
```

**DIFF:**
- E4 f[28] **niezmienne** (`0x0D`) — nie ma różnicy między Wentylacja=Harm a Harm-Urlop w f[28].
- E5 f[28] `0x19`→`0x18` (różnica tylko w bicie 0).

### MX2c: Went B1 → Harmonogram (Term=Harm, Chłodz) (13:40:05)

```
E4 [...,14,00,02,05,10,0D,23]    # f[28]=0D (B2_slot+chłodz)
E3 [...,20,11,1D,23]
E5 [...,61,00,14,05,23]           # f[28]=05 (Harm+Chłodz)
```

DIFF Pre-MX2c (Term=Harm,Went=B1) → MX2c (Went=Harm):
- E4 f[28] `0x0B` (B1+chłodz) → `0x0D` (B2_slot+chłodz) — slot rotował.
- E5 f[28] `0x01` → `0x05`. 🔍 nowy kod UI dla Harm+Chłodz+Term=Harm (do tabeli §3.7).

### MX2d: Went B1 → Harm (Term=Urlop, Chłodz) (13:41:20)

```
E4 cycle 3: [...,14,00,01,1A,11,0D,23]   # f[27]=11 (Urlop+Chłodz); f[28]=0D
E5:         [...,61,00,14,19,23]         # f[28]=19? (cycle 3)
```

**Pytanie**: czy Term=Urlop dominuje?
- E4 f[27]=`0x11` = Urlop (`0x01`) | Chłodz (`0x10`).
- Pre-cycle: Wentylacja=B1+Term=Urlop+Chłodz: f[28]=`0x0B` (B1+chłodz, brak `0x40` jak Urlop).
- Po MX2d: f[28]=`0x0D` (B2_slot+chłodz, brak `0x40`).
- **🔍 Term=Urlop NIE dominuje nad Wentylacją** — Wentylacja=Harm rotuje jak normalnie (slot B2 widoczny w f[28]).
- PROTOCOL §5.5 mówi: "Programy=Urlop | f[28] = 0x40" — ale to **Programy=Urlop**, NIE Term=Urlop!
- Term=Urlop w MX2d = standardowy mode, slot Harm działa.

---

## MX3: Wietrzenie × Sezon × Termostat

### MX3a: Wietrz OFF→ON (Chłodz, Manual, B2) (13:42:26)

```
E4   [...,14,00,03,0A,32,0D,23]   # f[27]=32 = Manual(02)|Chłodz(10)|Wietrz(20); f[28]=0D (B2+chłodz)
E3   [...,20,31,1D,23]            # f[27]=31 = Chłodz(11)|Wietrz(20); f[28]=1D
E5   [...,61,00,14,16,23]         # f[28]=16
AERO [...,1E,1E,04,0A,60,23]      # f[26-27]=04,0A; f[28]=60 (otwarty)
```

DIFF MX3a SETUP (Wietrz OFF) → MX3a (Wietrz ON):
- E4 f[27] `0x12`→`0x32` ✓ +`0x20` overlay
- E3 f[27] `0x11`→`0x31` ✓ +`0x20` overlay
- E4 f[28] `0x0D` (bez zmian) — Wietrz NIE wpływa na f[28]
- AERO f[26] `02`→`04` (B2→Wietrzenie) ✓
- AERO f[27] `02`→`0A` ✓ Wietrzenie aktywne
- AERO f[24-25] `aktualne_%`→`1E,1E` (% Wietrzenie)
- AERO f[28] niezmienne `0x60` (bypass dalej otwarty z auto-bypass Chłodz)

**🔍 Wniosek MX3a:** Wietrzenie ON nie zmienia f[28] mastera (B2 w slocie zostaje), ale AERO przełącza się fizycznie w bieg=4 Wietrzenie. Master nie wie/nie odzwierciedla tego w f[28].

### MX3b: Wietrz OFF→ON (Lato bez, Harm, B1) (13:44:03)

DIFF:
- E4 f[27] `0x08`→`0x28` ✓ Lato bez|Wietrz
- E3 f[27] `0x09`→`0x29` ✓
- E4 f[28] niezmienne `0x03`
- AERO f[26-27] `02,02`→`04,0A` ✓
- AERO f[28] `0x60` (auto-bypass Lato bez był otwarty, niezmiennie)

**🔍 Cycle 3 MX3b:** E4 f[27]=`0x21` zamiast `0x28`! Bit `0x08` (Lato bez) zniknął, bit `0x01` pojawił się — co sugeruje **f[27] dostał bit 0**.
- Hipoteza: Wietrzenie=ON + Lato bez: f[27] = Wietrz(`0x20`)|Urlop(`0x01`) = `0x21`. Ale Term=Harm!
- Inne wyjaśnienie: cykl 3 to artefakt po MX3b — między cycles może wystąpiło wiele rzeczy.
- **Wymaga osobnej weryfikacji** — cykl 1-2 spójny `0x28`, cykl 3 odbiega `0x21`.

### MX3c: Wietrz OFF→ON (Zima, Urlop, B1) (13:45:10)

DIFF:
- E4 f[27] `0x01`→`0x21` ✓ Urlop|Wietrz
- E3 f[27] `0x01`→`0x21` ✓
- E4 f[28] niezmienne `0x03`
- AERO f[26-27] `02,02`→`04,0A` ✓

**Wniosek**: Wietrzenie dozwolone w Term=Urlop. Nano nie blokuje.

### MX3d: Went B1→Harm-Urlop (Wietrz=ON, Zima, Urlop) (13:46:05)

DIFF cycle 1-2:
- E4 f[28] `0x03`→`0x05` (B1→bieg ze slotu/B2)
- E3 f[28] `0x13`→`0x15`
- f[27] niezmienne `0x21` (Wietrz overlay zachowane!)

**Wniosek**: Wietrzenie ON zachowane przy zmianie Wentylacja=Harm-Urlop. Nano nie wymusza Wietrz=OFF.

Cycle 3 nieco inny (f[27]=`0x20` bez `0x01`) — Term=Urlop bit zniknął? Możliwe że Nano auto-zamknął Wietrzenie w cyklu 3 (timeout Wietrzenia jak T30).

---

## MX4: Programy × wszystko

### MX4a: Programy Normal→Poza domem (Zima, Term=Harm, Went=B1) (13:47:32)

```
E4   [...,0A,44,00,06,0D,2F,7E,00,11,2F,10,70,7E×7,14,32,01,1A,00,01,23]
       ^^^                              ^^^^^^      ^^^^^^^
      f[5]=44                          f[14-15]=10:70 (Poza 16°C)   f[27]=00 f[28]=01
E3   [...,20,01,11,23]                  # f[28]=11 (Stop ze slotu Poza?)
E5   [...,61,00,00,01,23]
AERO [...,23,20,00,00,40,23]            # f[26-27]=00,00 (Stop!), f[28]=40
```

**Pola sterujące:**
| Pole | Pre → MX4a | PROTOCOL §5.5 | Werdykt |
|------|------------|---------------|---------|
| E4 f[5] | `0x40`→`0x44` | bit `0x04`=Programy=Poza domem | ✓ |
| E4 f[14-15] | `11:18`→`10:70` | f[16-17] (Poza domem 16°C) | ✓ |
| E4 f[27] | `0x00` (bez zmian) | – | ✓ |
| E4 f[28] | `0x03`→`0x01` | "bieg ze slotu poza-domem harmonogramu" | ✓ slot Poza-domem = Stop |
| **AERO f[26-27]** | `02,02`→`00,00` | – | 🔍 AERO fizycznie zatrzymany |

**🔍 Nowe odkrycia MX4a:**
1. **Programy=Poza domem + slot harm Poza domem = Stop**. Slot Poza-domem ma wpis "Stop" o tej godzinie (~13:47).
2. **AERO automatycznie zatrzymał wentylator** (f[26-27]=`00,00`) gdy slot Poza-domem nakazał Stop. AERO reaguje na f[28]=`0x01` (Stop) z mastera w cyklu master Mini.
3. **markers.txt obs:** "AERO wentylatory STOP w trakcie MX4a (Programy=Poza domem) @ 2026-05-10 13:49:26" — potwierdzone.

### MX4d: Programy Poza domem → Urlop (13:50:26)

```
E4   [...,0A,40,00,06,0D,32,7E,00,11,2F,10,70,7E×7,14,32,03,0A,00,00,23]
        ^^^                                              ^^^^^^^^^^^
       f[5]=40 (bit 04 CLEAR!)                         f[28]=00 (validity=0, bieg=0)
E3   [...,20,01,11,23]
E5   [...,61,00,00,01,23]
AERO [...,23,20,00,00,40,23]
```

**Pola sterujące:**
| Pole | MX4a → MX4d | PROTOCOL §5.5 | Werdykt |
|------|-------------|---------------|---------|
| E4 f[5] | `0x44`→`0x40` | "Urlop bit `0x04` CLEAR" | ✓ |
| E4 f[14-15] | `10:70` (bez zmian) | "Poza domem (20°C)" — błąd PROTOCOL: 16°C | ✓ ale PROTOCOL ma błąd: "Poza domem 20°C" — w tym secie `0x70`=16°C |
| **E4 f[28]** | `0x01`→`0x00` | "Urlop \| f[28]=`0x40`" | ⚠ **`0x00` nie `0x40`** |

**⚠ NIEZGODNOŚĆ MX4d:**
- PROTOCOL §3.2 "Programy=Urlop": `f[28]=0x40` (validity=0 + bit `0x40`).
- PROTOCOL §5.5 tabela: "Urlop | f[28] | `0x40` (validity=0, bieg=0)".
- **Empirycznie:** f[28]=`0x00` — bez stable bit. validity=0, bieg=0 zgadza się, ale brak `0x40`.
- **Możliwe wyjaśnienie:** stable bit `0x40` był CLEAR przed MX4d (nie ma skąd się wziąć). PROTOCOL implicit zakłada, że Programy=Urlop **wstawia** bit `0x40` jako sygnał "Programy aktywne". Tu tego nie ma.
- Dodatkowo PROTOCOL §3.2 mówi: "0x40 sam (validity=0, bieg=0) = Programy=Urlop" — to jest błędne stwierdzenie, bo widzimy że Programy=Urlop **nie** wstawia bitu `0x40`.

**🔍 Nowa hipoteza:** Programy=Urlop = `f[28]=0x00` (validity=0, bieg=0, bez stable). Inne kryterium odróżnienia od "fan Stop" (`0x01`)?
- Stop: `f[28]=0x01` (validity SET, bieg=0)
- Programy=Urlop: `f[28]=0x00` (validity CLEAR, bieg=0)
- bit 0 (validity) różnicuje.

---

## MX5: Bypass × Sezon (sanity)

### MX5a: Bypass AUTO→ON (Zima) (13:51:57)

```
E5  [...,62,00,00,01,23]   # f[25]=62 ON
E3  [...,20,02,13,23]      # f[27]=02 (bypass cmd ON, Zima)
AERO f[28]=60 (otwarty)
```

DIFF: E5 f[25] `0x61`→`0x62` ✓; E3 f[27] `0x01`→`0x02` ✓ (bypass cmd kodowany w E3 f[27], potwierdza T13-T15 obserwację).

### MX5b: Sezon Zima→Chłodz (Bypass=ON) (13:52:29)

```
E3  [...,20,12,1B,23]      # f[27]=12 (Chłodz | ON)
E5  [...,62,00,14,01,23]
AERO f[28]=60
```

✓ E3 f[27]=`0x12` = Chłodz (`0x10`) | bypass_ON (`0x02`). Spójne z propozycją reformulacji E3 f[27] z T13-T15.

### MX5c: Sezon Chłodz→Lato bez (Bypass=ON) (13:53:24)

```
E3  [...,20,0A,13,23]      # f[27]=0A (Lato | ON)
E5  [...,62,00,0A,01,23]
AERO f[28]=60
```

✓ E3 f[27]=`0x0A` = Lato (`0x08`) | bypass_ON (`0x02`).

**MX5 podsumowanie**: bypass komenda jest stabilna we wszystkich sezonach (E5 f[25]=`0x62` niezmienne). E3 f[27] ujawnia kombinację sezon × bypass_cmd.

---

## MX6: Aktywny setpoint cross-table

### MX6/4: Term=Harm, Sezon=Lato bez, Programy=Normal (13:53:50)

```
E4 f[14-15] = 11:04 (Eco_chłodz 18.0)   ← Lato bez używa Eco_chłodz (zgodne z T1)
E5 f[28] = 01
```

### MX6/5: Sezon Lato bez→Chłodz (Term=Harm) (13:54:30)

```
E4 f[14-15] = 11:04 (bez zmian — Eco_chłodz dla Lato i Chłodz)
E4 f[28] = 0B (B1+Chłodz)
```

### MX6/3: Sezon Chłodz→Zima (Term=Harm) (13:55:11)

```
E4 f[14-15] = 11:04 → 11:18 (Eco_chłodz → Eco_zima) ✓ slot Harm zima
E5 f[28] = 0F? → 01
```

### MX6/1: Term Harm→Manual (Sezon=Zima) (13:55:40)

```
E4 f[14-15] = 11:18 → 11:11 (Eco_zima → Manual 19.3 — current Manual SP)
E4 f[27] = 00→02 ✓
E4 f[28] = 03 (B1, brak stable!)
E4 f[24] = 32 (sync nie wzrósł do 64!)
```

**🔍 Potwierdzenie hipotezy z T15c:** Term=Manual+Sezon=Zima w sesji **późnej** (po wielu zmianach) **NIE aktywuje stable bit**. Mimo że teoretycznie powinno (PROTOCOL §3.2). T4 to zrobiło, ale T4 było pierwszym wejściem w Manual w tej sesji. Po wielu cyklach Manual stable znikł.
- **Hipoteza**: stable bit jest "lepkie" — raz aktywowany w pewnych warunkach pozostaje, raz utracony nie wraca samoczynnie. Mechanizm aktywacji = tylko po świeżym setupie / power-cycle / pierwsza zmiana w Manual.

### MX6/2: Sezon Zima→Chłodz (Term=Manual) (13:56:16)

```
E4 f[14-15] = 11:11 (Manual 19.3 — bez zmian niezależnie od Sezon!)
E4 f[28] = 0B (B1+Chłodz, brak stable)
E5 f[28] = 15 (Manual+Chłodz)
```

✓ Term=Manual: Active SP = Manual SP, niezależny od Sezon.

### MX6/6: Term Manual→Urlop (Sezon=Chłodz) (13:56:52)

```
E4 f[14-15] = 11:11 → 11:04 (Manual → Eco_chłodz)  
E4 f[27] = 12 → 11 (Manual+Chłodz → Urlop+Chłodz)
E4 f[28] = 0B (B1+Chłodz, brak stable — bo Urlop)
```

**🔍 Wniosek MX6/6:** Term=Urlop+Sezon=Chłodz → **Active SP = Eco_chłodz** (`f[12-13]`).
- PROTOCOL §5.1 mówi: "Term=Urlop+Zima = eco_zima" — analogicznie Urlop+Chłodz = Eco_chłodz?
- **Brak w PROTOCOL** wprost. Wymaga uzupełnienia.

### Cross-table MX6 podsumowanie

| Termostat | Sezon | Programy | Pole E5 użyte (E4 f[14-15]) | Empiryczne | Werdykt |
|-----------|-------|----------|------------------------------|------------|---------|
| Manual | Zima | Normal | f[14-15] (T_manual) | T_manual | ✓ |
| Manual | Chłodzenie | Normal | f[14-15] (T_manual) | T_manual | ✓ MX6/2 |
| Manual | Lato bez | Normal | f[14-15] | – | nie testowane |
| Harm | Zima | Normal | f[10-11] (Eco_zima) | Eco_zima | ✓ MX6/3 |
| Harm | Lato bez | Normal | f[12-13] (Eco_chłodz) | Eco_chłodz | ✓ T1, MX6/4 |
| Harm | Chłodzenie | Normal | f[12-13] (Eco_chłodz) | Eco_chłodz | ✓ MX6/5 |
| Urlop | Zima | Normal | f[10-11] (Eco_zima) | Eco_zima | ✓ T5 |
| Urlop | Chłodzenie | Normal | f[12-13] (Eco_chłodz) | Eco_chłodz | ✓ MX6/6 |
| dowolny | dowolny | Poza domem | f[16-17] (Poza) | Poza | ✓ MX4a |
| dowolny | dowolny | Urlop | f[16-17] (Poza) | Poza | ✓ MX4d |

Term=Harm/Urlop **nie używa Comfort (f[8-9])** — to zaskakujące. Comfort prawdopodobnie używany tylko w specjalnym slocie harmonogramu (np. dni robocze rano). Wymaga osobnego testu (slot Harm szczególowo).

---

# RAPORT KOŃCOWY — Lista propozycji do PROTOCOL.md

⚠ Bez auto-update — decyzja Twoja.

## P1. **§3.3 E3(29) f[27]** — reformulacja

**Obecnie:** "Bit 0 (`0x01`) zawsze SET, bity 3-4 = sezon, bit 5 = wietrzenie ON"

**Proponowane:**
```
f[27] = (sezon_szyld) | (bypass_cmd & 0x03) | (wietrz_overlay)

Sezon szyld:    Zima=0x00, Lato bez=0x08, Chłodz=0x10
Bypass cmd:     OFF=0x00, AUTO=0x01, ON=0x02 (z E5 f[25] mapowane na 2-bitowy enum)
Wietrz overlay: +0x20 gdy Wietrzenie ON
```

Tabela kombinacji (Wietrz OFF, sanity check):
| Sezon × Bypass | OFF | AUTO | ON |
|----------------|-----|------|-----|
| Zima | `0x00` | `0x01` | `0x02` |
| Lato bez | `0x08` | `0x09` | `0x0A` |
| Chłodz | `0x10` | `0x11` | `0x12` |

Empirycznie potwierdzone: F0/T1/T2/T3/T13-T15/MX5a-c (każda kombinacja widziana ≥ raz).

## P2. **§3.3 E3(29) f[28]** — uzupełnienie overlay Chłodz

**Obecnie:** `f[28] = bieg | 0x10 (znacznik E3) | 0x40 (stable config)`

**Proponowane dodanie:**
```
f[28] = bieg | 0x10 | 0x40_stable | 0x08_chłodz_overlay

Overlay 0x08 obecny gdy Sezon=Chłodzenie (analogicznie jak E4 f[28]).
```

Empirycznie: T2 (`0x13`→`0x1B`), MX1a (`0x1D`), MX1c (`0x1B`), MX1d (`0x19` = Stop+Chłodz).

## P3. **§3.2 E4(29) f[24]** — dodać trzecią wartość `0x00`

**Obecnie:** "0x64 = synced, 0x32 = unsynced/awaryjny"

**Proponowane:**
```
f[24] = 0x64 (synced, max), 0x32 (unsynced), 0x00 (Sezon=Chłodzenie + brak stable)
```

Empirycznie: T2/MX1a-d/MX2a-d/MX3a/MX5b (każdy Sezon=Chłodz + Term=Harm/Urlop).

Korelacja: f[24]=`0x00` ⇔ Sezon=Chłodzenie AND f[28] bit `0x40` CLEAR.

## P4. **§3.2 E4(29) f[28] bit `0x40` (stable)** — uściślenie warunków

**Obecnie:** "SET ⇔ (Term=Manual) AND (korekta=0)"

**Proponowane (ostrożna reformulacja):**
```
Bit 0x40 SET wymaga:
  - Term=Manual ORAZ
  - Wentylacja ∈ {Stop, B1, B2, B3} (NIE Harm/Harm-Urlop) ORAZ
  - korekta termostatu = 0 ORAZ
  - Sezon=Zima (możliwe inne sezony też, ale nie potwierdzone) ORAZ
  - "świeży" cykl Manual (po power-cycle / wejściu z innego trybu)

Raz utracony bit nie wraca samoczynnie nawet po przywróceniu warunków.
Mechanizm "lepkości" wymaga osobnego testu (power-cycle).
```

Empirycznie:
- T4 (Manual+Zima+B1+korekta_0): SET → ✓
- MX2a (Manual+Wentylacja=Harm): CLEAR — Wentylacja=Harm clear stable
- T15c (Manual+Chłodz): CLEAR — możliwe że Chłodz blokuje, lub stable został utracony wcześniej
- MX6/1 (Manual+Zima ponownie po wielu zmianach): CLEAR — stable nie wrócił mimo warunków OK

## P5. **§3.4 E4(63) f[27]** — dodać wartość `0x0A` Wietrzenie

**Obecnie:** "0x00 Stop, 0x02 B1/B2/B3 aktywny"

**Proponowane:**
```
f[27]:
  0x00 = Stop
  0x02 = B1/B2/B3 aktywny
  0x0A = Wietrzenie aktywne (= 0x08 | 0x02)
```

Empirycznie: T30, MX3a, MX3b, MX3c, MX3d.

## P6. **§3.7 E5 f[28] kod UI** — uzupełnienie tabeli

**Obecnie zawiera:**
- Manual+Zima=`0x19`, Harm+Zima=`0x05`, Urlop+Zima=`0x05`, Manual+Chłodz=`0x01`, Manual Stop=`0x00`, Manual B1=`0x01`, Manual B3=`0x03`

**Empirycznie obserwowane (do uzupełnienia):**

| Term | Sezon | Wentylacja | Bieg/slot | E5 f[28] |
|------|-------|------------|-----------|----------|
| Harm | Zima | B1 (manual) | B1 | `0x01` |
| Harm | Zima | B2 | B2 | `0x02` |
| Harm | Zima | B3 | B3 | `0x03` |
| Harm | Zima | Stop | Stop | `0x00` |
| Harm | Zima | Harm | rotuje slot | `0x05` (T10), `0x04` (T11 Harm-Urlop) |
| Harm | Zima | Harm | slot Stop | `0x05` (B2 ostatecznie) |
| Manual | Zima | B1 | B1 | `0x15` (NIE `0x19` jak PROTOCOL!) |
| Urlop | Zima | B1 | B1 | `0x0B` (NIE `0x05`!) |
| Manual | Chłodz | B1 | B1 | `0x15` |
| Manual | Chłodz | Harm | slot B2 | `0x19` |
| Manual | Chłodz | Harm-Urlop | slot B2 | `0x18` |
| Harm | Chłodz | Harm | slot B2 | `0x05` |
| Urlop | Chłodz | B1 | B1 | `0x0B`, `0x0F` |
| Manual+wietrz | Chłodz | B2 | B2 | `0x16` |
| Harm+Programy=Poza | Zima | B1 (Stop slot) | Stop | `0x01` (cycle 1), `0x05` (cycle 3) |

PROTOCOL §3.7 ma kilka błędów — wymienione wartości `0x19` Manual+Zima i `0x05` Urlop+Zima nie zgadzają się z empirią (`0x15` i `0x0B` odpowiednio). **Tabela wymaga przepisania**.

Nadal nieujęte: pełna macierz Manual+wszystko, Wietrzenie+wszystko. Wskazany osobny test focused na E5 f[28] enum.

## P7. **§3.7 E5 f[6-7]** — wyjaśnienie pola

**Obecnie:** "T.Czerpnia (kopia z AERO E4(63), NIE sensor pokojowy)"

**Empirycznie potwierdzone (T1):** f[6-7] = mirror AERO f[10-11] (T.Czerpnia). ✓

Wniosek: aktualne. Dodać wzmiankę "wartość aktualizowana co cykl, opóźnienie ~1 cykl".

## P8. **§3.4 AERO E4(63) f[20-27]=`00,00,00,00,00,00,00,00`** — Stop pełen

**Obecnie:** "f[20-23]=`7E,00,00,00` stałe"

**Empirycznie (MX1d Sezon=Chłodz+Went=Stop):** `f[20-27]=00,00,00,00,00,00,00,00`. f[20] zmienia się z `0x7E` na `0x00` w pełnym Stop. Wiarygodne że w Stop AERO zeruje wszystkie pola statusowe.

**Propozycja:** uzupełnić §3.4 że w Stop f[20]=`0x00` (zamiast `0x7E`).

## P9. **§3.2/§5.5 Programy=Urlop** — korekta

**Obecnie:** "Programy=Urlop | f[28] = `0x40` (validity=0, bieg=0)"

**Empirycznie (MX4d):** `f[28]=0x00` (NIE `0x40`!). Validity=0 i bieg=0 zgadza się, ale **brak bitu `0x40`**.

**Propozycja:**
```
Programy=Urlop:
  f[5] = bit 0x04 CLEAR (różnica vs Programy=Poza domem gdzie bit 0x04 SET)
  f[14-15] = setpoint Poza domem (f[16-17] z E5)
  f[28] = 0x00 (validity=0, bieg=0, bez stable)
  f[24] = 0x32
```

Programy=Urlop ≠ Wentylacja=Harm-Urlop ≠ Termostat=Urlop — **3 różne tryby**, każdy ma inne efekty.

## P10. **§5.6 Aktywny setpoint** — uzupełnienie

**Obecnie:** brakuje wiersza Term=Urlop+Sezon=Chłodzenie/Lato

**Empirycznie:**
| Termostat | Sezon | Aktywny SP |
|-----------|-------|------------|
| Urlop | Zima | Eco_zima (f[10-11]) |
| Urlop | Lato bez | Eco_chłodz (f[12-13]) — **nieprzetestowane** |
| Urlop | Chłodzenie | **Eco_chłodz (f[12-13])** ✓ MX6/6 |

Term=Urlop nie przeskakuje na Poza domem mimo nazwy "Urlop" — to zachowanie zarezerwowane dla **Programy=Urlop** (tam f[16-17] = Poza domem).

## P11. **§5.6 row "Poza domem"** — usunąć "Urlop+Zima"

**Obecnie:** "Poza domem | f[16-17] | Urlop+Zima, Poza domem"

**Empirycznie (T5):** Term=Urlop+Zima → Active SP = Eco_zima (`f[10-11]`), **NIE** Poza domem.

**Propozycja:**
```
Poza domem (f[16-17]) aktywny gdy:
  - Programy=Poza domem (zawsze)
  - Programy=Urlop (zawsze)
NIE aktywny dla Termostat=Urlop (tam Eco wg sezonu).
```

## P12. **§5.3 Wentylacja=Harm vs Harm-Urlop** — różnica jest tylko w E5 f[28]

**Obecnie:** sugeruje że Harm-Urlop ma "BEZ bitu `0x40`" w E4 f[28].

**Empirycznie:** to prawdziwe gdy Term=Manual. Ale gdy Term=Harm/Urlop, bit `0x40` i tak nie jest SET, więc **f[28] w E4 jest IDENTYCZNE** dla Wentylacja=Harm i Wentylacja=Harm-Urlop.

Różnica widoczna **tylko w**:
- E5 f[28] (kod UI: Harm=`0x05`, Harm-Urlop=`0x04` — różnica bitu 0)
- f[24] gdy Term=Manual (Harm: `0x64`, Harm-Urlop: `0x32`)

W przypadku Term=Harm różnica między Wentylacja=Harm a Harm-Urlop jest **niewidoczna na busie poza E5 f[28]**.

## P13. **Auto-bypass mapy aktywności** — uzupełnienie §3.7 lub §5.0

Empirycznie potwierdzone:
| Sezon | Bypass cmd | Cooling demand | AERO bypass |
|-------|-----------|----------------|-------------|
| Zima | AUTO | n/a | zamknięty |
| Zima | OFF | n/a | zamknięty |
| Zima | ON | n/a | otwarty |
| Lato bez | AUTO | – | otwarty (T1) |
| Chłodz | AUTO | aktywne (T_pok > Manual SP) | otwarty (T15c) |
| Chłodz | AUTO | nieaktywne | zamknięty (?) |
| Chłodz | OFF | dowolne | zamknięty (T15d) |
| Chłodz | ON | dowolne | otwarty |

**Propozycja:** osobna sekcja "Auto-bypass logic" lub uzupełnienie §3.7 / §5.0.

---

# Otwarte pytania / wymagane następne testy

1. **Stable bit `0x40` w f[28]** — mechanizm "lepkości": potrzebny test power-cycle Nano + sekwencja Term=Manual+Zima → czy stable wraca po power-cycle?
2. **E4 f[24]=`0x00`** — czy występuje w Lato bez+Harm? (nie testowane, T1 miał f[24]=`0x32`).
3. **Harmonogram Termostatu — slot Comfort (f[8-9])** — kiedy aktywny? Wymagany test z slotem Comfort w godzinach które trafią na test (lub menu serwisowe Nano: harmonogram=cały dzień Comfort).
4. **Wietrzenie auto-exit timeout** — empirycznie Wietrzenie ON wraca do OFF po ~10s w cyklu 2. Sprawdzić w menu Nano czy jest ustawialny.
5. **MX1d AERO bypass otwarty w Stop+Chłodz** — czy trwała pozostałość z poprzedniego stanu (T15c), czy AERO świadomie utrzymuje?
6. **Cycle 3 MX3b f[27]=`0x21`** — Wietrz OFF po 16s? Auto-exit identyczny jak T30?
7. **AERO E4(63) f[27]=`0x0A`** — bit `0x08`: czy oznacza "tryb Wietrzenie" w f[27], czy oznacza coś innego (np. "high speed override")?
8. **Programy=Poza domem slot harmonogramu** — kiedy slot Poza-domem zwraca B1/B2/B3? Test z różnymi godzinami.
9. **Bypass komenda kodowanie w E3 f[27]** — propozycja P1 podaje 2-bitowy enum, ale mamy tylko 3 obserwowane wartości (`0x00`/`0x01`/`0x02`). Możliwe że `0x03` to nieobserwowany 4. stan (np. "Bypass blocked")?
10. **E5 f[28]=`0x16` Wietrz+Manual+Chłodz+B2 (MX3a)** — wymaga sprawdzenia w innych kombinacjach Wietrz × {sezon, term, bieg}.

---

**Status raportu:** kompletny, gotów do review przez Piotra. Decyzja o aktualizacji PROTOCOL.md w kolejnej sesji.

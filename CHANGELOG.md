# Changelog

## 1.0.0

Erste Version. Übernimmt die Bestellfunktionen, die bisher in home.radio eingebaut waren.

### Anzeige

- Drei Modi: **App-Anzeige** (Vollbild, Display bleibt an), **Einblendung über anderen Apps** und **nur Abhol-Meldungen**.
- Die Einblendung ist in Position (3×3), Größe, Randabstand, Deckkraft und Aufbau (breit/kompakt) einstellbar,
  mit Skizze und Vorschau.
- Auf Wunsch öffnet sich die App nach dem Einschalten des Geräts automatisch.
- Vollbild-Anzeige: Größe von QR-Code (20–100 %) und Schrift (40–200 %) getrennt einstellbar, mit maßstabsgetreuer
  Vorschau in den Einstellungen. Text und QR-Code stehen zusammen in der Mitte.
- Solange die Vollbild-Anzeige offen ist, liegt keine Einblendung darüber.
- Die Einblendung hält Abstand zu Status- und Navigationsleiste (z.B. auf Tablets).

### Bitte abholen

- Meldung über allem, gleiche Gerichte zusammengefasst, mit Countdown.
- Gong mit Audio-Ducking: Andere Wiedergabe wird kurz leiser.

### Technik

- Hintergrunddienst als Bedienungshilfe mit vorgewärmter Flutter-Engine, wie bei home.control.
- Autostart nach Neustart und Update; mit adb-Berechtigung auch nach „Beenden erzwingen“.
- Design von home.control übernommen. Das Icon zeigt die Pizza des order.manager auf einem Fernseher.

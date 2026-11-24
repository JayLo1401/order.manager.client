# Changelog

## Unveröffentlicht

- Einheitliche Namen wie bei allen JayCloud-Apps: Der volle Name ist „JayCloud Order Manager Client“. In der App und
  unter dem App-Symbol bleibt es „Order Manager Client“. Die Kopfzeile zeigt jetzt „Powered by jaycloud.at“ und
  öffnet jaycloud.at. Die App-ID `at.jaycloud.order.manager.client` bleibt gleich.
- Automatische Updates wie bei home.control: Jeder Push auf `main` baut per GitHub Actions eine signierte APK und
  lädt sie ins Nexus. Der Hintergrunddienst installiert neue Versionen selbst (alle 6 Stunden, nicht während
  Bestellungen angenommen werden oder „Bitte abholen“ zu sehen ist). Eine offene Vollbild-Anzeige öffnet sich danach
  wieder. Einstellbar unter Verbindung → Updates.

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

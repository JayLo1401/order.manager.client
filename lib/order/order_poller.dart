import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'order_service.dart';

/// Fragt den order.manager regelmaessig ab (es gibt keinen Push):
///
/// - `/api/v1/today` im eingestellten Intervall -> [day] (Bestelltag, Kuechenstatus, QR-Code).
///   Schlaegt eine Abfrage fehl (z.B. kurz nach dem Booten noch kein Netz), wird nach 15 s
///   erneut gefragt und der letzte bekannte Bestelltag bleibt stehen, statt zu flackern.
/// - `/api/v1/ready` im selben Intervall, aber nur an einem Bestelltag und nur mit
///   [watchReady] -> [pickup] („Bitte abholen“).
///
/// Jede Fertigmeldung hat einen eindeutigen `key`; bereits gesehene werden gemerkt, damit
/// jede genau einmal gemeldet wird. Ist eine beim ersten Sehen schon aelter als die
/// Anzeigedauer (z.B. direkt nach dem Start), wird sie nur gemerkt, nicht gemeldet – nach
/// Server-Uhr. Neue Meldungen werden an eine offene Anzeige angehaengt (oft werden viele
/// Suppen gleichzeitig fertig) und starten deren Anzeigedauer neu; [onAnnounce] (Gong)
/// kommt einmal je Schwung, nicht je Eintrag.
class OrderPoller extends ChangeNotifier {
  OrderPoller({this.watchReady = true, this.onAnnounce});

  static const _errorRetry = Duration(seconds: 15);

  /// Abhol-Meldungen ueberwachen? (In der App nur, wenn der Hintergrunddienst nicht laeuft.)
  bool watchReady;

  /// Neue Abhol-Meldungen sind dazugekommen (z.B. Gong abspielen).
  void Function(List<ReadyItem> fresh)? onAnnounce;

  final _service = OrderService();
  final _seenKeys = <String>{};
  AppConfig _config = AppConfig();
  String _connection = '';
  int _generation = 0;
  Timer? _todayTimer;
  Timer? _readyTimer;
  Timer? _hideTimer;
  bool _disposed = false;

  /// Heutiger Bestelltag, null = keiner / nicht eingerichtet / (noch) nicht erreichbar.
  OrderDay? day;

  /// Ergebnis der letzten `/today`-Abfrage (null = noch keine).
  OrderFetchStatus? lastStatus;

  /// Aktuelle „Bitte abholen“-Anzeige (alle seit dem Oeffnen neu fertigen, aelteste zuerst).
  List<ReadyItem>? pickup;

  /// Wann die aktuelle Abhol-Anzeige zuletzt neu gestartet wurde (fuer den Countdown).
  DateTime? pickupSince;

  AppConfig get config => _config;

  /// Neue Einstellungen uebernehmen. Nur wenn sich die Verbindung geaendert hat, wird
  /// neu gestartet – ein geaendertes Intervall gilt einfach ab der naechsten Runde.
  void configure(AppConfig c) {
    _config = c;
    if (c.connectionKey == _connection) {
      if (!c.pickupEnabled && pickup != null) dismiss();
      return;
    }
    _connection = c.connectionKey;
    _generation++;
    _todayTimer?.cancel();
    _readyTimer?.cancel();
    _seenKeys.clear();
    day = null;
    lastStatus = null;
    _notify();
    if (_connection.isNotEmpty) _pollToday(_generation);
  }

  /// Sofort neu abfragen (z.B. App kommt in den Vordergrund).
  void refresh() {
    if (_connection.isEmpty) return;
    _pollToday(_generation);
  }

  Future<void> _pollToday(int gen) async {
    _todayTimer?.cancel();
    final c = _config;
    final result = await _service.fetchToday(baseUrl: c.baseUrl, user: c.user, password: c.password, previous: day);
    if (_disposed || gen != _generation) return;
    final hadDay = day != null;
    if (result.status == OrderFetchStatus.error) {
      if (lastStatus != OrderFetchStatus.error) {
        lastStatus = result.status;
        _notify();
      }
      // cancel: ein refresh() waehrend der Abfrage darf keine zweite Schleife hinterlassen.
      _todayTimer?.cancel();
      _todayTimer = Timer(_errorRetry, () => _pollToday(gen));
      return;
    }
    final changed = result.day != day || result.status != lastStatus;
    day = result.day;
    lastStatus = result.status;
    if (changed) _notify();
    // Abhol-Abfrage laeuft nur an einem Bestelltag.
    if (day != null && !hadDay) _pollReady(gen);
    if (day == null) _readyTimer?.cancel();
    _todayTimer?.cancel();
    _todayTimer = Timer(Duration(seconds: _config.pollSeconds), () => _pollToday(gen));
  }

  Future<void> _pollReady(int gen) async {
    _readyTimer?.cancel();
    if (day == null) return;
    final c = _config;
    if (watchReady && c.pickupEnabled) {
      final items = await _service.fetchReady(
        baseUrl: c.baseUrl,
        user: c.user,
        password: c.password,
        // Muss mindestens die Anzeigedauer abdecken, sonst faellt eine noch zu meldende heraus.
        seconds: math.max(120, c.pickupSeconds),
      );
      if (_disposed || gen != _generation) return;
      if (items != null) _handle(items);
    }
    if (day == null) return;
    _readyTimer?.cancel();
    _readyTimer = Timer(Duration(seconds: _config.pollSeconds), () => _pollReady(gen));
  }

  void _handle(List<ReadyItem> items) {
    final fresh = <ReadyItem>[];
    for (final item in items) {
      if (!_seenKeys.add(item.key)) continue;
      if (item.ageSeconds <= _config.pickupSeconds) fresh.add(item);
    }
    // Ein key verschwindet nur durch Alterung aus der Antwort und kommt nie wieder
    // (erneutes Abschliessen = neuer key) – die Menge bleibt so klein.
    _seenKeys.retainAll(items.map((i) => i.key));
    if (fresh.isNotEmpty) announce(fresh);
  }

  /// Zeigt [fresh] (an eine offene Anzeige angehaengt) und startet die Anzeigedauer neu.
  void announce(List<ReadyItem> fresh) {
    pickup = [...?pickup, ...fresh];
    pickupSince = DateTime.now();
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: _config.pickupSeconds), dismiss);
    _notify();
    onAnnounce?.call(fresh);
  }

  /// Testanzeige mit Beispieldaten (ohne Bestelltag).
  void showDemo() => announce(ReadyItem.demo());

  /// Anzeige schliessen (Zeit abgelaufen oder vom Benutzer). Die Eintraege bleiben als
  /// gesehen markiert; die naechste neue Fertigmeldung oeffnet eine frische Anzeige.
  void dismiss() {
    _hideTimer?.cancel();
    if (pickup == null) return;
    pickup = null;
    pickupSince = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _todayTimer?.cancel();
    _readyTimer?.cancel();
    _hideTimer?.cancel();
    _service.close();
    super.dispose();
  }
}

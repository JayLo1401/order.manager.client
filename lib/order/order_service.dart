import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Ein Gang des Bestelltags, z.B. 🥣 Vorspeise.
class Course {
  final String code;
  final String label;
  final String icon;
  const Course(this.code, this.label, this.icon);

  @override
  bool operator ==(Object other) =>
      other is Course && other.code == code && other.label == label && other.icon == icon;

  @override
  int get hashCode => Object.hash(code, label, icon);
}

/// Heutiger Bestelltag aus dem order.manager (`GET /api/v1/today`) – gibt es
/// keinen, ist das Ergebnis schlicht null.
class OrderDay {
  const OrderDay({
    required this.title,
    required this.hostName,
    required this.statusCode,
    required this.statusLabel,
    required this.statusIcon,
    required this.courses,
    required this.url,
    required this.qrPngBase64,
    required this.qrPng,
  });

  /// z.B. "Pizzaabend bei Jürgen" – angezeigt als "Bestellung aufgeben für <title>".
  final String title;
  final String hostName;

  /// 'starter' | 'main' | 'dessert' | 'closed'.
  final String statusCode;
  final String statusLabel;
  final String statusIcon;
  final List<Course> courses;
  final String url;

  /// Base64 bleibt neben den Bytes erhalten: bei unveraendertem QR-Code wird
  /// dieselbe [qrPng]-Instanz weiterverwendet (sonst dekodiert Image.memory jedes Mal neu).
  final String qrPngBase64;
  final Uint8List? qrPng;

  bool get isClosed => statusCode == 'closed';

  /// Beispieldaten fuer Vorschau und Test.
  static const demo = OrderDay(
    title: 'Pizzaabend (Vorschau)',
    hostName: 'Jay',
    statusCode: 'main',
    statusLabel: 'Pizzen werden angenommen',
    statusIcon: '🍕',
    courses: [Course('starter', 'Vorspeise', '🥣'), Course('main', 'Hauptspeise', '🍕'), Course('dessert', 'Nachspeise', '🍨')],
    url: 'https://bestellung.jaycloud.at',
    qrPngBase64: '',
    qrPng: null,
  );

  // Wertgleichheit ueber das Angezeigte: eine unveraenderte Abfrage loest keinen Neuaufbau aus.
  @override
  bool operator ==(Object other) =>
      other is OrderDay &&
      other.title == title &&
      other.hostName == hostName &&
      other.statusCode == statusCode &&
      other.statusLabel == statusLabel &&
      other.statusIcon == statusIcon &&
      _sameCourses(other.courses, courses) &&
      other.url == url &&
      other.qrPngBase64 == qrPngBase64;

  @override
  int get hashCode => Object.hash(title, hostName, statusCode, statusLabel, statusIcon, url, qrPngBase64);

  static bool _sameCourses(List<Course> a, List<Course> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Eine gerade fertig gewordene Bestellung (`GET /api/v1/ready`) – fuer „Bitte abholen“.
class ReadyItem {
  const ReadyItem({
    required this.key,
    required this.number,
    required this.guest,
    required this.itemName,
    required this.itemIcon,
    required this.options,
    required this.ageSeconds,
  });

  /// Eindeutig je Fertigmeldung – eine wieder geoeffnete und erneut
  /// abgeschlossene Bestellung bekommt einen neuen und wird erneut gemeldet.
  final String key;
  final int? number;
  final String guest;
  final String itemName;
  final String itemIcon;
  final String options;

  /// Alter laut *Server*-Uhr – eine falsch gehende Geraeteuhr stoert nicht.
  final int ageSeconds;

  /// Wer aufgerufen wird: Name des Gastes, sonst die Bestellnummer.
  String get who => guest.isNotEmpty ? guest : (number != null ? 'Nr. $number' : '?');

  factory ReadyItem.fromJson(Map<String, dynamic> json) => ReadyItem(
        key: '${json['key']}',
        number: (json['number'] as num?)?.toInt(),
        guest: (json['guest'] as String? ?? '').trim(),
        itemName: (json['item_name'] as String? ?? '').trim(),
        itemIcon: json['item_icon'] as String? ?? '',
        options: (json['options'] as String? ?? '').trim(),
        ageSeconds: (json['age_seconds'] as num?)?.toInt() ?? 0,
      );

  /// Beispiel-Meldung fuer „Bitte abholen testen“ (inkl. vieler gleicher Suppen).
  static List<ReadyItem> demo() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    const soups = ['Anna · Tisch 3', 'Ben', 'Carla', 'David', 'Eva', 'Franz'];
    return [
      for (final (i, guest) in soups.indexed)
        ReadyItem(
          key: 'demo-$stamp-$i',
          number: i + 1,
          guest: guest,
          itemName: 'Kürbiscremesuppe',
          itemIcon: '🎃',
          options: '',
          ageSeconds: 0,
        ),
      ReadyItem(
        key: 'demo-$stamp-ice',
        number: 11,
        guest: 'Lena',
        itemName: 'Eisbecher',
        itemIcon: '🍨',
        options: 'Erdbeereis, mit Schokosauce',
        ageSeconds: 0,
      ),
      ReadyItem(
        key: 'demo-$stamp-ice2',
        number: 12,
        guest: 'Max',
        itemName: 'Eisbecher',
        itemIcon: '🍨',
        options: 'Vanilleeis, ohne Sauce',
        ageSeconds: 0,
      ),
    ];
  }
}

/// Ergebnis von [OrderService.fetchToday]: unterscheidet die Gruende fuer
/// „kein Bestelltag“, damit die Einstellungen sagen koennen, was nicht passt.
enum OrderFetchStatus { ok, unauthorized, error }

class OrderFetchResult {
  const OrderFetchResult(this.status, [this.day]);

  final OrderFetchStatus status;

  /// Heutiger Bestelltag, null wenn keiner (oder Fehler).
  final OrderDay? day;
}

/// Lese-API des order.manager (HTTP Basic mit dem eigenen Konto des Gastgebers:
/// jeder Gastgeber sieht seinen eigenen Bestelltag; 401 = falsche Zugangsdaten
/// oder Konto nicht freigeschaltet). Es gibt keinen Push – es wird abgefragt.
class OrderService {
  static const _timeout = Duration(seconds: 10);

  final _client = http.Client();

  Future<OrderFetchResult> fetchToday({
    required String baseUrl,
    required String user,
    required String password,
    OrderDay? previous,
  }) async {
    final uri = _uri(baseUrl, '/api/v1/today');
    if (uri == null) return const OrderFetchResult(OrderFetchStatus.error);
    try {
      final response = await _client.get(uri, headers: _headers(user, password)).timeout(_timeout);
      if (response.statusCode == 401) return const OrderFetchResult(OrderFetchStatus.unauthorized);
      if (response.statusCode != 200) return const OrderFetchResult(OrderFetchStatus.error);
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (json['active'] != true) return const OrderFetchResult(OrderFetchStatus.ok);
      return OrderFetchResult(OrderFetchStatus.ok, _parse(json, previous));
    } catch (_) {
      return const OrderFetchResult(OrderFetchStatus.error);
    }
  }

  /// In den letzten [seconds] (10..600, Grenze des Servers) fertig gewordene
  /// Bestellungen, aelteste zuerst – oder null bei Fehler. Schlank (ohne QR),
  /// fuer haeufiges Abfragen an einem Bestelltag.
  Future<List<ReadyItem>?> fetchReady({
    required String baseUrl,
    required String user,
    required String password,
    required int seconds,
  }) async {
    final uri = _uri(baseUrl, '/api/v1/ready?seconds=${seconds.clamp(10, 600)}');
    if (uri == null) return null;
    try {
      final response = await _client.get(uri, headers: _headers(user, password)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (json['active'] != true) return const [];
      return [
        for (final item in (json['ready'] as List? ?? const []))
          ReadyItem.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();

  Uri? _uri(String baseUrl, String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base$path');
    return uri == null || !uri.hasScheme ? null : uri;
  }

  Map<String, String> _headers(String user, String password) => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('${user.trim()}:$password'))}',
        'Accept': 'application/json',
        'User-Agent': 'order_manager_client/1.0',
      };

  OrderDay _parse(Map<String, dynamic> json, OrderDay? previous) {
    final status = (json['status'] as Map?)?.cast<String, dynamic>() ?? const {};
    final qrBase64 = json['qr_png_base64'] as String? ?? '';
    Uint8List? qrPng;
    if (previous != null && previous.qrPngBase64 == qrBase64) {
      qrPng = previous.qrPng;
    } else if (qrBase64.isNotEmpty) {
      try {
        qrPng = base64Decode(qrBase64);
      } on FormatException {
        qrPng = null;
      }
    }
    return OrderDay(
      title: json['title'] as String? ?? '',
      hostName: json['host_name'] as String? ?? '',
      statusCode: status['code'] as String? ?? 'closed',
      statusLabel: status['label'] as String? ?? 'Geschlossen',
      statusIcon: status['icon'] as String? ?? '',
      courses: [
        for (final c in (json['courses'] as List? ?? const []))
          if (c is Map) Course('${c['code'] ?? ''}', '${c['label'] ?? ''}', '${c['icon'] ?? ''}'),
      ],
      url: json['url'] as String? ?? '',
      qrPngBase64: qrBase64,
      qrPng: qrPng,
    );
  }
}

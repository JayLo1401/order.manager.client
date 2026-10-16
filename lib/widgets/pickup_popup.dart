import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../order/order_service.dart';

/// „Bitte abholen“: abgedunkelter Hintergrund mit Karte in der Mitte (wie bisher im
/// home.radio). Gleiche Gerichte werden zusammengefasst („3× 🎃 Kürbiscremesuppe: Anna,
/// Ben, Carla“), jeder Name wird immer gezeigt (nie „… und 5 weitere“ – jeder muss
/// sich finden), und die Liste wird verkleinert statt abgeschnitten.
///
/// [showCloseButton]: in der App (fokussierbar fuer die Fernbedienung). In der
/// Einblendung hat das Fenster keinen Fokus – dort faengt der Dienst OK/Zurueck ab.
class PickupPopup extends StatelessWidget {
  final List<ReadyItem> items;
  final DateTime? since;
  final int durationSeconds;
  final VoidCallback onClose;
  final bool showCloseButton;

  const PickupPopup({
    super.key,
    required this.items,
    required this.since,
    required this.durationSeconds,
    required this.onClose,
    this.showCloseButton = false,
  });

  List<_DishGroup> _group() {
    final groups = <String, _DishGroup>{};
    for (final item in items) {
      groups.putIfAbsent('${item.itemIcon}|${item.itemName}', () => _DishGroup(item.itemIcon, item.itemName)).items.add(item);
    }
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Skaliert mit dem Bildschirm (Basis 1000 px Breite), wie das Tuerglocken-Popup in home.control.
    final s = (size.width / 1000).clamp(0.6, 2.0);
    final width = math.min(size.width * 0.7, 1400.0);
    final groups = _group();

    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Tippen auf die Karte schliesst nicht
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: size.height * 0.85),
              decoration: BoxDecoration(
                color: panelBackground.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(24 * s),
                border: Border.all(color: accentAmber, width: 3),
                boxShadow: [BoxShadow(color: accentAmber.withValues(alpha: 0.35), blurRadius: 40)],
              ),
              padding: EdgeInsets.fromLTRB(32 * s, 24 * s, 32 * s, 20 * s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.notifications_active_rounded, color: accentAmber, size: 48 * s),
                    SizedBox(width: 14 * s),
                    Expanded(
                      child: Text('Bitte abholen',
                          style: TextStyle(color: accentAmber, fontSize: 44 * s, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  SizedBox(height: 8 * s),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width - 64 * s,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [for (final g in groups) _GroupView(group: g, scale: s)],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16 * s),
                  if (since != null)
                    _Countdown(key: ValueKey(since), since: since!, seconds: durationSeconds),
                  SizedBox(height: 12 * s),
                  if (showCloseButton)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        autofocus: true,
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        label: Text('Schließen', style: TextStyle(fontSize: 20 * s)),
                      ),
                    )
                  else
                    Text('OK oder Zurück zum Schließen',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 14 * s)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Restzeit bis zum automatischen Schliessen.
class _Countdown extends StatelessWidget {
  final DateTime since;
  final int seconds;
  const _Countdown({super.key, required this.since, required this.seconds});

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(since).inMilliseconds / 1000 / seconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: (1 - elapsed).clamp(0.0, 1.0), end: 0),
      duration: Duration(milliseconds: (seconds * 1000 * (1 - elapsed)).clamp(0, 600000).round()),
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 6,
          color: accentAmber,
          backgroundColor: Colors.white10,
        ),
      ),
    );
  }
}

class _DishGroup {
  _DishGroup(this.icon, this.name);

  final String icon;
  final String name;
  final items = <ReadyItem>[];

  bool get hasOptions => items.any((i) => i.options.isNotEmpty);
}

class _GroupView extends StatelessWidget {
  final _DishGroup group;
  final double scale;
  const _GroupView({required this.group, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final count = group.items.length;
    final title = [if (count > 1) '$count×', if (group.icon.isNotEmpty) group.icon, group.name].join(' ');
    final nameStyle = TextStyle(color: Colors.white70, fontSize: 26 * s);

    return Padding(
      padding: EdgeInsets.only(top: 12 * s),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: Colors.white, fontSize: 32 * s, fontWeight: FontWeight.w700)),
        SizedBox(height: 4 * s),
        // Mit Optionen (z.B. Eissorte) braucht jeder Gast einen eigenen Block, damit klar
        // ist, wem was gehoert; ohne ist eine Namenszeile viel schneller erfasst.
        if (group.hasOptions)
          Wrap(spacing: 32 * s, runSpacing: 8 * s, children: [
            for (final item in group.items)
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.who, style: nameStyle),
                if (item.options.isNotEmpty)
                  Text(item.options, style: TextStyle(color: Colors.white54, fontSize: 20 * s)),
              ]),
          ])
        else
          Text(group.items.map((i) => i.who).join(', '), style: nameStyle),
      ]),
    );
  }
}

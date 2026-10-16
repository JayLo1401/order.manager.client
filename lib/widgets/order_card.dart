import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../order/order_service.dart';

/// Kuechenstatus + QR-Code als Karte – fuellt den verfuegbaren Platz (die Einblendung
/// bekommt vom Dienst ein Fenster genau in Kartengroesse). Schriftgroessen wachsen mit
/// der Karte mit, statt nur mehr Leerraum zu bekommen.
class OrderCard extends StatelessWidget {
  final OrderDay day;
  final OverlayLayout layout;

  const OrderCard({super.key, required this.day, this.layout = OverlayLayout.wide});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final radius = math.min(c.maxWidth, c.maxHeight) * 0.07;
      return Container(
        decoration: BoxDecoration(
          color: panelBackground.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(radius.clamp(8.0, 24.0)),
          border: Border.all(color: brandGreen.withValues(alpha: 0.6), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: layout == OverlayLayout.wide ? _Wide(day: day) : _Compact(day: day),
      );
    });
  }
}

class _Wide extends StatelessWidget {
  final OrderDay day;
  const _Wide({required this.day});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Relativ zur 420x260-Grundkachel aus home.radio.
      final s = math.min(c.maxHeight / 260, c.maxWidth / 420).clamp(0.3, 4.0);
      final padding = 14.0 * s;
      final qrSize = (c.maxHeight - 2 * padding).clamp(0.0, c.maxWidth * 0.5);
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Row(children: [
          Expanded(
            // Auf sehr kleinen Karten lieber verkleinern als ueberlaufen; die feste Breite
            // laesst den Zeilenumbruch wie unskaliert.
            child: LayoutBuilder(
              builder: (context, tc) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: tc.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bestellung aufgeben für',
                          style: TextStyle(color: Colors.white60, fontSize: 14 * s, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2 * s),
                      Text(
                        day.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white, fontSize: 20 * s, fontWeight: FontWeight.w700, height: 1.15),
                      ),
                      SizedBox(height: 6 * s),
                      Row(children: [
                        Icon(Icons.qr_code_scanner_rounded, color: Colors.white70, size: 16 * s),
                        SizedBox(width: 6 * s),
                        Flexible(
                          child: Text('Scanne einfach den QR-Code',
                              style: TextStyle(color: Colors.white70, fontSize: 13 * s)),
                        ),
                      ]),
                      SizedBox(height: 12 * s),
                      StatusBadge(day: day, scale: s),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: padding),
          QrBox(day: day, size: qrSize),
        ]),
      );
    });
  }
}

class _Compact extends StatelessWidget {
  final OrderDay day;
  const _Compact({required this.day});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Relativ zu einer 240 breiten Grundkarte.
      final s = (c.maxWidth / 240).clamp(0.3, 4.0);
      final padding = 10.0 * s;
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            day.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6 * s),
          Expanded(
            child: LayoutBuilder(
              builder: (context, qc) => Center(child: QrBox(day: day, size: math.min(qc.maxWidth, qc.maxHeight))),
            ),
          ),
          SizedBox(height: 8 * s),
          Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: StatusBadge(day: day, scale: s * 0.9)),
          ),
        ]),
      );
    });
  }
}

/// Kuechenstatus, z.B. „🍕 Pizzen werden angenommen“.
class StatusBadge extends StatelessWidget {
  final OrderDay day;
  final double scale;

  const StatusBadge({super.key, required this.day, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
      decoration: BoxDecoration(
        color: statusColor(day.statusCode).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20 * scale),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (day.statusIcon.isNotEmpty) ...[
          Text(day.statusIcon, style: TextStyle(fontSize: 15 * scale)),
          SizedBox(width: 6 * scale),
        ],
        Flexible(
          child: Text(
            day.statusLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontSize: 15 * scale, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

/// QR-Code auf eigenem weissen Feld mit Ruhezone – sonst auf dunklem Grund nicht scanbar.
class QrBox extends StatelessWidget {
  final OrderDay day;
  final double size;

  const QrBox({super.key, required this.day, required this.size});

  @override
  Widget build(BuildContext context) {
    final png = day.qrPng;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.04)),
      child: png == null
          ? FittedBox(child: Icon(Icons.qr_code_2_rounded, color: Colors.black26, size: size))
          : Image.memory(
              png,
              fit: BoxFit.contain,
              // Naechster Nachbar: Module bleiben scharf, egal wie gross.
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
    );
  }
}

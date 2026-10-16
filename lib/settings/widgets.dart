import 'package:flutter/material.dart';

import '../core/theme.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const SectionCard({super.key, required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) => Card(
        color: panelBackground,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, color: brandGreen),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class StatusLine extends StatelessWidget {
  final bool ok;
  final String text;
  const StatusLine({super.key, required this.ok, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error, color: ok ? brandGreen : Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]);
}

/// Plus/Minus-Einstellung (D-Pad-freundlicher als ein Slider).
class StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  const StepperRow({super.key, required this.label, required this.value, this.onDec, this.onInc});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          IconButton(onPressed: onDec, icon: const Icon(Icons.remove)),
          SizedBox(width: 120, child: Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
          IconButton(onPressed: onInc, icon: const Icon(Icons.add)),
        ]),
      );
}

/// Auswahl aus mehreren Moeglichkeiten als Liste (fokussierbar mit dem D-Pad).
class ChoiceTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const ChoiceTile({super.key, required this.selected, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        selected: selected,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? brandGreen : Colors.white54),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(color: Colors.white54)),
        onTap: onTap,
      );
}

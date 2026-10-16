import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../display/display_page.dart';
import '../order/order_service.dart';
import '../widgets/order_card.dart';
import '../widgets/pickup_popup.dart';
import 'widgets.dart';

const _homepage = 'https://github.com/JayLo1401/order.manager.client';

class SettingsPage extends StatefulWidget {
  /// Beim App-Start: im Modus „App-Anzeige“ direkt die Anzeige oeffnen.
  final bool openDisplayIfConfigured;
  const SettingsPage({super.key, this.openDisplayIfConfigured = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppConfig _config = AppConfig();
  bool _serviceOn = false;
  bool _autoEnable = false;
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  final _service = OrderService();
  OrderFetchResult? _server;
  bool _testing = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshService);
    _load(initial: true);
    _refreshService();
    _loadVersion();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    final c = await AppConfig.load();
    if (!mounted) return;
    setState(() {
      _config = c;
      _urlCtrl.text = c.baseUrl;
      _userCtrl.text = c.user;
      _passwordCtrl.text = c.password;
    });
    if (initial && widget.openDisplayIfConfigured && c.mode == DisplayMode.app && c.openDisplayOnStart) {
      _openDisplay();
    }
    _testServer();
  }

  Future<void> _loadVersion() async {
    final v = (await NativeBridge.deviceInfo())['appVersion'] ?? '';
    if (mounted) setState(() => _version = v);
  }

  Future<void> _refreshService() async {
    final on = await NativeBridge.isServiceEnabled();
    final auto = await NativeBridge.canAutoEnable();
    if (mounted) {
      setState(() {
        _serviceOn = on;
        _autoEnable = auto;
      });
    }
    // Wurde der Dienst gerade automatisch eingeschaltet, bindet Android ihn mit kurzer Verzoegerung.
    if (!on && auto) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final now = await NativeBridge.isServiceEnabled();
      if (mounted && now) setState(() => _serviceOn = true);
    }
  }

  Future<void> _save() async {
    await _config.save();
    // Der Dienst (Einblendung, Abhol-Meldungen) uebernimmt die Aenderungen sofort.
    await NativeBridge.reloadOverlayConfig();
    if (mounted) setState(() {});
  }

  void _set(VoidCallback fn) {
    setState(fn);
    _save();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openDisplay() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisplayPage()));
    _refreshService();
  }

  // ---------------------------------------------------------------- Verbindung

  Future<void> _testServer() async {
    if (!_config.isConfigured) {
      setState(() => _server = null);
      return;
    }
    setState(() => _testing = true);
    final r = await _service.fetchToday(baseUrl: _config.baseUrl, user: _config.user, password: _config.password);
    if (!mounted) return;
    setState(() {
      _server = r;
      _testing = false;
    });
  }

  Future<void> _saveConnection() async {
    _config
      ..baseUrl = _urlCtrl.text.trim()
      ..user = _userCtrl.text.trim()
      ..password = _passwordCtrl.text;
    await _save();
    await _testServer();
    if (mounted) _snack('Gespeichert – ${_serverText.$2}');
  }

  (bool, String) get _serverText {
    final r = _server;
    if (!_config.isConfigured) return (false, 'Server-Adresse, E-Mail und Passwort eintragen');
    if (r == null) return (false, 'Wird geprüft…');
    return switch (r.status) {
      OrderFetchStatus.ok when r.day != null => (true, 'Verbunden – heute: ${r.day!.title} (${r.day!.statusLabel})'),
      OrderFetchStatus.ok => (true, 'Verbunden – heute kein Bestelltag'),
      OrderFetchStatus.unauthorized => (false, 'E-Mail/Passwort falsch oder Konto nicht freigeschaltet'),
      OrderFetchStatus.error => (false, 'Server nicht erreichbar'),
    };
  }

  // ---------------------------------------------------------------- Tests

  Future<void> _preview() async {
    if (!await NativeBridge.previewOverlay()) {
      _snack('Hintergrunddienst ist nicht aktiv – siehe Tab „Verbindung“.');
    } else {
      _snack('Einblendung wird 15 Sekunden gezeigt. Jetzt z.B. home.radio öffnen.');
    }
  }

  Future<void> _testPickup() async {
    if (await NativeBridge.testPickup()) return;
    // Ohne Dienst: Meldung in der App zeigen.
    if (_config.pickupSound) NativeBridge.playChime(volume: _config.chimeVolumePercent / 100);
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, _) => Material(
        type: MaterialType.transparency,
        child: PickupPopup(
          items: ReadyItem.demo(),
          since: DateTime.now(),
          durationSeconds: _config.pickupSeconds,
          onClose: () => Navigator.of(ctx).pop(),
          showCloseButton: true,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    Widget tab(List<Widget> children) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(padding: const EdgeInsets.all(16), children: children),
          ),
        );
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: panelBackground,
          toolbarHeight: 64,
          title: Row(children: [
            Image.asset('assets/logo.png', width: 40, height: 40, filterQuality: FilterQuality.medium),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Order Manager Client',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.15)),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () async {
                  if (!await NativeBridge.openUrl(_homepage)) _snack('Kein Browser gefunden: $_homepage');
                },
                child: const Text('Powered by Jay',
                    style: TextStyle(color: brandGreen, fontWeight: FontWeight.w600, fontSize: 12, height: 1.3)),
              ),
            ]),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: _openDisplay,
                icon: const Icon(Icons.tv),
                label: const Text('Anzeige starten'),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tv), text: 'Anzeige'),
              Tab(icon: Icon(Icons.notifications_active), text: 'Bitte abholen'),
              Tab(icon: Icon(Icons.hub), text: 'Verbindung'),
            ],
          ),
        ),
        body: TabBarView(children: [
          tab([
            _modeSection(),
            if (_config.mode == DisplayMode.app) _appSection(),
            if (_config.mode == DisplayMode.overlay) _overlaySection(),
          ]),
          tab([_pickupSection()]),
          tab([_serviceSection(), _serverSection()]),
        ]),
        bottomNavigationBar: _statusBar(),
      ),
    );
  }

  /// Immer sichtbar: Dienst, Autostart, order.manager.
  Widget _statusBar() {
    Widget item(bool ok, IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: ok ? brandGreen : Colors.redAccent),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(fontSize: 13, color: ok ? Colors.white70 : Colors.redAccent)),
          ]),
        );
    final (serverOk, _) = _serverText;
    final day = _server?.day;
    return Container(
      color: panelBackground,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SafeArea(
        top: false,
        child: Wrap(alignment: WrapAlignment.center, runSpacing: 6, children: [
          item(_serviceOn, Icons.settings_remote, _serviceOn ? 'Dienst läuft' : 'Dienst aus'),
          item(_autoEnable, Icons.restart_alt, _autoEnable ? 'Autostart abgesichert' : 'Autostart fehlt'),
          item(serverOk, Icons.hub, serverOk ? 'order.manager verbunden' : 'order.manager nicht verbunden'),
          if (serverOk)
            item(true, Icons.restaurant, day != null ? 'Bestelltag: ${day.statusLabel}' : 'Heute kein Bestelltag'),
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('v$_version', style: const TextStyle(fontSize: 13, color: Colors.white38)),
            ),
        ]),
      ),
    );
  }

  Widget _serviceHint() => _serviceOn
      ? const SizedBox.shrink()
      : const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: StatusLine(
            ok: false,
            text: 'Der Hintergrunddienst ist nicht aktiv – ohne ihn gibt es keine Einblendung über anderen Apps '
                'und „Bitte abholen“ nur, solange die App-Anzeige offen ist (Tab „Verbindung“).',
          ),
        );

  Widget _modeSection() => SectionCard(title: 'Anzeigemodus', icon: Icons.view_quilt, children: [
        for (final m in DisplayMode.values)
          ChoiceTile(
            selected: _config.mode == m,
            title: m.label,
            subtitle: m.description,
            onTap: () => _set(() => _config.mode = m),
          ),
      ]);

  Widget _appSection() => SectionCard(title: 'App-Anzeige', icon: Icons.fit_screen, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _config.keepScreenOn,
          onChanged: (v) => _set(() => _config.keepScreenOn = v),
          title: const Text('Display nicht ausschalten'),
          subtitle: const Text('Solange die Anzeige offen ist, gehen Bildschirm und Bildschirmschoner nicht an bzw. aus.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _config.openDisplayOnStart,
          onChanged: (v) => _set(() => _config.openDisplayOnStart = v),
          title: const Text('Beim Öffnen der App direkt die Anzeige zeigen'),
          subtitle: const Text('Zurück führt dann zu diesen Einstellungen.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _config.launchOnBoot,
          onChanged: (v) => _set(() => _config.launchOnBoot = v),
          title: const Text('Nach dem Einschalten des Geräts automatisch öffnen'),
          subtitle: const Text('Braucht den Hintergrunddienst.'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _openDisplay,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Anzeige jetzt starten'),
          ),
        ),
      ]);

  Widget _overlaySection() {
    final c = _config;
    return SectionCard(title: 'Einblendung', icon: Icons.picture_in_picture, children: [
      _serviceHint(),
      const Text(
        'Erscheint an Bestelltagen über jeder App (home.radio, Spotify, …). Sie lässt sich nicht anklicken '
        'und nimmt der App darunter nicht den Fokus.',
        style: TextStyle(color: Colors.white54),
      ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Position', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          _positionGrid(),
        ]),
        const SizedBox(width: 24),
        Expanded(child: _screenPreview()),
      ]),
      const SizedBox(height: 12),
      for (final l in OverlayLayout.values)
        ChoiceTile(selected: c.overlayLayout == l, title: l.label, onTap: () => _set(() => c.overlayLayout = l)),
      const SizedBox(height: 8),
      StepperRow(
        label: 'Größe (Breite)',
        value: '${c.overlayWidthPercent} %',
        onDec: c.overlayWidthPercent > 10 ? () => _set(() => c.overlayWidthPercent -= 5) : null,
        onInc: c.overlayWidthPercent < 80 ? () => _set(() => c.overlayWidthPercent += 5) : null,
      ),
      StepperRow(
        label: 'Abstand zum Rand',
        value: '${c.overlayMarginPercent} %',
        onDec: c.overlayMarginPercent > 0 ? () => _set(() => c.overlayMarginPercent -= 1) : null,
        onInc: c.overlayMarginPercent < 20 ? () => _set(() => c.overlayMarginPercent += 1) : null,
      ),
      StepperRow(
        label: 'Deckkraft',
        value: '${c.overlayOpacityPercent} %',
        onDec: c.overlayOpacityPercent > 40 ? () => _set(() => c.overlayOpacityPercent -= 5) : null,
        onInc: c.overlayOpacityPercent < 100 ? () => _set(() => c.overlayOpacityPercent += 5) : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: c.overlayWhenClosed,
        onChanged: (v) => _set(() => c.overlayWhenClosed = v),
        title: const Text('Auch zeigen, wenn die Küche geschlossen ist'),
        subtitle: const Text('Sonst nur, solange Bestellungen angenommen werden.'),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _preview,
          icon: const Icon(Icons.visibility),
          label: const Text('Vorschau (15 s)'),
        ),
      ),
    ]);
  }

  /// 3x3-Tasten fuer die Position (D-Pad-freundlich).
  Widget _positionGrid() {
    const icons = [
      Icons.north_west, Icons.north, Icons.north_east, //
      Icons.west, Icons.center_focus_strong, Icons.east,
      Icons.south_west, Icons.south, Icons.south_east,
    ];
    return SizedBox(
      width: 156,
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final p in OverlayPosition.values)
          SizedBox(
            width: 48,
            height: 48,
            child: Tooltip(
              message: p.label,
              child: IconButton(
                onPressed: () => _set(() => _config.overlayPosition = p),
                isSelected: _config.overlayPosition == p,
                style: IconButton.styleFrom(
                  backgroundColor: _config.overlayPosition == p ? brandGreenDark : tileBackground,
                ),
                icon: Icon(icons[p.index], color: _config.overlayPosition == p ? Colors.white : Colors.white54),
              ),
            ),
          ),
      ]),
    );
  }

  /// Verkleinerter Bildschirm mit der Einblendung an Position und in Groesse.
  Widget _screenPreview() {
    final c = _config;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth * c.overlayWidthPercent / 100;
        final h = w * c.overlayLayout.aspect;
        final m = box.maxWidth * c.overlayMarginPercent / 100;
        final align = _alignment(c.overlayPosition);
        return Container(
          decoration: BoxDecoration(
            color: tileBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 2),
          ),
          padding: EdgeInsets.all(m),
          child: Align(
            alignment: align,
            child: SizedBox(
              width: w,
              height: h.clamp(0.0, box.maxHeight - 2 * m - 4),
              child: Opacity(
                opacity: c.overlayOpacityPercent / 100,
                child: OrderCard(day: _server?.day ?? OrderDay.demo, layout: c.overlayLayout),
              ),
            ),
          ),
        );
      }),
    );
  }

  static Alignment _alignment(OverlayPosition p) => switch (p) {
        OverlayPosition.topLeft => Alignment.topLeft,
        OverlayPosition.topCenter => Alignment.topCenter,
        OverlayPosition.topRight => Alignment.topRight,
        OverlayPosition.centerLeft => Alignment.centerLeft,
        OverlayPosition.center => Alignment.center,
        OverlayPosition.centerRight => Alignment.centerRight,
        OverlayPosition.bottomLeft => Alignment.bottomLeft,
        OverlayPosition.bottomCenter => Alignment.bottomCenter,
        OverlayPosition.bottomRight => Alignment.bottomRight,
      };

  Widget _pickupSection() {
    final c = _config;
    return SectionCard(title: 'Bitte abholen', icon: Icons.notifications_active, children: [
      _serviceHint(),
      const Text(
        'Sobald die Küche eine Bestellung als fertig markiert, erscheint über allem eine Meldung – mit Gong. '
        'Laufende Musik (home.radio, Spotify, …) wird dabei kurz leiser gestellt.',
        style: TextStyle(color: Colors.white54),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: c.pickupEnabled,
        onChanged: (v) => _set(() => c.pickupEnabled = v),
        title: const Text('„Bitte abholen“ anzeigen'),
      ),
      StepperRow(
        label: 'Anzeigedauer',
        value: '${c.pickupSeconds} s',
        onDec: c.pickupSeconds > 10 ? () => _set(() => c.pickupSeconds -= 10) : null,
        onInc: c.pickupSeconds < 300 ? () => _set(() => c.pickupSeconds += 10) : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: c.pickupSound,
        onChanged: (v) => _set(() => c.pickupSound = v),
        title: const Text('Gong abspielen'),
      ),
      StepperRow(
        label: 'Lautstärke Gong',
        value: '${c.chimeVolumePercent} %',
        onDec: c.pickupSound && c.chimeVolumePercent > 10 ? () => _set(() => c.chimeVolumePercent -= 10) : null,
        onInc: c.pickupSound && c.chimeVolumePercent < 100 ? () => _set(() => c.chimeVolumePercent += 10) : null,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _testPickup,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('„Bitte abholen“ testen'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Hinweis: Läutet gleichzeitig die Türglocke von home.control, liegen beide Meldungen übereinander – '
        'die zuletzt erschienene ist oben.',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      ),
    ]);
  }

  Widget _serviceSection() => SectionCard(title: 'Hintergrunddienst', icon: Icons.settings_remote, children: [
        StatusLine(
          ok: _serviceOn,
          text: _serviceOn
              ? 'Dienst läuft'
              : 'Dienst ist nicht aktiv – in den Bedienungshilfen „Order Manager Client“ einschalten.',
        ),
        const SizedBox(height: 8),
        StatusLine(
          ok: _autoEnable,
          text: _autoEnable
              ? 'Autostart abgesichert: Der Dienst schaltet sich nach Neustart, Update oder „Beenden erzwingen“ '
                  '(beim nächsten Öffnen der App) selbst wieder ein.'
              : 'Autostart nicht abgesichert. Einmalig am PC ausführen:\n'
                  'adb shell pm grant org.lotzapp.order_manager_client android.permission.WRITE_SECURE_SETTINGS',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: NativeBridge.openAccessibilitySettings,
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Bedienungshilfen öffnen'),
          ),
        ),
      ]);

  Widget _serverSection() {
    final (ok, text) = _serverText;
    final c = _config;
    return SectionCard(title: 'order.manager', icon: Icons.hub, children: [
      StatusLine(ok: ok, text: text),
      const SizedBox(height: 12),
      TextField(
        controller: _urlCtrl,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Server-Adresse', hintText: AppConfig.defaultBaseUrl),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _userCtrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-Mail (order.manager-Konto)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordCtrl,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Passwort'),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _testing ? null : _saveConnection,
          icon: _testing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link),
          label: const Text('Speichern & testen'),
        ),
      ),
      const Divider(height: 32),
      StepperRow(
        label: 'Aktualisieren alle',
        value: '${c.pollSeconds} s',
        onDec: c.pollSeconds > 5 ? () => _set(() => c.pollSeconds -= 5) : null,
        onInc: c.pollSeconds < 60 ? () => _set(() => c.pollSeconds += 5) : null,
      ),
      const Text(
        'Angemeldet wird mit dem eigenen order.manager-Konto des Gastgebers (HTTP Basic). '
        'Bitte nur über HTTPS verwenden.',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      ),
    ]);
  }
}

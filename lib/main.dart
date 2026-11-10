
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'download_stub.dart' if (dart.library.html) 'download_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dark = prefs.getBool('split_dark_mode') ?? true;
  _themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
  runApp(const SplitApp());
}

final _themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> toggleTheme() async {
  final next =
      _themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  _themeMode.value = next;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('split_dark_mode', next == ThemeMode.dark);
}

/// Muted text colors that adapt to the current brightness.
extension ThemeHelpers on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get muted => isDark ? Colors.white60 : Colors.black54;
  Color get faint => isDark ? Colors.white54 : Colors.black45;
  Color get subtle => isDark ? Colors.white70 : Colors.black87;
}

// RolodexAI look: vibrant dark mode, cosmic purple brand, neon highlights.
const _brand = Color(0xFF9B87F5); // vibrant purple
const _accent = Color(0xFFFF4D94); // neon pink highlight
const _neonBlue = Color(0xFF4DA6FF); // neon blue highlight
const _bg = Color(0xFF0A0A10); // deep space black

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ThemeData(brightness: brightness);
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: _brand, brightness: brightness),
    useMaterial3: true,
    // Scaffolds are transparent so the aurora gradient shows through.
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: dark ? Colors.white : const Color(0xFF12211D),
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade200,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF17171F) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.grey.shade300,
        ),
      ),
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor:
          dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
      labelStyle: TextStyle(color: dark ? Colors.white : Colors.black87),
    ),
  );
}

class SplitApp extends StatelessWidget {
  const SplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Split',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: mode,
        // Aurora backdrop: dark cosmic glows, or soft pastel tints in light.
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: mode == ThemeMode.dark
                  ? const [
                      Color(0xFF1B1533),
                      _bg,
                      _bg,
                      Color(0xFF141021),
                    ]
                  : const [
                      Color(0xFFEDE9FE),
                      Color(0xFFF6F8F7),
                      Color(0xFFF6F8F7),
                      Color(0xFFFDE7F1),
                    ],
              stops: const [0.0, 0.35, 0.7, 1.0],
            ),
          ),
          child: child,
        ),
        home: const RootScreen(),
      ),
    );
  }
}

// ---------- session ----------
class Session {
  final String code;
  final int memberId;
  final String nickname;
  const Session(this.code, this.memberId, this.nickname);
}

/// Upserts a group into the saved My Groups list (SharedPreferences).
/// Shared by the landing screen and the group screen so going home always
/// leaves the current group in the list.
Future<void> persistMyGroup(String code, String name, String nickname, int memberId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('split_my_groups');
  var list = <Map<String, dynamic>>[];
  if (raw != null && raw.isNotEmpty) {
    try {
      list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
  }
  list = [
    {'code': code, 'name': name, 'nickname': nickname, 'memberId': memberId},
    ...list.where((g) => g['code'] != code),
  ];
  await prefs.setString('split_my_groups', jsonEncode(list));
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  Session? _session;
  String? _joinCodePrefill;
  bool _loading = true;
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('split_code');
    final memberId = prefs.getInt('split_member_id');
    final nickname = prefs.getString('split_nickname');
    final urlCode = Uri.base.queryParameters['code'];
    setState(() {
      if (code != null && memberId != null && nickname != null) {
        _session = Session(code, memberId, nickname);
      }
      _joinCodePrefill = urlCode?.toUpperCase();
      _loading = false;
    });
  }

  Future<void> _saveSession(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('split_code', s.code);
    await prefs.setInt('split_member_id', s.memberId);
    await prefs.setString('split_nickname', s.nickname);
    setState(() {
      _session = s;
      _showHome = false;
    });
  }

  Future<void> _leave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('split_code');
    await prefs.remove('split_member_id');
    await prefs.remove('split_nickname');
    setState(() {
      _session = null;
      _showHome = false;
    });
  }

  void _goHome() {
    // Back to the landing screen without leaving the group: the session
    // stays stored, so reopening the app still restores it.
    setState(() => _showHome = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session != null && !_showHome) {
      return GroupScreen(session: _session!, onLeave: _leave, onHome: _goHome);
    }
    return LandingScreen(prefillCode: _joinCodePrefill, onSession: _saveSession);
  }
}

// ---------- landing ----------
class LandingScreen extends StatefulWidget {
  final String? prefillCode;
  final Future<void> Function(Session) onSession;
  const LandingScreen({super.key, this.prefillCode, required this.onSession});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _createGroupName = TextEditingController();
  final _createNick = TextEditingController();
  final _joinCode = TextEditingController();
  final _joinNick = TextEditingController();
  bool _busy = false;
  List<Map<String, dynamic>> _myGroups = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.prefillCode != null && widget.prefillCode!.isNotEmpty) {
      _joinCode.text = widget.prefillCode!;
      _tabs.index = 1;
    }
    _loadMyGroups();
  }

  Future<void> _loadMyGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('split_my_groups');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _myGroups = list);
    } catch (_) {
      // Corrupt saved list: ignore it rather than crashing the landing screen.
    }
  }

  Future<void> _saveMyGroup(String code, String name, String nickname, int memberId) async {
    final entry = {
      'code': code,
      'name': name,
      'nickname': nickname,
      'memberId': memberId,
    };
    _myGroups = [
      entry,
      ..._myGroups.where((g) => g['code'] != code),
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('split_my_groups', jsonEncode(_myGroups));
    if (mounted) setState(() {});
  }

  Future<void> _forgetMyGroup(String code) async {
    _myGroups = _myGroups.where((g) => g['code'] != code).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('split_my_groups', jsonEncode(_myGroups));
    setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _createGroupName.dispose();
    _createNick.dispose();
    _joinCode.dispose();
    _joinNick.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _create() async {
    final name = _createGroupName.text.trim();
    final nick = _createNick.text.trim();
    if (name.isEmpty || nick.isEmpty) return _snack('Give the group a name and your nickname.');
    setState(() => _busy = true);
    try {
      final g = await SplitApi.createGroup(name, nick);
      await _saveMyGroup(
        g['code'] as String,
        g['name'] as String? ?? name,
        nick,
        g['your_member_id'] as int,
      );
      await widget.onSession(Session(g['code'] as String, g['your_member_id'] as int, nick));
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _joinCode.text.trim().toUpperCase();
    final nick = _joinNick.text.trim();
    if (code.isEmpty || nick.isEmpty) return _snack('Enter the group code and your nickname.');
    setState(() => _busy = true);
    try {
      final g = await SplitApi.joinGroup(code, nick);
      await _saveMyGroup(
        g['code'] as String,
        g['name'] as String? ?? code,
        nick,
        g['your_member_id'] as int,
      );
      await widget.onSession(Session(g['code'] as String, g['your_member_id'] as int, nick));
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(context.isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded),
                      tooltip: context.isDark
                          ? 'Switch to light mode'
                          : 'Switch to dark mode',
                      onPressed: toggleTheme,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_brand, _neonBlue],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.call_split_rounded, size: 44, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text('Split',
                      style: GoogleFonts.outfit(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Snap receipts. Split them equally.\nSettle up in seconds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: context.muted, height: 1.4),
                  ),
                ),
                const SizedBox(height: 28),
                if (_myGroups.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('YOUR GROUPS',
                        style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.faint)),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: _myGroups.map<Widget>((g) {
                        final name = g['name'] as String? ?? g['code'] as String;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _avatarColor(name),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              'Code: ${g['code']} • as ${g['nickname']}',
                              style: TextStyle(color: context.muted, fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: 'Forget this group',
                            onPressed: () => _forgetMyGroup(g['code'] as String),
                          ),
                          onTap: () => widget.onSession(Session(
                            g['code'] as String,
                            g['memberId'] as int,
                            g['nickname'] as String,
                          )),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TabBar(
                          controller: _tabs,
                          labelColor: _brand,
                          unselectedLabelColor: context.faint,
                          indicatorColor: _brand,
                          tabs: const [
                            Tab(text: 'Create a group'),
                            Tab(text: 'Join a group'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 240,
                          child: TabBarView(
                            controller: _tabs,
                            children: [
                              _createForm(),
                              _joinForm(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'No accounts. No passwords.\nJust share the group link and pick a nickname.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.faint, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _createForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _createGroupName,
            decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Goa Trip'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _createNick,
            decoration: const InputDecoration(labelText: 'Your nickname', hintText: 'e.g. Salman'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.group_add_rounded),
            label: const Text('Create group'),
          ),
        ],
      );

  Widget _joinForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _joinCode,
            decoration: const InputDecoration(
              labelText: 'Group code',
              hintText: 'e.g. K7X2PQ',
              prefixIcon: Icon(Icons.key_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _joinNick,
            decoration: const InputDecoration(labelText: 'Your nickname', hintText: 'e.g. Salman'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _join,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login_rounded),
            label: const Text('Join group'),
          ),
        ],
      );
}

// ---------- balance engine ----------
// Client-side balances: per-expense shares (equal / shares / items), then
// settlements applied, then minimal transfers. All money is rounded to cents.

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

double _round2(double v) => (v * 100).round() / 100;

/// Per-expense shares keyed by member id. Shares always sum exactly to total.
Map<int, double> expenseShares(Map<String, dynamic> expense, List<int> memberIds) {
  final total = _num(expense['total']);
  if (memberIds.isEmpty || total <= 0) {
    return {for (final id in memberIds) id: 0.0};
  }
  final mode = expense['split_mode'] as String? ?? 'equal';
  final data = expense['split_data'] as Map<String, dynamic>?;
  final raw = <int, double>{for (final id in memberIds) id: 0.0};

  if (mode == 'shares') {
    final weights = (data?['weights'] as Map?) ?? {};
    final w = <int, double>{};
    double sumW = 0;
    for (final id in memberIds) {
      final wi = _num(weights[id.toString()] ?? weights[id] ?? 1);
      w[id] = wi > 0 ? wi : 0;
      sumW += w[id]!;
    }
    if (sumW <= 0) {
      for (final id in memberIds) {
        raw[id] = total / memberIds.length;
      }
    } else {
      for (final id in memberIds) {
        raw[id] = total * w[id]! / sumW;
      }
    }
  } else if (mode == 'items') {
    final items = (data?['items'] as List?) ?? [];
    double itemsSum = 0;
    for (final item in items) {
      final it = item as Map;
      final price = _num(it['price']);
      itemsSum += price;
      final assigned = ((it['members'] as List?) ?? [])
          .map((m) => m is int ? m : int.tryParse('$m') ?? -1)
          .where(memberIds.contains)
          .toList();
      final targets = assigned.isEmpty ? memberIds : assigned;
      for (final id in targets) {
        raw[id] = raw[id]! + price / targets.length;
      }
    }
    // Remainder (tax/tip, or item prices not covering the total) is shared equally.
    final remainder = total - itemsSum;
    if (remainder != 0) {
      for (final id in memberIds) {
        raw[id] = raw[id]! + remainder / memberIds.length;
      }
    }
  } else {
    for (final id in memberIds) {
      raw[id] = total / memberIds.length;
    }
  }

  // Round to cents; distribute the residual cent-by-cent (largest shares
  // first) so the shares sum exactly to the total.
  final totalCents = (total * 100).round();
  final cents = <int, int>{};
  var sumCents = 0;
  for (final id in memberIds) {
    cents[id] = (raw[id]! * 100).round();
    sumCents += cents[id]!;
  }
  var residual = totalCents - sumCents;
  final ordered = List<int>.from(memberIds)
    ..sort((a, b) => residual > 0
        ? raw[b]!.compareTo(raw[a]!)
        : raw[a]!.compareTo(raw[b]!));
  var i = 0;
  while (residual != 0 && ordered.isNotEmpty && i < ordered.length * 1000) {
    final id = ordered[i % ordered.length];
    if (residual > 0) {
      cents[id] = cents[id]! + 1;
      residual--;
    } else if (cents[id]! > 0) {
      cents[id] = cents[id]! - 1;
      residual++;
    }
    i++;
  }
  return {for (final id in memberIds) id: cents[id]! / 100};
}

class GroupBalances {
  final Map<int, double> paid;
  final Map<int, double> share;
  final Map<int, double> net;
  final List<Map<String, dynamic>> transfers; // from_member_id, to_member_id, from, to, amount (String)
  const GroupBalances({
    required this.paid,
    required this.share,
    required this.net,
    required this.transfers,
  });
}

GroupBalances computeGroupBalances(Map<String, dynamic> group) {
  final members = (group['members'] as List?) ?? [];
  final memberIds = members.map<int>((m) => m['id'] as int).toList();
  final names = {
    for (final m in members) m['id'] as int: m['nickname'] as String
  };
  final paid = {for (final id in memberIds) id: 0.0};
  final share = {for (final id in memberIds) id: 0.0};
  for (final e in (group['expenses'] as List?) ?? []) {
    final exp = e as Map<String, dynamic>;
    final payerId = exp['payer_id'] as int?;
    if (payerId != null && paid.containsKey(payerId)) {
      paid[payerId] = paid[payerId]! + _num(exp['total']);
    }
    final shares = expenseShares(exp, memberIds);
    for (final id in memberIds) {
      share[id] = share[id]! + (shares[id] ?? 0);
    }
  }
  final net = <int, double>{};
  for (final id in memberIds) {
    net[id] = _round2(paid[id]! - share[id]!);
  }
  // Settlements: from owes less, to is owed less.
  for (final s in (group['settlements'] as List?) ?? []) {
    final st = s as Map<String, dynamic>;
    final amt = _num(st['amount']);
    final from = st['from_member_id'] as int?;
    final to = st['to_member_id'] as int?;
    if (from != null && net.containsKey(from)) net[from] = _round2(net[from]! + amt);
    if (to != null && net.containsKey(to)) net[to] = _round2(net[to]! - amt);
  }
  // Minimal transfers: greedy largest-debtor to largest-creditor.
  final debtors = <int, double>{};
  final creditors = <int, double>{};
  for (final id in memberIds) {
    if (net[id]! < -0.005) debtors[id] = -net[id]!;
    if (net[id]! > 0.005) creditors[id] = net[id]!;
  }
  final transfers = <Map<String, dynamic>>[];
  while (debtors.isNotEmpty && creditors.isNotEmpty) {
    final dId = debtors.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final cId = creditors.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final amt = _round2(math.min(debtors[dId]!, creditors[cId]!));
    if (amt <= 0) break;
    transfers.add({
      'from_member_id': dId,
      'to_member_id': cId,
      'from': names[dId] ?? '',
      'to': names[cId] ?? '',
      'amount': amt.toStringAsFixed(2),
    });
    debtors[dId] = _round2(debtors[dId]! - amt);
    creditors[cId] = _round2(creditors[cId]! - amt);
    if (debtors[dId]! <= 0.005) debtors.remove(dId);
    if (creditors[cId]! <= 0.005) creditors.remove(cId);
  }
  return GroupBalances(paid: paid, share: share, net: net, transfers: transfers);
}

/// Server timestamps are UTC with no zone marker ("2026-11-10 14:23:11").
DateTime? _parseTs(String? s) {
  if (s == null || s.isEmpty) return null;
  final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final iso = hasTz ? s : '${s.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(iso)?.toLocal();
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String _shortDate(String? ts) {
  final t = _parseTs(ts);
  if (t == null) return (ts ?? '').length > 10 ? ts!.substring(0, 10) : (ts ?? '');
  return '${_monthNames[t.month - 1].substring(0, 3)} ${t.day}';
}

String _csvCell(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

// ---------- group ----------
class GroupScreen extends StatefulWidget {
  final Session session;
  final Future<void> Function() onLeave;
  final VoidCallback onHome;
  const GroupScreen({super.key, required this.session, required this.onLeave, required this.onHome});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _group;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final g = await SplitApi.getGroup(widget.session.code);
      if (!mounted) return;
      setState(() {
        _group = g;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _inviteLink() => '${Uri.base.origin}/?code=${widget.session.code}';

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: _inviteLink()));
    _snack('Invite link copied — send it to your friends.');
  }

  Future<void> _openAddExpense() async {
    final members = (_group?['members'] as List?) ?? [];
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => AddExpenseDialog(session: widget.session, members: members),
    );
    if (changed == true) _refresh();
  }

  Future<void> _deleteExpense(int id, String merchant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Remove "$merchant" from the group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final g = await SplitApi.deleteExpense(widget.session.code, id);
      setState(() {
        _group = g;
      });
      _snack('Expense deleted.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _goHome() async {
    // Make sure this group is in My Groups, then go to the landing screen.
    await persistMyGroup(
      widget.session.code,
      _group?['name'] as String? ?? 'Split',
      widget.session.nickname,
      widget.session.memberId,
    );
    widget.onHome();
  }

  @override
  Widget build(BuildContext context) {
    final members = (_group?['members'] as List?) ?? [];
    final expenses = (_group?['expenses'] as List?) ?? [];
    final total = _group?['total'] as String? ?? '0.00';
    final gb = _group == null ? null : computeGroupBalances(_group!);
    final myShare = gb == null
        ? '0.00'
        : (gb.share[widget.session.memberId] ?? 0).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'My groups',
          onPressed: _goHome,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_group?['name'] as String? ?? 'Split',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Code: ${widget.session.code} • You are ${widget.session.nickname}',
                style: TextStyle(fontSize: 12, color: context.subtle)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'theme') {
                await toggleTheme();
              } else if (v == 'invite') {
                await _copyInvite();
              } else if (v == 'export') {
                _showExportMenu();
              } else if (v == 'refresh') {
                await _refresh();
              } else if (v == 'leave') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Leave group?'),
                    content: const Text('You can rejoin anytime with the code and your nickname.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
                    ],
                  ),
                );
                if (ok == true) await widget.onLeave();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(context.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(context.isDark ? 'Switch to light mode' : 'Switch to dark mode'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'invite',
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Copy invite link'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Export / monthly summary'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Leave group'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: context.subtle,
          indicatorColor: _accent,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Expenses'),
            Tab(icon: Icon(Icons.account_balance_wallet_rounded), text: 'Balances'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _refresh, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _expensesTab(members, expenses, total, myShare),
                        if (gb != null) _balancesTab(gb),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAddExpense,
              backgroundColor: _accent,
              foregroundColor: Colors.black87,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _expensesTab(List members, List expenses, String total, String myShare) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _brand,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL SPENT',
                      style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2)),
                  const SizedBox(height: 4),
                  Text('\$$total',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    members.isEmpty
                        ? 'No members yet'
                        : 'Your share: \$$myShare • ${members.length} ${members.length == 1 ? 'person' : 'people'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (members.isNotEmpty) ...[
            Text('MEMBERS',
                style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.faint)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map<Widget>((m) {
                final nick = m['nickname'] as String;
                final isMe = m['id'] == widget.session.memberId;
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: _avatarColor(nick),
                    child: Text(
                      nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(isMe ? '$nick (you)' : nick),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          Text('EXPENSES',
              style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.faint)),
          const SizedBox(height: 8),
          if (expenses.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No expenses yet.\nSnap your first receipt to get splitting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted, height: 1.5),
                  ),
                ),
              ),
            )
          else
            ...expenses.map<Widget>((e) {
              final receipt = e['receipt'] as String?;
              return Card(
                child: ListTile(
                  leading: receipt != null
                      ? GestureDetector(
                          onTap: () => _showReceipt(receipt),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              '/uploads/$receipt',
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.receipt_rounded, size: 32),
                            ),
                          ),
                        )
                      : Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _brand.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.receipt_rounded, color: _brand),
                        ),
                  title: Text(e['merchant'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Paid by ${e['payer']} • ${e['date']}${(e['note'] as String).isNotEmpty ? ' • ${e['note']}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('\$${e['total']}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        tooltip: 'Delete',
                        onPressed: () => _deleteExpense(e['id'] as int, e['merchant'] as String),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _showReceipt(String filename) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network('/uploads/$filename',
                  errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Receipt image unavailable.'),
                      )),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balancesTab(GroupBalances gb) {
    final members = (_group?['members'] as List?) ?? [];
    final settlements = (_group?['settlements'] as List?) ?? [];
    final nudges = (_group?['nudges'] as List?) ?? [];
    final transfers = gb.transfers;
    final allSettled = transfers.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WHO PAID WHAT',
                    style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.faint)),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  const Text('Nobody here yet.')
                else
                  ...members.map<Widget>((m) {
                    final id = m['id'] as int;
                    final nick = m['nickname'] as String;
                    final net = gb.net[id] ?? 0;
                    final isMe = id == widget.session.memberId;
                    final label = net > 0.005
                        ? 'gets back \$${net.abs().toStringAsFixed(2)}'
                        : net < -0.005
                            ? 'owes \$${net.abs().toStringAsFixed(2)}'
                            : 'all settled';
                    final color = net > 0.005
                        ? Colors.green.shade400
                        : net < -0.005
                            ? Colors.red.shade400
                            : context.faint;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _avatarColor(nick),
                            child: Text(
                              nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$nick${isMe ? ' (you)' : ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('Paid \$${(gb.paid[id] ?? 0).toStringAsFixed(2)} • Share \$${(gb.share[id] ?? 0).toStringAsFixed(2)}',
                                    style: TextStyle(color: context.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: allSettled
              ? Colors.green.withValues(alpha: 0.12)
              : Colors.amber.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(allSettled ? Icons.check_circle_rounded : Icons.handshake_rounded,
                        color: allSettled ? Colors.green.shade300 : Colors.amber.shade300),
                    const SizedBox(width: 8),
                    Text(allSettled ? 'Everyone is settled up' : 'SETTLE UP',
                        style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                if (!allSettled)
                  ...transfers.map<Widget>((t) => _transferRow(t, nudges)),
                if (!allSettled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Fewest payments possible — just these transfers and everyone is even.',
                      style: TextStyle(color: context.muted, fontSize: 13),
                    ),
                  ),
                if (settlements.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('RECORDED PAYMENTS',
                      style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: context.faint)),
                  const SizedBox(height: 4),
                  ...settlements.map<Widget>((s) {
                    final from = _memberName(members, s['from_member_id'] as int?);
                    final to = _memberName(members, s['to_member_id'] as int?);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$from paid $to \$${_num(s['amount']).toStringAsFixed(2)} • ${_shortDate(s['created_at'] as String?)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.undo_rounded, size: 20),
                            tooltip: 'Undo payment',
                            onPressed: () => _undoSettlement(s['id'] as int),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  String _memberName(List members, int? id) {
    for (final m in members) {
      if (m['id'] == id) return m['nickname'] as String;
    }
    return 'Someone';
  }

  Widget _transferRow(Map<String, dynamic> t, List nudges) {
    final fromId = t['from_member_id'] as int;
    final toId = t['to_member_id'] as int;
    final amount = _num(t['amount']);
    DateTime? latestNudge;
    for (final n in nudges) {
      final nn = n as Map<String, dynamic>;
      if (nn['from_member_id'] == fromId && nn['to_member_id'] == toId) {
        final ts = _parseTs(nn['created_at'] as String?);
        if (ts != null && (latestNudge == null || ts.isAfter(latestNudge))) {
          latestNudge = ts;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${t['from']}  →  ${t['to']}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Text('\$${amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _transferAction(Icons.check_circle_outline_rounded, 'Mark paid',
                  () => _showMarkPaid(t)),
              _transferAction(Icons.payment_rounded, 'Pay', () => _showPaySheet(t)),
              _transferAction(Icons.notifications_active_outlined, 'Nudge',
                  () => _showNudgeDialog(t)),
              const Spacer(),
              if (latestNudge != null)
                Text('Nudged ${_relativeTime(latestNudge)}',
                    style: TextStyle(color: context.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transferAction(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  Future<void> _undoSettlement(int id) async {
    try {
      await SplitApi.deleteSettlement(widget.session.code, id);
      _snack('Payment undone.');
      _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _showMarkPaid(Map<String, dynamic> t) async {
    final remaining = _num(t['amount']);
    final controller =
        TextEditingController(text: remaining.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark paid — ${t['from']} → ${t['to']}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: 'Amount paid', prefixText: '\$ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(controller.text.trim());
    if (amt == null || amt <= 0 || amt > remaining) {
      _snack(
          'Enter an amount greater than 0 and no more than \$${remaining.toStringAsFixed(2)}.');
      return;
    }
    try {
      await SplitApi.createSettlement(
        widget.session.code,
        fromMemberId: t['from_member_id'] as int,
        toMemberId: t['to_member_id'] as int,
        amount: amt,
      );
      _snack('Payment recorded.');
      _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _showPaySheet(Map<String, dynamic> t) async {
    final members = (_group?['members'] as List?) ?? [];
    Map<String, dynamic>? toMember;
    for (final m in members) {
      final mm = Map<String, dynamic>.from(m as Map);
      if (mm['id'] == t['to_member_id']) toMember = mm;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PaySheet(
        code: widget.session.code,
        toName: t['to'] as String,
        toMember: toMember,
        amount: _num(t['amount']).toStringAsFixed(2),
        groupName: _group?['name'] as String? ?? 'Split',
        onHandlesSaved: _refresh,
      ),
    );
  }

  Future<void> _showNudgeDialog(Map<String, dynamic> t) async {
    final fromId = t['from_member_id'] as int;
    final toId = t['to_member_id'] as int;
    final amount = _num(t['amount']).toStringAsFixed(2);
    final groupName = _group?['name'] as String? ?? 'Split';
    final message =
        'Hey ${t['from']}, you owe \$$amount for $groupName — settle up here: ${_inviteLink()}';
    final send = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nudge ${t['from']}'),
        content: SelectableText(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'copy'),
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'whatsapp'),
            child: const Text('Send via WhatsApp'),
          ),
        ],
      ),
    );
    if (send == null) return;
    try {
      if (send == 'copy') {
        await Clipboard.setData(ClipboardData(text: message));
        _snack('Nudge copied.');
      } else {
        final url = 'https://wa.me/?text=${Uri.encodeComponent(message)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      await SplitApi.createNudge(
        widget.session.code,
        fromMemberId: fromId,
        toMemberId: toId,
        amount: _num(t['amount']),
      );
      _refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _showExportMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_rounded),
              title: const Text('Export CSV'),
              subtitle: const Text('All expenses + balances'),
              onTap: () => Navigator.pop(ctx, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Monthly summary'),
              subtitle: const Text('Totals per month'),
              onTap: () => Navigator.pop(ctx, 'monthly'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (choice == 'csv') {
      _exportCsv();
    } else if (choice == 'monthly') {
      _showMonthlySummary();
    }
  }

  void _exportCsv() {
    final group = _group;
    if (group == null) return;
    final members = (group['members'] as List?) ?? [];
    final expenses = (group['expenses'] as List?) ?? [];
    final gb = computeGroupBalances(group);
    final buf = StringBuffer();
    buf.writeln('date,merchant,payer,total,tax,tip,note');
    for (final e in expenses) {
      final exp = e as Map<String, dynamic>;
      buf.writeln([
        _csvCell('${exp['date'] ?? ''}'),
        _csvCell('${exp['merchant'] ?? ''}'),
        _csvCell('${exp['payer'] ?? ''}'),
        _csvCell(_num(exp['total']).toStringAsFixed(2)),
        _csvCell(_num(exp['tax']).toStringAsFixed(2)),
        _csvCell(_num(exp['tip']).toStringAsFixed(2)),
        _csvCell('${exp['note'] ?? ''}'),
      ].join(','));
    }
    buf.writeln();
    buf.writeln('Balances');
    buf.writeln('member,paid,share,net');
    for (final m in members) {
      final id = m['id'] as int;
      buf.writeln([
        _csvCell(m['nickname'] as String),
        _csvCell((gb.paid[id] ?? 0).toStringAsFixed(2)),
        _csvCell((gb.share[id] ?? 0).toStringAsFixed(2)),
        _csvCell((gb.net[id] ?? 0).toStringAsFixed(2)),
      ].join(','));
    }
    final filename = 'split-${widget.session.code}-expenses.csv';
    try {
      downloadFile(filename, buf.toString());
      _snack('CSV downloaded: $filename');
    } on UnsupportedError {
      _snack('CSV download is only supported on web.');
    }
  }

  void _showMonthlySummary() {
    final group = _group;
    if (group == null) return;
    final members = (group['members'] as List?) ?? [];
    final expenses = (group['expenses'] as List?) ?? [];
    final byMonth = <String, List<Map<String, dynamic>>>{};
    for (final e in expenses) {
      final exp = e as Map<String, dynamic>;
      final date = '${exp['date'] ?? ''}';
      final key = date.length >= 7 ? date.substring(0, 7) : 'Unknown';
      byMonth.putIfAbsent(key, () => []).add(exp);
    }
    final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly summary'),
        content: SizedBox(
          width: double.maxFinite,
          child: keys.isEmpty
              ? const Text('No expenses yet.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: keys.length,
                  itemBuilder: (_, i) {
                    final key = keys[i];
                    final list = byMonth[key]!;
                    final total =
                        list.fold<double>(0, (s, e) => s + _num(e['total']));
                    final label = key == 'Unknown'
                        ? 'Unknown date'
                        : '${_monthNames[int.parse(key.substring(5, 7)) - 1]} ${key.substring(0, 4)}';
                    final perPerson = members.isEmpty
                        ? '—'
                        : '\$${(total / members.length).toStringAsFixed(2)} each';
                    return ListTile(
                      title: Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${list.length} expense${list.length == 1 ? '' : 's'} • $perPerson'),
                      trailing: Text('\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

// ---------- pay sheet ----------
class _PaySheet extends StatefulWidget {
  final String code;
  final String toName;
  final Map<String, dynamic>? toMember;
  final String amount;
  final String groupName;
  final VoidCallback onHandlesSaved;
  const _PaySheet({
    required this.code,
    required this.toName,
    required this.toMember,
    required this.amount,
    required this.groupName,
    required this.onHandlesSaved,
  });

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  String? _venmo;
  String? _cashapp;
  final _venmoController = TextEditingController();
  final _cashappController = TextEditingController();
  bool _savingVenmo = false;
  bool _savingCashapp = false;

  @override
  void initState() {
    super.initState();
    _venmo = widget.toMember?['venmo_handle'] as String?;
    _cashapp = widget.toMember?['cashapp_handle'] as String?;
  }

  @override
  void dispose() {
    _venmoController.dispose();
    _cashappController.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _cleanVenmo(String h) => h.trim().replaceFirst(RegExp(r'^@'), '');
  String _cleanCashapp(String h) => h.trim().replaceFirst(RegExp(r'^\$'), '');

  Future<void> _launch(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Could not open that app.');
  }

  Future<void> _saveHandle({required bool venmo}) async {
    final memberId = widget.toMember?['id'] as int?;
    if (memberId == null) return;
    final value = (venmo ? _venmoController : _cashappController).text.trim();
    if (value.isEmpty) return _snack('Enter a handle first.');
    setState(() {
      if (venmo) {
        _savingVenmo = true;
      } else {
        _savingCashapp = true;
      }
    });
    try {
      await SplitApi.updateMemberHandles(
        widget.code,
        memberId,
        venmoHandle: venmo ? value : null,
        cashappHandle: venmo ? null : value,
      );
      if (!mounted) return;
      setState(() {
        if (venmo) {
          _venmo = value;
        } else {
          _cashapp = value;
        }
      });
      widget.onHandlesSaved();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) {
        setState(() {
          if (venmo) {
            _savingVenmo = false;
          } else {
            _savingCashapp = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final venmoUrl = _venmo == null || _venmo!.isEmpty
        ? null
        : 'https://venmo.com/?txn=pay&recipients=${Uri.encodeComponent(_cleanVenmo(_venmo!))}&amount=${widget.amount}&note=${Uri.encodeComponent('Split ${widget.groupName}')}';
    final cashappUrl = _cashapp == null || _cashapp!.isEmpty
        ? null
        : 'https://cash.app/\$${Uri.encodeComponent(_cleanCashapp(_cashapp!))}/${widget.amount}';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ${widget.toName} • \$${widget.amount}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (venmoUrl != null)
              FilledButton.icon(
                onPressed: () => _launch(venmoUrl),
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Pay with Venmo'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _venmoController,
                      decoration: const InputDecoration(
                          labelText: 'Venmo handle', hintText: '@username'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _savingVenmo ? null : () => _saveHandle(venmo: true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (cashappUrl != null)
              FilledButton.icon(
                onPressed: () => _launch(cashappUrl),
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Pay with Cash App'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cashappController,
                      decoration: const InputDecoration(
                          labelText: 'Cash App handle', hintText: '\$cashtag'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _savingCashapp
                        ? null
                        : () => _saveHandle(venmo: false),
                    child: const Text('Save'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Zelle has no direct pay link — copy the amount and send it in your banking app.',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: widget.amount));
                    _snack('Amount copied.');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy amount'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _avatarColor(String name) {
  const palette = [
    Color(0xFF9B87F5),
    Color(0xFFFF4D94),
    Color(0xFF4DA6FF),
    Color(0xFF7E69AB),
    Color(0xFF8B5CF6),
    Color(0xFFD946EF),
    Color(0xFF0EA5E9),
    Color(0xFFC084FC),
  ];
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) % 997;
  }
  return palette[h % palette.length];
}

// ---------- add expense ----------
class _SplitItem {
  String name;
  double price;
  Set<int> assigned; // empty = everyone
  _SplitItem({required this.name, required this.price, Set<int>? assigned})
      : assigned = assigned ?? <int>{};
}

String _weightLabel(double w) => w % 1 == 0 ? '${w.toInt()}x' : '${w}x';

class AddExpenseDialog extends StatefulWidget {
  final Session session;
  final List members;
  const AddExpenseDialog({super.key, required this.session, required this.members});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _merchant = TextEditingController();
  final _total = TextEditingController();
  final _note = TextEditingController();
  final _tax = TextEditingController();
  final _tip = TextEditingController();
  final _itemName = TextEditingController();
  final _itemPrice = TextEditingController();
  DateTime _date = DateTime.now();
  String? _receiptFilename;
  XFile? _pickedImage;
  Future<Uint8List>? _imageBytesFuture;
  bool _scanning = false;
  bool _saving = false;
  bool _manual = false;
  String? _ocrNote;
  String _splitMode = 'equal';
  Map<int, double> _weights = {};
  List<_SplitItem> _splitItems = [];

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    _note.dispose();
    _tax.dispose();
    _tip.dispose();
    _itemName.dispose();
    _itemPrice.dispose();
    super.dispose();
  }

  double _computedTotal() {
    final amount = double.tryParse(_total.text.trim()) ?? 0;
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    final tip = double.tryParse(_tip.text.trim()) ?? 0;
    return amount + tax + tip;
  }

  void _addSplitItem() {
    final name = _itemName.text.trim();
    final price = double.tryParse(_itemPrice.text.trim());
    if (name.isEmpty || price == null || price <= 0) {
      return _snack('Enter an item name and a price greater than 0.');
    }
    setState(() {
      _splitItems.add(_SplitItem(name: name, price: price));
      _itemName.clear();
      _itemPrice.clear();
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() {
        _pickedImage = file;
        _imageBytesFuture = file.readAsBytes();
        _scanning = true;
        _ocrNote = null;
      });
      try {
        final parsed = await SplitApi.ocrReceipt(widget.session.code, file);
        if (!mounted) return;
        setState(() {
          _receiptFilename = parsed['receipt'] as String?;
          if ((parsed['merchant'] as String?)?.isNotEmpty == true) {
            _merchant.text = parsed['merchant'] as String;
          }
          if (parsed['total'] != null) {
            _total.text = (parsed['total'] as num).toStringAsFixed(2);
          }
          final items = (parsed['items'] as List?) ?? [];
          _splitItems = items.map<_SplitItem>((it) {
            final m = it as Map;
            return _SplitItem(name: '${m['name'] ?? ''}', price: _num(m['price']));
          }).where((it) => it.name.isNotEmpty && it.price > 0).toList();
          _ocrNote = items.isEmpty
              ? 'Receipt read — check the total below and fix it if needed.'
              : 'Receipt read — found ${items.length} item${items.length == 1 ? '' : 's'}. Check the total below and fix it if needed.';
          _scanning = false;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _manual = true;
          _ocrNote = null;
        });
        _snack(e.message);
      }
    } on Exception catch (e) {
      _snack('Could not pick that photo: $e');
    }
  }

  Future<void> _save() async {
    final merchant = _merchant.text.trim();
    final amount = double.tryParse(_total.text.trim());
    if (merchant.isEmpty) return _snack('Add a merchant or description.');
    if (amount == null || amount <= 0) {
      return _snack('Enter a valid total greater than 0.');
    }
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    final tip = double.tryParse(_tip.text.trim()) ?? 0;
    if (tax < 0 || tip < 0) {
      return _snack('Tax and tip can\'t be negative.');
    }
    if (_splitMode == 'items' && _splitItems.isEmpty) {
      return _snack('Add at least one item to split by items.');
    }
    // Total sent to the server already includes tax + tip.
    final total = amount + tax + tip;
    Map<String, dynamic>? splitData;
    if (_splitMode == 'shares') {
      splitData = {
        'weights': {
          for (final e in _weights.entries) e.key.toString(): e.value
        }
      };
    } else if (_splitMode == 'items') {
      splitData = {
        'items': _splitItems
            .map((it) => {
                  'name': it.name,
                  'price': it.price,
                  'members': it.assigned.toList(),
                })
            .toList()
      };
    }
    setState(() => _saving = true);
    try {
      await SplitApi.addExpense(
        widget.session.code,
        memberId: widget.session.memberId,
        merchant: merchant,
        total: total.toStringAsFixed(2),
        note: _note.text.trim(),
        receipt: _receiptFilename,
        date: _date.toIso8601String().substring(0, 10),
        splitMode: _splitMode,
        splitData: splitData,
        tax: tax,
        tip: tip,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showForm = _manual || _pickedImage != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Add expense',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (!_manual) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _scanning ? null : () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_rounded),
                              label: const Text('Take photo'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _scanning ? null : () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const Text('From gallery'),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => setState(() => _manual = true),
                        child: const Text('Or enter it manually instead'),
                      ),
                    ],
                    if (_scanning)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Reading your receipt…'),
                          ],
                        ),
                      ),
                    if (_pickedImage != null && !_scanning)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FutureBuilder<Uint8List>(
                            future: _imageBytesFuture,
                            builder: (ctx, snap) {
                              if (!snap.hasData) return const SizedBox(height: 120);
                              return Image.memory(snap.data!, height: 160, fit: BoxFit.cover);
                            },
                          ),
                        ),
                      ),
                    if (_ocrNote != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                color: Colors.amber.shade300, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_ocrNote!, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    if (showForm) ...[
                      TextField(
                        controller: _merchant,
                        decoration: const InputDecoration(
                            labelText: 'Merchant / description', hintText: 'e.g. Shake Shack'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _total,
                        decoration: const InputDecoration(
                          labelText: 'Total',
                          hintText: '0.00',
                          prefixText: '\$ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tax,
                              decoration: const InputDecoration(
                                labelText: 'Tax (optional)',
                                hintText: '0.00',
                                prefixText: '\$ ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _tip,
                              decoration: const InputDecoration(
                                labelText: 'Tip (optional)',
                                hintText: '0.00',
                                prefixText: '\$ ',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: \$${_computedTotal().toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(const Duration(days: 1)),
                                );
                                if (picked != null) setState(() => _date = picked);
                              },
                              icon: const Icon(Icons.calendar_today_rounded, size: 18),
                              label: Text(
                                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _note,
                              decoration:
                                  const InputDecoration(labelText: 'Note (optional)', hintText: 'Dinner'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('SPLIT',
                          style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.2,
                              color: context.faint)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: 'equal',
                              label: Text('Equal'),
                              icon: Icon(Icons.people_rounded)),
                          ButtonSegment(
                              value: 'shares',
                              label: Text('By shares'),
                              icon: Icon(Icons.pie_chart_rounded)),
                          ButtonSegment(
                              value: 'items',
                              label: Text('By items'),
                              icon: Icon(Icons.receipt_long_rounded)),
                        ],
                        selected: {_splitMode},
                        onSelectionChanged: (s) {
                          setState(() {
                            _splitMode = s.first;
                            if (_splitMode == 'shares' && _weights.isEmpty) {
                              _weights = {
                                for (final m in widget.members)
                                  m['id'] as int: 1.0
                              };
                            }
                          });
                        },
                      ),
                      if (_splitMode == 'shares') ...[
                        const SizedBox(height: 12),
                        ...widget.members.map<Widget>((m) {
                          final id = m['id'] as int;
                          final w = _weights[id] ?? 1.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(m['nickname'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline_rounded),
                                  tooltip: 'Lower share',
                                  onPressed: w <= 0.5
                                      ? null
                                      : () => setState(
                                          () => _weights[id] = w - 0.5),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text(_weightLabel(w),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.add_circle_outline_rounded),
                                  tooltip: 'Raise share',
                                  onPressed: () => setState(
                                      () => _weights[id] = w + 0.5),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (_splitMode == 'items') ...[
                        const SizedBox(height: 12),
                        if (_splitItems.isEmpty)
                          Text(
                            'No items yet — snap a receipt to load its items, or add one below.',
                            style: TextStyle(
                                color: context.muted, fontSize: 13),
                          ),
                        ..._splitItems.asMap().entries.map<Widget>((entry) {
                          final idx = entry.key;
                          final it = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(it.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    Text(
                                        '\$${it.price.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20),
                                      tooltip: 'Remove item',
                                      onPressed: () => setState(
                                          () => _splitItems.removeAt(idx)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children:
                                      widget.members.map<Widget>((m) {
                                    final id = m['id'] as int;
                                    final selected =
                                        it.assigned.contains(id);
                                    return ChoiceChip(
                                      label:
                                          Text(m['nickname'] as String),
                                      selected: selected,
                                      selectedColor:
                                          _brand.withValues(alpha: 0.3),
                                      onSelected: (_) => setState(() {
                                        if (selected) {
                                          it.assigned.remove(id);
                                        } else {
                                          it.assigned.add(id);
                                        }
                                      }),
                                    );
                                  }).toList(),
                                ),
                                Text(
                                  'No one picked = shared by everyone.',
                                  style: TextStyle(
                                      color: context.faint, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _itemName,
                                decoration: const InputDecoration(
                                    labelText: 'Item name'),
                                textCapitalization:
                                    TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _itemPrice,
                                decoration: const InputDecoration(
                                    labelText: 'Price', prefixText: '\$ '),
                                keyboardType: const TextInputType
                                    .numberWithOptions(decimal: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_rounded),
                              tooltip: 'Add item',
                              onPressed: _addSplitItem,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Paid by ${widget.session.nickname} • ${_splitMode == 'equal'
                            ? 'Split equally between everyone in the group.'
                            : _splitMode == 'shares'
                                ? 'Split by shares — see weights above.'
                                : 'Split by items — items with nobody picked are shared by everyone.'}',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_saving || _scanning || !showForm) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded),
                label: const Text('Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

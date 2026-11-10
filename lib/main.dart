
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

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

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  Session? _session;
  String? _joinCodePrefill;
  bool _loading = true;

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
    setState(() => _session = s);
  }

  Future<void> _leave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('split_code');
    await prefs.remove('split_member_id');
    await prefs.remove('split_nickname');
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session != null) {
      return GroupScreen(session: _session!, onLeave: _leave);
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.prefillCode != null && widget.prefillCode!.isNotEmpty) {
      _joinCode.text = widget.prefillCode!;
      _tabs.index = 1;
    }
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

// ---------- group ----------
class GroupScreen extends StatefulWidget {
  final Session session;
  final Future<void> Function() onLeave;
  const GroupScreen({super.key, required this.session, required this.onLeave});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _group;
  Map<String, dynamic>? _balances;
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
      final b = await SplitApi.getBalances(widget.session.code);
      if (!mounted) return;
      setState(() {
        _group = g;
        _balances = b;
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

  Future<void> _copyInvite() async {
    final link = '${Uri.base.origin}/?code=${widget.session.code}';
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Invite link copied — send it to your friends.');
  }

  Future<void> _openAddExpense() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => AddExpenseDialog(session: widget.session),
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
      final b = await SplitApi.getBalances(widget.session.code);
      setState(() {
        _group = g;
        _balances = b;
      });
      _snack('Expense deleted.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = (_group?['members'] as List?) ?? [];
    final expenses = (_group?['expenses'] as List?) ?? [];
    final total = _group?['total'] as String? ?? '0.00';
    final perPerson = members.isEmpty
        ? '0.00'
        : (double.parse(total) / members.length).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
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
          IconButton(
            icon: Icon(context.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            tooltip: context.isDark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            onPressed: toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.link_rounded),
            tooltip: 'Copy invite link',
            onPressed: _copyInvite,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'leave') {
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
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'leave', child: Text('Leave group')),
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
                        _expensesTab(members, expenses, total, perPerson),
                        _balancesTab(),
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

  Widget _expensesTab(List members, List expenses, String total, String perPerson) {
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
                        : '\$$perPerson each across ${members.length} ${members.length == 1 ? 'person' : 'people'}',
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

  Widget _balancesTab() {
    final balances = (_balances?['balances'] as List?) ?? [];
    final transfers = (_balances?['transfers'] as List?) ?? [];
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
                if (balances.isEmpty)
                  const Text('Nobody here yet.')
                else
                  ...balances.map<Widget>((b) {
                    final net = double.parse(b['net'] as String);
                    final isMe = b['member_id'] == widget.session.memberId;
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
                            backgroundColor: _avatarColor(b['nickname'] as String),
                            child: Text(
                              (b['nickname'] as String).isNotEmpty
                                  ? (b['nickname'] as String)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${b['nickname']}${isMe ? ' (you)' : ''}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('Paid \$${b['paid']} • Share \$${b['share']}',
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
                  ...transfers.map<Widget>((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('${t['from']}  →  ${t['to']}',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                            Text('\$${t['amount']}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      )),
                if (!allSettled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Fewest payments possible — just these transfers and everyone is even.',
                      style: TextStyle(color: context.muted, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
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
class AddExpenseDialog extends StatefulWidget {
  final Session session;
  const AddExpenseDialog({super.key, required this.session});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _merchant = TextEditingController();
  final _total = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _receiptFilename;
  XFile? _pickedImage;
  bool _scanning = false;
  bool _saving = false;
  bool _manual = false;
  String? _ocrNote;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      setState(() {
        _pickedImage = file;
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
    final total = _total.text.trim();
    if (merchant.isEmpty) return _snack('Add a merchant or description.');
    final parsedTotal = double.tryParse(total);
    if (parsedTotal == null || parsedTotal <= 0) {
      return _snack('Enter a valid total greater than 0.');
    }
    setState(() => _saving = true);
    try {
      await SplitApi.addExpense(
        widget.session.code,
        memberId: widget.session.memberId,
        merchant: merchant,
        total: parsedTotal.toStringAsFixed(2),
        note: _note.text.trim(),
        receipt: _receiptFilename,
        date: _date.toIso8601String().substring(0, 10),
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
                            future: _pickedImage!.readAsBytes(),
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
                      const SizedBox(height: 8),
                      Text(
                        'Paid by ${widget.session.nickname} • Split equally between everyone in the group.',
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

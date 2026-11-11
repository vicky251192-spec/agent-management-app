import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bcrypt/bcrypt.dart';

const secure = FlutterSecureStorage();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AgentStore.db;
  runApp(const AgentApp());
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Agent Management',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xff124b8c), useMaterial3: true),
    home: const StartPage(),
  );
}

class AgentStore {
  static Database? _database;
  static Future<Database> get db async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'agents.db');
    _database = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE agents(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          agentCode TEXT NOT NULL COLLATE NOCASE UNIQUE,
          agentName TEXT NOT NULL,
          passwordHash TEXT NOT NULL
        )
      ''');
    });
    return _database!;
  }

  static Future<List<Map<String, Object?>>> all() async =>
      (await db).query('agents', orderBy: 'agentName COLLATE NOCASE');

  static Future<void> add(String code, String name, String password) async {
    await (await db).insert('agents', {
      'agentCode': code.trim(),
      'agentName': name.trim(),
      'passwordHash': BCrypt.hashpw(password, BCrypt.gensalt()),
    });
  }

  static Future<void> update(int id, String code, String name, String? password) async {
    final values = <String, Object?>{
      'agentCode': code.trim(), 'agentName': name.trim()
    };
    if (password != null && password.isNotEmpty) {
      values['passwordHash'] = BCrypt.hashpw(password, BCrypt.gensalt());
    }
    await (await db).update('agents', values, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> delete(int id) async =>
      (await db).delete('agents', where: 'id=?', whereArgs: [id]);

  static Future<Map<String, Object?>?> login(String code, String password) async {
    final rows = await (await db).query('agents',
      where: 'agentCode=?', whereArgs: [code.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BCrypt.checkpw(password, row['passwordHash'] as String) ? row : null;
  }
}

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class StartPage extends StatelessWidget {
  const StartPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: secure.read(key: 'admin_hash'),
    builder: (context, snap) {
      if (!snap.hasData && snap.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snap.data == null ? const SetupPage() : const HomePage();
    },
  );
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}
class _SetupPageState extends State<SetupPage> {
  final a = TextEditingController(), b = TextEditingController();
  Future<void> save() async {
    if (a.text.length < 8 || a.text != b.text) {
      message(context, 'Passwords must match and contain at least 8 characters.');
      return;
    }
    await secure.write(key: 'admin_hash', value: BCrypt.hashpw(a.text, BCrypt.gensalt()));
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
  }
  @override
  void dispose() { a.dispose(); b.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administrator setup')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.admin_panel_settings, size: 64),
        const Text('Create administrator password'),
        const SizedBox(height: 16),
        TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)')),
        const SizedBox(height: 12),
        TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: save, child: const Text('Save admin password'))),
      ],
    )),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent Management')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.badge, size: 72),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentLoginPage())),
          child: const Text('Agent Login'))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginPage())),
          child: const Text('Administrator Login'))),
      ],
    ))),
  );
}

class AgentLoginPage extends StatefulWidget {
  const AgentLoginPage({super.key});
  @override
  State<AgentLoginPage> createState() => _AgentLoginPageState();
}
class _AgentLoginPageState extends State<AgentLoginPage> {
  final code = TextEditingController(), pass = TextEditingController();
  bool busy = false, hide = true;
  Future<void> login() async {
    if (code.text.trim().isEmpty || pass.text.isEmpty) { message(context, 'Enter agent code and password.'); return; }
    setState(() => busy = true);
    try {
      final agent = await AgentStore.login(code.text, pass.text);
      if (!mounted) return;
      if (agent == null) { message(context, 'Incorrect agent code or password.'); }
      else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AgentPage(agent: agent)));
      }
    } catch (_) { if (mounted) message(context, 'Login failed.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { code.dispose(); pass.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent Login')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Agent code')),
        const SizedBox(height: 12),
        TextField(controller: pass, obscureText: hide, decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => hide = !hide)))),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: busy ? null : login, child: Text(busy ? 'Checking...' : 'LOGIN'))),
      ],
    )),
  );
}

class AgentPage extends StatelessWidget {
  final Map<String, Object?> agent;
  const AgentPage({super.key, required this.agent});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent dashboard'), actions: [
      IconButton(icon: const Icon(Icons.logout), onPressed: () =>
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomePage()), (_) => false))
    ]),
    body: Center(child: Card(margin: const EdgeInsets.all(24), child: Padding(
      padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.account_circle, size: 70),
        const Text('Login successful', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ListTile(title: const Text('Agent name'), subtitle: Text(agent['agentName'] as String)),
        ListTile(title: const Text('Agent code'), subtitle: Text(agent['agentCode'] as String)),
      ],
    )))),
  );
}

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});
  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}
class _AdminLoginPageState extends State<AdminLoginPage> {
  final pass = TextEditingController();
  Future<void> login() async {
    final hash = await secure.read(key: 'admin_hash');
    final valid = hash != null && BCrypt.checkpw(pass.text, hash);
    if (!mounted) return;
    if (valid) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPage()));
    } else { message(context, 'Incorrect administrator password.'); }
  }
  @override
  void dispose() { pass.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administrator login')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Admin password')),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: login, child: const Text('ADMIN LOGIN'))),
      ],
    )),
  );
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}
class _AdminPageState extends State<AdminPage> {
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() { super.initState(); refresh(); }
  void refresh() { future = AgentStore.all(); }
  Future<void> form([Map<String, Object?>? agent]) async {
    final saved = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => AgentFormPage(agent: agent)));
    if (saved == true && mounted) setState(refresh);
  }
  Future<void> remove(Map<String, Object?> agent) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete agent?'),
      content: Text('Delete ${agent['agentName']} (${agent['agentCode']})?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (yes == true) { await AgentStore.delete(agent['id'] as int); if (mounted) setState(refresh); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin dashboard'), actions: [
      IconButton(icon: const Icon(Icons.logout), onPressed: () =>
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomePage()), (_) => false))
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => form(),
      icon: const Icon(Icons.person_add), label: const Text('Add agent')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return const Center(child: Text('Could not load agents.'));
        final agents = snap.data ?? [];
        if (agents.isEmpty) return const Center(child: Text('No agents yet. Tap Add agent.'));
        return ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: agents.length,
          itemBuilder: (context, i) {
            final a = agents[i];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(a['agentName'] as String),
              subtitle: Text('Agent code: ${a['agentCode']}'),
              onTap: () => form(a),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(a)),
            );
          });
      },
    ),
  );
}

class AgentFormPage extends StatefulWidget {
  final Map<String, Object?>? agent;
  const AgentFormPage({super.key, this.agent});
  @override
  State<AgentFormPage> createState() => _AgentFormPageState();
}
class _AgentFormPageState extends State<AgentFormPage> {
  final code = TextEditingController(), name = TextEditingController(), pass = TextEditingController();
  bool busy = false;
  bool get editing => widget.agent != null;
  @override
  void initState() {
    super.initState();
    if (editing) {
      code.text = widget.agent!['agentCode'] as String;
      name.text = widget.agent!['agentName'] as String;
    }
  }
  Future<void> save() async {
    final c = code.text.trim(), n = name.text.trim(), pw = pass.text;
    if (c.isEmpty || n.isEmpty) { message(context, 'Agent code and name are required.'); return; }
    if ((!editing && pw.length < 8) || (editing && pw.isNotEmpty && pw.length < 8)) {
      message(context, 'Password must be at least 8 characters.'); return;
    }
    setState(() => busy = true);
    try {
      if (editing) {
        await AgentStore.update(widget.agent!['id'] as int, c, n, pw.isEmpty ? null : pw);
      } else {
        await AgentStore.add(c, n, pw);
      }
      if (mounted) Navigator.pop(context, true);
    } on DatabaseException catch (e) {
      if (mounted) message(context, e.isUniqueConstraintError() ? 'Agent code already exists.' : 'Database error.');
    } catch (_) {
      if (mounted) message(context, 'Could not save agent.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { code.dispose(); name.dispose(); pass.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(editing ? 'Edit agent' : 'Add agent')),
    body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
      TextField(controller: code, inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\\s'))],
        decoration: const InputDecoration(labelText: 'Agent code')),
      const SizedBox(height: 12),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Agent name')),
      const SizedBox(height: 12),
      TextField(controller: pass, obscureText: true, decoration: InputDecoration(
        labelText: editing ? 'New password (leave blank to keep current)' : 'Password (8+ characters)')),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: busy ? null : save, child: Text(busy ? 'Saving...' : 'Save agent'))),
    ])),
  );
}

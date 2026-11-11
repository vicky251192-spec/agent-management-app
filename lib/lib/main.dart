import os, textwrap, zipfile

root = "/mnt/data/agent_management_v2"
os.makedirs(root + "/lib", exist_ok=True)
os.makedirs(root + "/.github/workflows", exist_ok=True)

main_dart = r'''
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:image_picker/image_picker.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

const secure = FlutterSecureStorage();
const blue = Color(0xff124b8c);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.db;
  runApp(const AgentApp());
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Agent Management 2.0',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: blue, useMaterial3: true),
    home: const StartPage(),
  );
}

class Store {
  static Database? _db;
  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'agents.db');
    _db = await openDatabase(path, version: 2,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE agents(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          agentCode TEXT NOT NULL COLLATE NOCASE UNIQUE,
          agentName TEXT NOT NULL,
          passwordHash TEXT NOT NULL,
          fatherName TEXT DEFAULT '',
          dob TEXT DEFAULT '',
          gender TEXT DEFAULT '',
          mobile TEXT DEFAULT '',
          whatsapp TEXT DEFAULT '',
          email TEXT DEFAULT '',
          address TEXT DEFAULT '',
          city TEXT DEFAULT '',
          district TEXT DEFAULT '',
          state TEXT DEFAULT '',
          branch TEXT DEFAULT '',
          manager TEXT DEFAULT '',
          joiningDate TEXT DEFAULT '',
          category TEXT DEFAULT '',
          advisorCode TEXT DEFAULT '',
          fspStatus TEXT DEFAULT '',
          activeStatus TEXT DEFAULT 'Active',
          photoPath TEXT DEFAULT ''
        )''');
        await db.execute('''CREATE TABLE daily_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          agentId INTEGER NOT NULL,
          entryDate TEXT NOT NULL,
          business REAL NOT NULL DEFAULT 0,
          activisation INTEGER NOT NULL DEFAULT 0,
          fsp INTEGER NOT NULL DEFAULT 0,
          abl INTEGER NOT NULL DEFAULT 0,
          lwm INTEGER NOT NULL DEFAULT 0,
          customerOtp INTEGER NOT NULL DEFAULT 0,
          fspOtp INTEGER NOT NULL DEFAULT 0,
          advisorQr INTEGER NOT NULL DEFAULT 0,
          note TEXT DEFAULT '',
          createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(agentId) REFERENCES agents(id) ON DELETE CASCADE
        )''');
        await db.execute('CREATE INDEX idx_entries_agent_date ON daily_entries(agentId, entryDate)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          final columns = <String, String>{
            'fatherName': "TEXT DEFAULT ''", 'dob': "TEXT DEFAULT ''",
            'gender': "TEXT DEFAULT ''", 'mobile': "TEXT DEFAULT ''",
            'whatsapp': "TEXT DEFAULT ''", 'email': "TEXT DEFAULT ''",
            'address': "TEXT DEFAULT ''", 'city': "TEXT DEFAULT ''",
            'district': "TEXT DEFAULT ''", 'state': "TEXT DEFAULT ''",
            'branch': "TEXT DEFAULT ''", 'manager': "TEXT DEFAULT ''",
            'joiningDate': "TEXT DEFAULT ''", 'category': "TEXT DEFAULT ''",
            'advisorCode': "TEXT DEFAULT ''", 'fspStatus': "TEXT DEFAULT ''",
            'activeStatus': "TEXT DEFAULT 'Active'", 'photoPath': "TEXT DEFAULT ''"
          };
          for (final e in columns.entries) {
            await db.execute('ALTER TABLE agents ADD COLUMN ${e.key} ${e.value}');
          }
          await db.execute('''CREATE TABLE daily_entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT, agentId INTEGER NOT NULL,
            entryDate TEXT NOT NULL, business REAL NOT NULL DEFAULT 0,
            activisation INTEGER NOT NULL DEFAULT 0, fsp INTEGER NOT NULL DEFAULT 0,
            abl INTEGER NOT NULL DEFAULT 0, lwm INTEGER NOT NULL DEFAULT 0,
            customerOtp INTEGER NOT NULL DEFAULT 0, fspOtp INTEGER NOT NULL DEFAULT 0,
            advisorQr INTEGER NOT NULL DEFAULT 0, note TEXT DEFAULT '',
            createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(agentId) REFERENCES agents(id) ON DELETE CASCADE
          )''');
          await db.execute('CREATE INDEX idx_entries_agent_date ON daily_entries(agentId, entryDate)');
        }
      });
    return _db!;
  }

  static Future<List<Map<String, Object?>>> agents({String search = ''}) async {
    final d = await db;
    if (search.trim().isEmpty) return d.query('agents', orderBy: 'agentName COLLATE NOCASE');
    return d.query('agents', where: 'agentCode LIKE ? OR agentName LIKE ? OR mobile LIKE ?',
      whereArgs: ['%$search%', '%$search%', '%$search%'], orderBy: 'agentName COLLATE NOCASE');
  }

  static Future<Map<String, Object?>?> login(String code, String password) async {
    final rows = await (await db).query('agents', where: 'agentCode=?', whereArgs: [code.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BCrypt.checkpw(password, row['passwordHash'] as String) ? row : null;
  }

  static Future<void> saveAgent(Map<String, Object?> values, {int? id, String? password}) async {
    final d = await db;
    final data = Map<String, Object?>.from(values);
    if (password != null && password.isNotEmpty) data['passwordHash'] = BCrypt.hashpw(password, BCrypt.gensalt());
    if (id == null) {
      if (password == null || password.length < 8) throw Exception('Password must be at least 8 characters.');
      await d.insert('agents', data);
    } else {
      await d.update('agents', data, where: 'id=?', whereArgs: [id]);
    }
  }

  static Future<void> deleteAgent(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('daily_entries', where: 'agentId=?', whereArgs: [id]);
      await txn.delete('agents', where: 'id=?', whereArgs: [id]);
    });
  }

  static Future<void> addEntry(Map<String, Object?> values) async => (await db).insert('daily_entries', values);
  static Future<List<Map<String, Object?>>> entries(int agentId, String month) async =>
    (await db).query('daily_entries', where: 'agentId=? AND entryDate LIKE ?', whereArgs: [agentId, '$month%'], orderBy: 'entryDate DESC, id DESC');

  static Future<Map<String, num>> totals({int? agentId, required String month}) async {
    final d = await db;
    final where = agentId == null ? 'entryDate LIKE ?' : 'agentId=? AND entryDate LIKE ?';
    final args = agentId == null ? ['$month%'] : [agentId, '$month%'];
    final rows = await d.rawQuery('''SELECT
      COALESCE(SUM(business),0) business, COALESCE(SUM(activisation),0) activisation,
      COALESCE(SUM(fsp),0) fsp, COALESCE(SUM(abl),0) abl, COALESCE(SUM(lwm),0) lwm,
      COALESCE(SUM(customerOtp),0) customerOtp, COALESCE(SUM(fspOtp),0) fspOtp,
      COALESCE(SUM(advisorQr),0) advisorQr FROM daily_entries WHERE $where''', args);
    return rows.first.map((k,v) => MapEntry(k, (v as num)));
  }

  static Future<String> exportExcel(String month) async {
    final d = await db;
    final rows = await d.rawQuery('''SELECT a.agentCode, a.agentName, e.* FROM daily_entries e
      JOIN agents a ON a.id=e.agentId WHERE e.entryDate LIKE ? ORDER BY a.agentName, e.entryDate''', ['$month%']);
    final book = Excel.createExcel();
    final sheet = book['Daily Report'];
    final headers = ['Agent Code','Agent Name','Date','Business','Activisation','FSP','ABL','LWM Login','Customer OTP','FSP OTP','Advisor QR','Note'];
    sheet.appendRow(headers.map((x) => TextCellValue(x)).toList());
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue('${r['agentCode']}'), TextCellValue('${r['agentName']}'),
        TextCellValue('${r['entryDate']}'), DoubleCellValue((r['business'] as num).toDouble()),
        IntCellValue((r['activisation'] as num).toInt()), IntCellValue((r['fsp'] as num).toInt()),
        IntCellValue((r['abl'] as num).toInt()), IntCellValue((r['lwm'] as num).toInt()),
        IntCellValue((r['customerOtp'] as num).toInt()), IntCellValue((r['fspOtp'] as num).toInt()),
        IntCellValue((r['advisorQr'] as num).toInt()), TextCellValue('${r['note'] ?? ''}')
      ]);
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'Agent_Report_$month.xlsx'));
    await file.writeAsBytes(book.encode()!);
    return file.path;
  }

  static Future<String> backup() async {
    final d = await db;
    final a = await d.query('agents');
    final e = await d.query('daily_entries');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'agent_backup_${DateTime.now().millisecondsSinceEpoch}.json'));
    await file.writeAsString(jsonEncode({'version':2,'agents':a,'entries':e}));
    return file.path;
  }

  static Future<void> restore(String path) async {
    final obj = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    if (obj['version'] != 2 || obj['agents'] is! List || obj['entries'] is! List) {
      throw Exception('Invalid backup file.');
    }
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('daily_entries');
      await txn.delete('agents');
      for (final row in obj['agents']) {
        final m = Map<String, Object?>.from(row as Map);
        m.remove('id');
        await txn.insert('agents', m);
      }
      for (final row in obj['entries']) {
        final m = Map<String, Object?>.from(row as Map);
        m.remove('id');
        await txn.insert('daily_entries', m);
      }
    });
  }
}

void toast(BuildContext c, String s) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));
String monthNow() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2,'0')}';
}
String today() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
}
Future<void> shareFile(String path, String text) async {
  await Share.shareXFiles([XFile(path)], text: text);
}

class StartPage extends StatelessWidget {
  const StartPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: secure.read(key: 'admin_hash'),
    builder: (c,s) {
      if (s.connectionState != ConnectionState.done) return const Scaffold(body: Center(child:CircularProgressIndicator()));
      return s.data == null ? const AdminSetupPage() : const HomePage();
    });
}

class AdminSetupPage extends StatefulWidget {
  const AdminSetupPage({super.key});
  @override State<AdminSetupPage> createState()=>_AdminSetupPageState();
}
class _AdminSetupPageState extends State<AdminSetupPage> {
  final a=TextEditingController(), b=TextEditingController();
  Future<void> save() async {
    if(a.text.length<8 || a.text!=b.text){toast(context,'Passwords must match and be at least 8 characters.');return;}
    await secure.write(key:'admin_hash',value:BCrypt.hashpw(a.text,BCrypt.gensalt()));
    if(mounted) Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const HomePage()));
  }
  @override void dispose(){a.dispose();b.dispose();super.dispose();}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Administrator Setup')),body:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    const Icon(Icons.admin_panel_settings,size:64),const Text('Create Admin Password'),
    TextField(controller:a,obscureText:true,decoration:const InputDecoration(labelText:'Password (8+ characters)')),
    TextField(controller:b,obscureText:true,decoration:const InputDecoration(labelText:'Confirm password')),
    const SizedBox(height:18),FilledButton(onPressed:save,child:const Text('Save Password'))
  ])));
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Agent Management 2.0')),body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    const Icon(Icons.groups,size:76,color:blue),const Text('Offline Agent Management',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const SizedBox(height:24),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const AgentLoginPage())),child:const Text('AGENT LOGIN'))),
    const SizedBox(height:12),SizedBox(width:double.infinity,child:OutlinedButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const AdminLoginPage())),child:const Text('ADMIN LOGIN')))
  ]))));
}

class AdminLoginPage extends StatefulWidget {const AdminLoginPage({super.key});@override State<AdminLoginPage> createState()=>_AdminLoginPageState();}
class _AdminLoginPageState extends State<AdminLoginPage>{
 final pass=TextEditingController();
 Future<void> login()async{final h=await secure.read(key:'admin_hash');if(!mounted)return;if(h!=null&&BCrypt.checkpw(pass.text,h)){Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>const AdminPage()));}else{toast(context,'Incorrect admin password.');}}
 @override void dispose(){pass.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Admin Login')),body:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Admin password')),const SizedBox(height:16),FilledButton(onPressed:login,child:const Text('LOGIN'))])));
}

class AgentLoginPage extends StatefulWidget {const AgentLoginPage({super.key});@override State<AgentLoginPage> createState()=>_AgentLoginPageState();}
class _AgentLoginPageState extends State<AgentLoginPage>{
 final code=TextEditingController(),pass=TextEditingController();bool busy=false;
 Future<void> login()async{setState(()=>busy=true);try{final a=await Store.login(code.text,pass.text);if(!mounted)return;if(a==null){toast(context,'Wrong agent code or password.');}else{Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>AgentDashboard(agent:a)));}}catch(e){if(mounted)toast(context,'Login failed: $e');}finally{if(mounted)setState(()=>busy=false);}}
 @override void dispose(){code.dispose();pass.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Agent Login')),body:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[TextField(controller:code,decoration:const InputDecoration(labelText:'Agent Code')),TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Password')),const SizedBox(height:18),FilledButton(onPressed:busy?null:login,child:Text(busy?'Please wait...':'LOGIN'))])));
}

class AdminPage extends StatefulWidget {const AdminPage({super.key});@override State<AdminPage> createState()=>_AdminPageState();}
class _AdminPageState extends State<AdminPage>{
 final search=TextEditingController();late Future<List<Map<String,Object?>>> future;
 @override void initState(){super.initState();future=Store.agents();}
 void reload()=>setState(()=>future=Store.agents(search:search.text));
 Future<void> addEdit([Map<String,Object?>? a])async{final ok=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>AgentForm(agent:a)));if(ok==true)reload();}
 Future<void> backup()async{try{final f=await Store.backup();await shareFile(f,'Agent Management backup. Keep this file safely.');}catch(e){toast(context,'Backup failed: $e');}}
 Future<void> restore()async{try{final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);if(r==null)return;final yes=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(title:const Text('Restore backup?'),content:const Text('Restore replaces current agent and entry records. Make a backup first.'),actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Restore'))]));if(yes==true){await Store.restore(r.files.single.path!);reload();toast(context,'Backup restored.');}}catch(e){toast(context,'Restore failed: $e');}}
 Future<void> export()async{try{final f=await Store.exportExcel(monthNow());await shareFile(f,'Monthly agent report ${monthNow()}');}catch(e){toast(context,'Export failed: $e');}}
 @override void dispose(){search.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Admin Dashboard'),actions:[PopupMenuButton<String>(onSelected:(v){if(v=='backup')backup();if(v=='restore')restore();if(v=='excel')export();},itemBuilder:(_)=>const [PopupMenuItem(value:'excel',child:Text('Export this month to Excel')),PopupMenuItem(value:'backup',child:Text('Backup data')),PopupMenuItem(value:'restore',child:Text('Restore backup'))]),IconButton(onPressed:()=>Navigator.pushAndRemoveUntil(c,MaterialPageRoute(builder:(_)=>const HomePage()),(_)=>false),icon:const Icon(Icons.logout))]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>addEdit(),icon:const Icon(Icons.person_add),label:const Text('Add Agent')),body:Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:TextField(controller:search,onChanged:(_)=>reload(),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search code, name or mobile',border:OutlineInputBorder()))),
    Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:future,builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final list=s.data!;if(list.isEmpty)return const Center(child:Text('No agents found. Add your first agent.'));return ListView.builder(itemCount:list.length,itemBuilder:(c,i){final a=list[i];return Card(child:ListTile(leading:a['photoPath'].toString().isNotEmpty&&File(a['photoPath'] as String).existsSync()?CircleAvatar(backgroundImage:FileImage(File(a['photoPath'] as String))):const CircleAvatar(child:Icon(Icons.person)),title:Text('${a['agentName']}'),subtitle:Text('${a['agentCode']} • ${a['activeStatus']}'),onTap:()=>addEdit(a),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='entry')await Navigator.push(c,MaterialPageRoute(builder:(_)=>DailyEntryPage(agent:a)));if(v=='report')await Navigator.push(c,MaterialPageRoute(builder:(_)=>PerformancePage(agent:a)));if(v=='delete'){final yes=await showDialog<bool>(context:c,builder:(x)=>AlertDialog(title:const Text('Delete agent?'),content:Text('Delete ${a['agentName']} and all daily entries?'),actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Delete'))]));if(yes==true){await Store.deleteAgent(a['id'] as int);reload();}}},itemBuilder:(_)=>const [PopupMenuItem(value:'entry',child:Text('Add daily entry')),PopupMenuItem(value:'report',child:Text('View monthly performance')),PopupMenuItem(value:'delete',child:Text('Delete'))])));});})),
    Padding(padding:const EdgeInsets.all(8),child:Text('Agents use this same phone. Keep the app and phone secure.',style:Theme.of(c).textTheme.bodySmall))
  ]));
}

class AgentForm extends StatefulWidget {final Map<String,Object?>? agent;const AgentForm({super.key,this.agent});@override State<AgentForm> createState(

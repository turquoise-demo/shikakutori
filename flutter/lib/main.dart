import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// ===== ユーティリティ =====
Color hexColor(String s) {
  final h = s.startsWith('0x') ? s.substring(2) : s.replaceFirst('#', '');
  return Color(int.parse(h, radix: 16));
}

String yearLabel(String y) => '令和${y.substring(1)}年度';

/// ===== モデル =====
class CatDef {
  final String key;
  final String short;
  final Color color;
  final bool applied;
  CatDef(this.key, this.short, this.color, this.applied);
  factory CatDef.fromJson(Map<String, dynamic> j) => CatDef(
        j['key'] as String,
        (j['short'] ?? j['key']) as String,
        hexColor(j['color'] as String? ?? '0xFF0F5FA6'),
        j['applied'] == true,
      );
}

class Pass {
  final int overall;
  final Map<String, int> perCatMin;
  Pass(this.overall, this.perCatMin);
  factory Pass.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Pass(60, {});
    final m = <String, int>{};
    (j['perCatMin'] as Map<String, dynamic>?)?.forEach((k, v) => m[k] = v as int);
    return Pass((j['overall'] ?? 60) as int, m);
  }
}

class Exam {
  final String id;
  final String name;
  final String short;
  final String desc;
  final Color color;
  final List<CatDef> cats;
  final Pass pass;
  Exam(this.id, this.name, this.short, this.desc, this.color, this.cats, this.pass);

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
        j['id'] as String,
        j['name'] as String,
        (j['short'] ?? j['name']) as String,
        (j['desc'] ?? '') as String,
        hexColor(j['color'] as String? ?? '0xFF0F5FA6'),
        (j['cats'] as List).map((e) => CatDef.fromJson(e as Map<String, dynamic>)).toList(),
        Pass.fromJson(j['pass'] as Map<String, dynamic>?),
      );

  Map<String, CatDef> get catMap => {for (final c in cats) c.key: c};
  Set<String> get appliedCats => cats.where((c) => c.applied).map((c) => c.key).toSet();

  String passSummary() {
    if (pass.perCatMin.isEmpty) return '合格基準 全体${pass.overall}%';
    if (pass.perCatMin.length == 1) {
      final e = pass.perCatMin.entries.first;
      final short = catMap[e.key]?.short ?? e.key;
      return '合格基準 全体${pass.overall}% / $short${e.value}%';
    }
    return '合格基準 各科目${pass.perCatMin.values.first}%';
  }
}

class Question {
  final String id;
  final String exam;
  final String cat;
  final String? year;
  final String q;
  final List<String> choices;
  final int correct;
  final String exp;
  final bool applied;

  Question({
    required this.id,
    required this.exam,
    required this.cat,
    required this.year,
    required this.q,
    required this.choices,
    required this.correct,
    required this.exp,
    required this.applied,
  });

  factory Question.fromJson(Map<String, dynamic> j, String examId, Set<String> appliedCats) => Question(
        id: j['id'] as String,
        exam: examId,
        cat: j['cat'] as String,
        year: j['year'] as String?,
        q: j['q'] as String,
        choices: (j['choices'] as List).map((e) => e as String).toList(),
        correct: j['correct'] as int,
        exp: j['exp'] as String,
        applied: appliedCats.contains(j['cat']),
      );

  bool get isApplied => applied;
}

/// ===== 進捗ストア（端末保存） =====
class Store {
  static const _kStats = 'stats';
  static const _kWrong = 'wrong';
  static const _kBest = 'mogiBestMap';

  final SharedPreferences prefs;
  Map<String, List<int>> stats = {}; // id -> [seen, correct]
  List<String> wrong = [];
  Map<String, int> mogiBest = {}; // examId -> pct

  Store(this.prefs) {
    final s = prefs.getString(_kStats);
    if (s != null) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      stats = m.map((k, v) => MapEntry(k, (v as List).map((e) => e as int).toList()));
    }
    wrong = prefs.getStringList(_kWrong) ?? [];
    final b = prefs.getString(_kBest);
    if (b != null) {
      mogiBest = (jsonDecode(b) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    }
  }

  Future<void> _save() async {
    await prefs.setString(_kStats, jsonEncode(stats));
    await prefs.setStringList(_kWrong, wrong);
    await prefs.setString(_kBest, jsonEncode(mogiBest));
  }

  void record(Question q, bool ok) {
    final s = stats[q.id] ?? [0, 0];
    s[0] += 1;
    if (ok) s[1] += 1;
    stats[q.id] = s;
    if (ok) {
      wrong.remove(q.id);
    } else if (!wrong.contains(q.id)) {
      wrong.add(q.id);
    }
    _save();
  }

  void setBest(String examId, int pct) {
    if (pct > (mogiBest[examId] ?? 0)) {
      mogiBest[examId] = pct;
      _save();
    }
  }

  int seen(String id) => stats[id]?[0] ?? 0;
}

/// ===== グローバル =====
late List<Exam> gExams;
late Map<String, List<Question>> gByExam;
late Store gStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final examsRaw = await rootBundle.loadString('assets/exams.json');
  gExams = ((jsonDecode(examsRaw) as Map<String, dynamic>)['exams'] as List)
      .map((e) => Exam.fromJson(e as Map<String, dynamic>))
      .toList();

  final qRaw = await rootBundle.loadString('assets/questions.json');
  final qMap = jsonDecode(qRaw) as Map<String, dynamic>;
  gByExam = {};
  for (final ex in gExams) {
    final list = (qMap[ex.id] as List?) ?? [];
    gByExam[ex.id] =
        list.map((e) => Question.fromJson(e as Map<String, dynamic>, ex.id, ex.appliedCats)).toList();
  }

  final prefs = await SharedPreferences.getInstance();
  gStore = Store(prefs);
  runApp(const QuizApp());
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0F5FA6), brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          b == Brightness.dark ? const Color(0xFF0C141C) : const Color(0xFFEEF1F4),
      fontFamily: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'しかくとり',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const ExamSelectScreen(),
    );
  }
}

/// ===== セッション定義 =====
class SessionSpec {
  final String title;
  final bool isMogi;
  final List<Question> Function() build;
  SessionSpec(this.title, this.isMogi, this.build);
}

List<Question> _shuffled(Iterable<Question> src) {
  final l = src.toList()..shuffle();
  return l;
}

/// ===== 試験選択（トップ） =====
class ExamSelectScreen extends StatefulWidget {
  const ExamSelectScreen({super.key});
  @override
  State<ExamSelectScreen> createState() => _ExamSelectScreenState();
}

class _ExamSelectScreenState extends State<ExamSelectScreen> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _hero(cs),
            const SizedBox(height: 20),
            Text('試験を選ぶ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline)),
            const SizedBox(height: 10),
            ...gExams.map((ex) {
              final pool = gByExam[ex.id] ?? [];
              final done = pool.where((q) => gStore.seen(q.id) > 0).length;
              return _examCard(ex, pool.length, done);
            }),
            const SizedBox(height: 18),
            Text(
              '※ 全問オリジナル作問です（実際の過去問文は転載していません）。'
              '法規は改正で正答が変わることがあるため、受験前に公式・最新情報をご確認ください。',
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2A7DC4), Color(0xFF0B3F74)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 118, height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.13),
                ),
              ),
              Image.asset('assets/mascot/shikakutori-badge.png', width: 118),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bubble('正解はサッと次へ！\nまちがいだけ復習'),
                const SizedBox(height: 10),
                const Text('しかくとり',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('「資格（しかく）を取る」×「四角い鳥」',
                    style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 12, height: 1.4)),
                const SizedBox(height: 2),
                Text('できた問題はやらなくてOK。ニガテだけくり返す。',
                    style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(text,
          style: const TextStyle(color: Color(0xFF0B3F74), fontSize: 13, fontWeight: FontWeight.w800, height: 1.3)),
    );
  }

  Widget _examCard(Exam ex, int total, int done) {
    final cs = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0 : (done / total * 100).round();
    final ready = total > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: ready
              ? () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => HomeScreen(exam: ex)));
                  if (mounted) setState(() {});
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: ex.color, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(ex.short.characters.take(2).toString(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(ready ? '$total問 ・ 学習 $done/$total（$pct%）' : '準備中',
                          style: TextStyle(fontSize: 11.5, color: cs.outline)),
                    ],
                  ),
                ),
                Icon(ready ? Icons.chevron_right : Icons.lock_outline, color: cs.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== ホーム（試験別） =====
class HomeScreen extends StatefulWidget {
  final Exam exam;
  const HomeScreen({super.key, required this.exam});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Exam get exam => widget.exam;
  List<Question> get pool => gByExam[exam.id] ?? [];

  List<String> get years {
    final ys = pool.map((q) => q.year).whereType<String>().toSet().toList();
    ys.sort((a, b) => b.compareTo(a));
    return ys;
  }

  Future<void> _start(SessionSpec spec) async {
    final list = spec.build();
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この条件の問題がありません。')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => QuizScreen(exam: exam, spec: spec, questions: list)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wrongInExam = pool.where((q) => gStore.wrong.contains(q.id)).length;
    final seenList = pool.where((q) => gStore.seen(q.id) > 0);
    final totalSeen = pool.fold<int>(0, (a, q) => a + gStore.seen(q.id));
    final totalCorrect = pool.fold<int>(0, (a, q) => a + (gStore.stats[q.id]?[1] ?? 0));
    final acc = totalSeen > 0 ? '${(totalCorrect / totalSeen * 100).round()}%' : '—';
    final mogiN = pool.length >= 60 ? 60 : pool.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        title: Text(exam.short, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [exam.color, Color.lerp(exam.color, Colors.black, 0.35)!],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${exam.name} 対策',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(exam.desc,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                        const SizedBox(height: 12),
                        Row(children: [
                          _heroStat(acc, '累計 正答率'),
                          const SizedBox(width: 18),
                          _heroStat('${seenList.length}', '解いた問題'),
                          const SizedBox(width: 18),
                          _heroStat('$wrongInExam', '復習リスト'),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Image.asset('assets/mascot/shikakutori-badge.png', width: 66),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _label('学習モード'),
            Row(children: [
              Expanded(child: _modeCard('🎲', 'ランダム', '全分野からシャッフル', () {
                _start(SessionSpec('ランダム', false, () => _shuffled(pool).take(10).toList()));
              })),
              const SizedBox(width: 10),
              Expanded(child: _modeCard('🔁', '弱点復習', '間違えた問題だけ', () {
                _start(SessionSpec('弱点復習', false,
                    () => _shuffled(pool.where((q) => gStore.wrong.contains(q.id)))));
              }, badge: wrongInExam == 0 ? null : '$wrongInExam')),
            ]),
            const SizedBox(height: 10),
            _mogiCard(mogiN),
            if (years.isNotEmpty) ...[
              const SizedBox(height: 20),
              _label('年度別に解く'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                mainAxisSpacing: 9, crossAxisSpacing: 9,
                children: years.map((y) {
                  final qs = pool.where((q) => q.year == y).toList();
                  final done = qs.where((q) => gStore.seen(q.id) > 0).length;
                  return _yearChip(yearLabel(y), done, qs.length, () {
                    _start(SessionSpec(yearLabel(y), false, () => _shuffled(qs)));
                  });
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),
            _label('分野別に解く'),
            ...exam.cats.map((c) {
              final qs = pool.where((q) => q.cat == c.key).toList();
              final done = qs.where((q) => gStore.seen(q.id) > 0).length;
              final pct = qs.isEmpty ? 0 : (done / qs.length * 100).round();
              return _catRow(c, qs.length, done, pct, () {
                _start(SessionSpec(c.short, false, () => _shuffled(qs)));
              });
            }),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String v, String l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.outline)),
      );

  Widget _card({required Widget child, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _modeCard(String ico, String t, String d, VoidCallback onTap, {String? badge}) {
    return _card(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(ico, style: const TextStyle(fontSize: 20)),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFD23B3B), borderRadius: BorderRadius.circular(20)),
                  child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text(d, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }

  Widget _mogiCard(int n) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: exam.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _start(SessionSpec('模試', true, () => _shuffled(pool).take(n).toList())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('📝', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('模試（本番判定・$n問）',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  Text(exam.passSummary(),
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.8)),
          ]),
        ),
      ),
    );
  }

  Widget _yearChip(String label, int done, int total, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              Text('$total問', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 6, backgroundColor: cs.surfaceContainerHighest, color: cs.primary),
            ),
            const SizedBox(height: 4),
            Text('学習 $done/$total', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _catRow(CatDef c, int total, int done, int pct, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Container(width: 6, height: 40, decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(6))),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(c.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                    if (c.applied) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFB9750F)), borderRadius: BorderRadius.circular(5)),
                        child: const Text('応用', style: TextStyle(fontSize: 9.5, color: Color(0xFFB9750F), fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                  Text('$total問 ・ 学習 $done/$total', style: TextStyle(fontSize: 11.5, color: cs.outline)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      minHeight: 6, backgroundColor: cs.surfaceContainerHighest, color: c.color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('$pct%', style: TextStyle(fontWeight: FontWeight.w800, color: cs.outline)),
          ]),
        ),
      ),
    );
  }
}

/// ===== 出題画面 =====
class QuizScreen extends StatefulWidget {
  final Exam exam;
  final SessionSpec spec;
  final List<Question> questions;
  const QuizScreen({super.key, required this.exam, required this.spec, required this.questions});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int idx = 0;
  int? selected;
  final List<_Ans> answers = [];

  Question get q => widget.questions[idx];

  void _answer(int sel) {
    if (selected != null) return;
    final ok = sel == q.correct;
    gStore.record(q, ok);
    answers.add(_Ans(q.cat, q.isApplied, ok));
    setState(() => selected = sel);
    if (ok) {
      // 正解は解説なしで自動的に次の問題へ
      final at = idx;
      Future.delayed(const Duration(milliseconds: 850), () {
        if (mounted && selected != null && idx == at) _next();
      });
    }
  }

  void _next() {
    if (idx < widget.questions.length - 1) {
      setState(() {
        idx++;
        selected = null;
      });
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(exam: widget.exam, spec: widget.spec, answers: answers),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final revealed = selected != null;
    final keys = ['A', 'B', 'C', 'D'];
    final catColor = widget.exam.catMap[q.cat]?.color ?? cs.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.spec.title}   ${idx + 1} / ${widget.questions.length}'),
        titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
        backgroundColor: cs.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (idx + (revealed ? 1 : 0)) / widget.questions.length,
            minHeight: 4, backgroundColor: cs.surfaceContainerHighest, color: cs.primary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 7, children: [
              Text('● ${q.cat}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: catColor)),
              if (q.year != null)
                Text(q.year!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.primary)),
            ]),
            const SizedBox(height: 10),
            Text(q.q, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.6)),
            const SizedBox(height: 16),
            ...List.generate(q.choices.length, (i) {
              Color? bg;
              Color border = cs.outlineVariant;
              if (revealed) {
                if (i == q.correct) {
                  bg = const Color(0xFF1F9D5A).withOpacity(0.15);
                  border = const Color(0xFF1F9D5A);
                } else if (i == selected) {
                  bg = const Color(0xFFD23B3B).withOpacity(0.15);
                  border = const Color(0xFFD23B3B);
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: bg ?? cs.surface,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: revealed ? null : () => _answer(i),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: border, width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: revealed && i == q.correct
                                  ? const Color(0xFF1F9D5A)
                                  : (revealed && i == selected ? const Color(0xFFD23B3B) : cs.surfaceContainerHighest),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(keys[i], style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13,
                                color: (revealed && (i == q.correct || i == selected)) ? Colors.white : cs.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 11),
                          Expanded(child: Text(q.choices[i], style: const TextStyle(fontSize: 14.5, height: 1.5))),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            // 正解: 解説なし・短い演出で自動的に次へ
            if (revealed && selected == q.correct) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Image.asset('assets/mascot/shikakutori-correct.png', width: 84),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('せいかい！ 次の問題へ…',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1F9D5A))),
                  ),
                ],
              ),
            ],
            // 不正解: ここでしっかり解説＋正解を確認
            if (revealed && selected != q.correct) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD23B3B).withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD23B3B),
                          borderRadius: BorderRadius.circular(20)),
                        child: const Text('不正解',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 9),
                      Text('正解は ${keys[q.correct]}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD23B3B))),
                    ]),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/mascot/shikakutori-wrong.png', width: 96),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('解説', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.outline)),
                              const SizedBox(height: 3),
                              Text(q.exp, style: const TextStyle(fontSize: 13.5, height: 1.7)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
                  child: Text(idx == widget.questions.length - 1 ? '結果を見る' : '次の問題',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ans {
  final String cat;
  final bool applied;
  final bool ok;
  _Ans(this.cat, this.applied, this.ok);
}

/// ===== 結果画面 =====
class ResultScreen extends StatelessWidget {
  final Exam exam;
  final SessionSpec spec;
  final List<_Ans> answers;
  const ResultScreen({super.key, required this.exam, required this.spec, required this.answers});

  int _pctFor(bool Function(_Ans) f) {
    final l = answers.where(f).toList();
    if (l.isEmpty) return 0;
    return (l.where((a) => a.ok).length / l.length * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = answers.length;
    final correct = answers.where((a) => a.ok).length;
    final pct = total == 0 ? 0 : (correct / total * 100).round();

    final passOverall = pct >= exam.pass.overall;
    // 区分別の最低ライン
    final critFails = <bool>[];
    exam.pass.perCatMin.forEach((cat, min) {
      final present = answers.where((a) => a.cat == cat).isNotEmpty;
      if (present) critFails.add(_pctFor((a) => a.cat == cat) >= min);
    });
    final pass = passOverall && !critFails.contains(false);

    if (spec.isMogi) gStore.setBest(exam.id, pct);

    final ringColor = pct >= 80 ? const Color(0xFF1F9D5A) : (pct >= exam.pass.overall ? cs.primary : const Color(0xFFD23B3B));

    return Scaffold(
      appBar: AppBar(backgroundColor: cs.surface, title: Text(spec.isMogi ? '模試 結果' : '結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.surface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant)),
              child: Column(
                children: [
                  SizedBox(
                    width: 140, height: 140,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 140, height: 140,
                        child: CircularProgressIndicator(
                          value: pct / 100, strokeWidth: 12,
                          backgroundColor: cs.surfaceContainerHighest, color: ringColor,
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$pct%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                        Text('正答率', style: TextStyle(fontSize: 11, color: cs.outline)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Text('$total問中 $correct問正解', style: TextStyle(color: cs.outline)),
                  if (spec.isMogi) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: (pass ? const Color(0xFF1F9D5A) : const Color(0xFFD23B3B)).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: pass ? const Color(0xFF1F9D5A) : const Color(0xFFD23B3B)),
                      ),
                      child: Text(pass ? '✔ 合格ライン' : '✕ 合格基準に未達',
                          style: TextStyle(fontWeight: FontWeight.w800,
                              color: pass ? const Color(0xFF1F9D5A) : const Color(0xFFD23B3B))),
                    ),
                    const SizedBox(height: 14),
                    _crit(context, '全体の正答率', '合格基準 ${exam.pass.overall}% 以上', pct, exam.pass.overall, passOverall, null, cs),
                    ...exam.pass.perCatMin.entries.where((e) => answers.any((a) => a.cat == e.key)).map((e) {
                      final cp = _pctFor((a) => a.cat == e.key);
                      final n = answers.where((a) => a.cat == e.key).length;
                      final short = exam.catMap[e.key]?.short ?? e.key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _crit(context, short, '合格基準 ${e.value}% 以上', cp, e.value, cp >= e.value, n, cs),
                      );
                    }),
                    const SizedBox(height: 14),
                    ..._breakdown(cs),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final list = spec.build();
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => QuizScreen(exam: exam, spec: spec, questions: list)));
                },
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
                child: const Text('もう一度', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15)),
                child: const Text('ホームへ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _breakdown(ColorScheme cs) {
    final rows = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: Text('分野別 正答率', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline)),
      ),
      const SizedBox(height: 8),
    ];
    for (final c in exam.cats) {
      final ca = answers.where((a) => a.cat == c.key).toList();
      if (ca.isEmpty) continue;
      final cp = (ca.where((a) => a.ok).length / ca.length * 100).round();
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 78, child: Text(c.short, style: TextStyle(fontSize: 12.5, color: cs.outline))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: cp / 100, minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest, color: c.color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 40, child: Text('$cp%', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      ));
    }
    return rows;
  }

  Widget _crit(BuildContext context, String title, String cap, int val, int thr, bool ok, int? denom, ColorScheme cs) {
    final color = ok ? const Color(0xFF1F9D5A) : const Color(0xFFD23B3B);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('$title${denom != null ? '（$denom問）' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            Text('$val% ${ok ? '✔' : '✕'}', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 7),
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: val / 100, minHeight: 9, backgroundColor: cs.surface, color: color),
            ),
            Positioned(
              left: (thr / 100) * (MediaQuery.of(context).size.width - 32 - 26 - 26),
              child: Container(width: 2, height: 9, color: cs.onSurface.withOpacity(0.55)),
            ),
          ]),
          const SizedBox(height: 5),
          Text('$cap（縦線＝基準）', style: TextStyle(fontSize: 10.5, color: cs.outline)),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

/// ===== ブランド色 =====
const Color kBrand = Color(0xFF0F5FA6);
const Color kBrandDark = Color(0xFF0B3F74);
const Color kOk = Color(0xFF1F9D5A);
const Color kNg = Color(0xFFD23B3B);

/// 業界グループの表示順
const List<String> kGroupOrder = [
  '建設業',
  '電気・設備・エネルギー',
  '不動産業',
  'IT業界',
  '金融・保険',
  '経理・経営・士業',
  '公務員',
  '医療・福祉',
  'サービス・運輸・くらし',
  'その他',
];

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
  final String group;
  final List<CatDef> cats;
  final Pass pass;
  Exam(this.id, this.name, this.short, this.desc, this.color, this.group, this.cats, this.pass);

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
        j['id'] as String,
        j['name'] as String,
        (j['short'] ?? j['name']) as String,
        (j['desc'] ?? '') as String,
        hexColor(j['color'] as String? ?? '0xFF0F5FA6'),
        (j['group'] ?? 'その他') as String,
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
  static const _kOnboard = 'onboardDone';
  static const _kGoal = 'dailyGoal';
  static const _kDailyDate = 'dailyDate';
  static const _kDailyCount = 'dailyCount';

  final SharedPreferences prefs;
  Map<String, List<int>> stats = {}; // id -> [seen, correct]
  List<String> wrong = [];
  Map<String, int> mogiBest = {}; // examId -> pct
  bool onboardDone = false;
  int dailyGoal = 0;
  String _dailyDate = '';
  int _dailyCount = 0;

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
    onboardDone = prefs.getBool(_kOnboard) ?? false;
    dailyGoal = prefs.getInt(_kGoal) ?? 0;
    _dailyDate = prefs.getString(_kDailyDate) ?? '';
    _dailyCount = prefs.getInt(_kDailyCount) ?? 0;
  }

  Future<void> _save() async {
    await prefs.setString(_kStats, jsonEncode(stats));
    await prefs.setStringList(_kWrong, wrong);
    await prefs.setString(_kBest, jsonEncode(mogiBest));
    await prefs.setString(_kDailyDate, _dailyDate);
    await prefs.setInt(_kDailyCount, _dailyCount);
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  int get todayCount => _dailyDate == _today() ? _dailyCount : 0;

  Future<void> finishOnboarding(int goal) async {
    onboardDone = true;
    dailyGoal = goal;
    await prefs.setBool(_kOnboard, true);
    await prefs.setInt(_kGoal, goal);
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
    final t = _today();
    if (_dailyDate != t) {
      _dailyDate = t;
      _dailyCount = 0;
    }
    _dailyCount++;
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
    final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          b == Brightness.dark ? const Color(0xFF0C141C) : const Color(0xFFEDF1F6),
      splashFactory: InkSparkle.splashFactory,
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
      home: gStore.onboardDone ? const ExamSelectScreen() : const OnboardingScreen(),
    );
  }
}

/// ===== オンボーディング（初回起動） =====
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int totalSteps = 6;
  int step = 0;
  int? goal;

  bool get _canNext => step != 4 || goal != null;

  void _next() {
    HapticFeedback.lightImpact();
    if (step < totalSteps - 1) {
      setState(() => step++);
    } else {
      gStore.finishOnboarding(goal ?? 10);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ExamSelectScreen()));
    }
  }

  void _back() {
    if (step > 0) setState(() => step--);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: step > 0
                        ? IconButton(
                            onPressed: _back,
                            icon: Icon(Icons.arrow_back_rounded, color: cs.outline))
                        : null,
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: (step + 1) / totalSteps),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 10,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: kOk,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey(step),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: _stepView(cs),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canNext ? _next : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: kBrand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(step == totalSteps - 1 ? 'はじめる！' : '次へ',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String text, {double fontSize = 17}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant, width: 1.5),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.5)),
    );
  }

  Widget _tall(String bubbleText, {String mascot = 'assets/mascot/shikakutori-badge.png'}) {
    return Column(
      children: [
        const SizedBox(height: 60),
        _bubble(bubbleText),
        const SizedBox(height: 26),
        Bobbing(child: Image.asset(mascot, width: 190)),
      ],
    );
  }

  Widget _feature(IconData ico, Color c, String title, String desc) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: c.withOpacity(0.13), borderRadius: BorderRadius.circular(13)),
            child: Icon(ico, color: c, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(desc, style: TextStyle(fontSize: 12.5, color: cs.outline, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallHeader(String bubbleText) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Bobbing(amplitude: 3, child: Image.asset('assets/mascot/shikakutori-badge.png', width: 84)),
        const SizedBox(width: 10),
        Expanded(child: _bubble(bubbleText, fontSize: 15)),
      ],
    );
  }

  Widget _goalOption(int n, String label) {
    final cs = Theme.of(context).colorScheme;
    final sel = goal == n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: sel ? kBrand.withOpacity(0.1) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? kBrand : cs.outlineVariant, width: sel ? 2 : 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => goal = n);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Text('$n問 / 日',
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: sel ? kBrand : null)),
                  const Spacer(),
                  Text(label, style: TextStyle(fontSize: 13.5, color: cs.outline)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepView(ColorScheme cs) {
    switch (step) {
      case 0:
        return _tall('こんにちは！しかくとりだよ！\nきみの合格を、ぜんりょくで応援するね');
      case 1:
        return _tall('資格の勉強って、\nつづけるのがむずかしいよね…',
            mascot: 'assets/mascot/shikakutori-wrong.png');
      case 2:
        return _tall('でも大丈夫！しかくとりは\n「ムダなし勉強法」なんだ！',
            mascot: 'assets/mascot/shikakutori-correct.png');
      case 3:
        final totalQ = gByExam.values.fold<int>(0, (a, l) => a + l.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _smallHeader('しかくとりは、こんなアプリ！'),
            const SizedBox(height: 28),
            _feature(Icons.check_circle_rounded, kOk, '正解した問題は、もうやらない',
                '解けた問題は解説を出さずにサッと次へ。もう知っていることに時間を使わないから、最短で合格に近づける。'),
            _feature(Icons.replay_rounded, kNg, 'まちがいだけ、くり返す',
                'まちがえた問題はその場でしっかり解説。さらに「弱点復習」に自動でたまるから、ニガテだけを効率よくつぶせて合格率が上がる。'),
            _feature(Icons.assignment_turned_in_rounded, kBrand, '模試で本番の合否判定',
                '${gExams.length}種類の資格・${totalQ}問以上を収録。本番と同じ合格基準で、今の実力をいつでもチェックできる。'),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _smallHeader('毎日の目標はどれがいい？'),
            const SizedBox(height: 24),
            _goalOption(5, 'カジュアル'),
            _goalOption(10, 'ふつう'),
            _goalOption(20, '真剣'),
            _goalOption(30, 'マニアック'),
          ],
        );
      default:
        return _tall('まちがえた問題「だけ」を復習すれば、\n合格までの時間はグッと短くなる。\nさあ、はじめよう！',
            mascot: 'assets/mascot/shikakutori-correct.png');
    }
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

/// 共通: カード
class SoftCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? tint;
  const SoftCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.tint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: (tint ?? kBrand).withOpacity(0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// ふわふわ浮遊アニメ
class Bobbing extends StatefulWidget {
  final Widget child;
  final double amplitude;
  final Duration duration;
  const Bobbing(
      {super.key, required this.child, this.amplitude = 5, this.duration = const Duration(milliseconds: 1900)});
  @override
  State<Bobbing> createState() => _BobbingState();
}

class _BobbingState extends State<Bobbing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -widget.amplitude * Curves.easeInOut.transform(_c.value)),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// 出現アニメ（フェード＋スライド）。タイマー不使用でリスト遅延構築でも必ず表示される。
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int delayMs;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});
  @override
  Widget build(BuildContext context) {
    final total = 420 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

/// 星が弾けるエフェクト（1回再生）
class StarBurst extends StatelessWidget {
  final double size;
  final Color color;
  const StarBurst({super.key, this.size = 180, this.color = const Color(0xFFFFC93C)});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: List.generate(10, (i) {
                final ang = i * math.pi * 2 / 10 - math.pi / 2;
                final r = size / 2 * t;
                return Positioned(
                  left: size / 2 + r * math.cos(ang) - 9,
                  top: size / 2 + r * math.sin(ang) - 9,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: t * 2.5 + i,
                      child: Icon(
                        i.isEven ? Icons.star_rounded : Icons.circle,
                        size: i.isEven ? 18 + 5 * (1 - t) : 8,
                        color: i % 3 == 0 ? color : (i % 3 == 1 ? kOk : kBrand),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
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

    // グループ分け
    final byGroup = <String, List<Exam>>{};
    for (final ex in gExams) {
      (byGroup[ex.group] ??= []).add(ex);
    }
    final groups = [
      ...kGroupOrder.where(byGroup.containsKey),
      ...byGroup.keys.where((g) => !kGroupOrder.contains(g)),
    ];

    int ai = 0;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            FadeSlideIn(child: _hero()),
            const SizedBox(height: 8),
            for (final g in groups) ...[
              FadeSlideIn(delayMs: (ai * 28).clamp(0, 380), child: _sectionHeader(g, byGroup[g]!.length, cs)),
              for (final ex in byGroup[g]!)
                FadeSlideIn(delayMs: ((ai++) * 28).clamp(0, 380), child: _examCard(ex)),
            ],
            const SizedBox(height: 12),
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

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A7DC4), kBrandDark],
        ),
        boxShadow: [
          BoxShadow(color: kBrand.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.13),
                ),
              ),
              Bobbing(child: Image.asset('assets/mascot/shikakutori-badge.png', width: 112)),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('正解はサッと次へ！\nまちがいだけ復習',
                      style: TextStyle(
                          color: kBrandDark, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.35)),
                ),
                const SizedBox(height: 10),
                const Text('しかくとり',
                    style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('「資格（しかく）を取る」×「四角い鳥」',
                    style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 11.5)),
                Text('できた問題はやらなくてOK。ニガテだけくり返す。',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10.5, height: 1.4)),
                if (gStore.dailyGoal > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          gStore.todayCount >= gStore.dailyGoal
                              ? Icons.local_fire_department_rounded
                              : Icons.flag_rounded,
                          size: 14,
                          color: gStore.todayCount >= gStore.dailyGoal
                              ? const Color(0xFFFFC93C)
                              : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          gStore.todayCount >= gStore.dailyGoal
                              ? 'きょうの目標たっせい！ ${gStore.todayCount}問'
                              : 'きょう ${gStore.todayCount} / ${gStore.dailyGoal}問',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String g, int n, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: kBrand, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(g, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.outline)),
          ),
        ],
      ),
    );
  }

  Widget _examCard(Exam ex) {
    final cs = Theme.of(context).colorScheme;
    final pool = gByExam[ex.id] ?? [];
    final done = pool.where((q) => gStore.seen(q.id) > 0).length;
    final pct = pool.isEmpty ? 0.0 : done / pool.length;
    final ready = pool.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: ready ? 1 : 0.55,
        child: SoftCard(
          tint: ex.color,
          onTap: ready
              ? () async {
                  await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => HomeScreen(exam: ex)));
                  if (mounted) setState(() {});
                }
              : null,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ex.color, Color.lerp(ex.color, Colors.black, 0.28)!],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(ex.short.characters.take(2).toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ex.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(ready ? '${pool.length}問 ・ 学習 $done問' : '準備中',
                        style: TextStyle(fontSize: 11.5, color: cs.outline)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (ready)
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 4,
                          strokeCap: StrokeCap.round,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: ex.color,
                        ),
                      ),
                      Text('${(pct * 100).round()}',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.outline)),
                    ],
                  ),
                )
              else
                Icon(Icons.lock_outline, color: cs.outline, size: 20),
            ],
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
        backgroundColor: Colors.transparent,
        title: Text(exam.short, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [exam.color, Color.lerp(exam.color, Colors.black, 0.35)!],
                ),
                boxShadow: [
                  BoxShadow(color: exam.color.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 7)),
                ],
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
                  Bobbing(amplitude: 4, child: Image.asset('assets/mascot/shikakutori-badge.png', width: 64)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _label('学習モード'),
            Row(children: [
              Expanded(
                child: _modeCard(Icons.casino_rounded, kBrand, 'ランダム', '全分野からシャッフル', () {
                  _start(SessionSpec('ランダム', false, () => _shuffled(pool).take(10).toList()));
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _modeCard(Icons.replay_rounded, kNg, '弱点復習', 'まちがいだけが合格への近道', () {
                  _start(SessionSpec('弱点復習', false,
                      () => _shuffled(pool.where((q) => gStore.wrong.contains(q.id)))));
                }, badge: wrongInExam == 0 ? null : '$wrongInExam'),
              ),
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
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
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
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2, left: 2),
        child: Text(t,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.outline)),
      );

  Widget _modeCard(IconData ico, Color c, String t, String d, VoidCallback onTap, {String? badge}) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: onTap,
      tint: c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.withOpacity(0.13), borderRadius: BorderRadius.circular(11)),
              child: Icon(ico, color: c, size: 21),
            ),
            const Spacer(),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: kNg, borderRadius: BorderRadius.circular(20)),
                child: Text(badge,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 9),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(d, style: TextStyle(fontSize: 11.5, color: cs.outline)),
        ],
      ),
    );
  }

  Widget _mogiCard(int n) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: exam.color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: exam.color,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _start(SessionSpec('模試', true, () => _shuffled(pool).take(n).toList())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 13),
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
      ),
    );
  }

  Widget _yearChip(String label, int done, int total, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const Spacer(),
            Text('$total問', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: exam.color,
            ),
          ),
          const SizedBox(height: 4),
          Text('学習 $done/$total', style: TextStyle(fontSize: 11, color: cs.outline, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _catRow(CatDef c, int total, int done, int pct, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SoftCard(
        onTap: onTap,
        tint: c.color,
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Container(
              width: 6,
              height: 42,
              decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(c.key,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                  if (c.applied) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFB9750F)),
                          borderRadius: BorderRadius.circular(5)),
                      child: const Text('応用',
                          style: TextStyle(
                              fontSize: 9.5, color: Color(0xFFB9750F), fontWeight: FontWeight.w800)),
                    ),
                  ],
                ]),
                Text('$total問 ・ 学習 $done/$total', style: TextStyle(fontSize: 11.5, color: cs.outline)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: c.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('$pct%', style: TextStyle(fontWeight: FontWeight.w800, color: cs.outline)),
        ]),
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
  int streak = 0;
  final List<_Ans> answers = [];

  Question get q => widget.questions[idx];

  void _answer(int sel) {
    if (selected != null) return;
    final ok = sel == q.correct;
    gStore.record(q, ok);
    answers.add(_Ans(q.cat, q.isApplied, ok));
    streak = ok ? streak + 1 : 0;
    if (ok) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() => selected = sel);
    if (ok) {
      // 正解は解説なしで自動的に次の問題へ
      final at = idx;
      Future.delayed(const Duration(milliseconds: 900), () {
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
    final correctNow = revealed && selected == q.correct;
    final keys = ['A', 'B', 'C', 'D'];
    final catColor = widget.exam.catMap[q.cat]?.color ?? cs.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Text(widget.spec.title,
                style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${idx + 1} / ${widget.questions.length}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline)),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (idx + (revealed ? 1 : 0)) / widget.questions.length,
                minHeight: 5,
                backgroundColor: cs.surfaceContainerHighest,
                color: widget.exam.color,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: ListView(
              key: ValueKey(idx),
              padding: const EdgeInsets.all(16),
              children: [
                SoftCard(
                  tint: catColor,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 7, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(q.cat,
                              style: TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w800, color: catColor)),
                        ),
                        if (q.year != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(q.year!,
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w800, color: cs.outline)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Text(q.q,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.65)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...List.generate(q.choices.length, (i) {
                  Color bg = cs.surface;
                  Color border = cs.outlineVariant;
                  Widget? trailing;
                  if (revealed) {
                    if (i == q.correct) {
                      bg = kOk.withOpacity(0.13);
                      border = kOk;
                      trailing = const Icon(Icons.check_circle_rounded, color: kOk, size: 22);
                    } else if (i == selected) {
                      bg = kNg.withOpacity(0.12);
                      border = kNg;
                      trailing = const Icon(Icons.cancel_rounded, color: kNg, size: 22);
                    }
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border, width: 1.5),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: revealed ? null : () => _answer(i),
                          child: Padding(
                            padding: const EdgeInsets.all(13),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: revealed && i == q.correct
                                        ? kOk
                                        : (revealed && i == selected ? kNg : cs.surfaceContainerHighest),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(keys[i],
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: (revealed && (i == q.correct || i == selected))
                                              ? Colors.white
                                              : cs.onSurfaceVariant)),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                    child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(q.choices[i],
                                      style: const TextStyle(fontSize: 14.5, height: 1.5)),
                                )),
                                if (trailing != null) ...[const SizedBox(width: 6), trailing],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                // 不正解: ここでしっかり解説＋正解を確認
                if (revealed && selected != q.correct) ...[
                  const SizedBox(height: 4),
                  SoftCard(
                    tint: kNg,
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                                color: kNg, borderRadius: BorderRadius.circular(20)),
                            child: const Text('不正解',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 9),
                          Text('正解は ${keys[q.correct]}',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: kNg)),
                        ]),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Image.asset('assets/mascot/shikakutori-wrong.png', width: 92),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('解説',
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w800, color: cs.outline)),
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
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(15),
                        backgroundColor: widget.exam.color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(idx == widget.questions.length - 1 ? '結果を見る' : '次の問題',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
                const SizedBox(height: 90),
              ],
            ),
            ),
            // 正解オーバーレイ: マスコットがポンと出て自動で次へ
            if (correctNow)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: const Alignment(0, 0.55),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const StarBurst(size: 230),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.6, end: 1.0),
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.elasticOut,
                          builder: (context, v, child) => Transform.scale(scale: v, child: child),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 12, 22, 12),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: kOk.withOpacity(0.4), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: kOk.withOpacity(0.25),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset('assets/mascot/shikakutori-correct.png', width: 88),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('せいかい！',
                                        style: TextStyle(
                                            fontSize: 19, fontWeight: FontWeight.w800, color: kOk)),
                                    const Text('次の問題へ…',
                                        style: TextStyle(fontSize: 12, color: kOk)),
                                    if (streak >= 2) ...[
                                      const SizedBox(height: 6),
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0.4, end: 1.0),
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.elasticOut,
                                        builder: (context, v, child) =>
                                            Transform.scale(scale: v, child: child),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3D6),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: const Color(0xFFE8A93C)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.local_fire_department_rounded,
                                                  size: 15, color: Color(0xFFE07B12)),
                                              const SizedBox(width: 3),
                                              Text('$streak問れんぞく！',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFFB56A08))),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
    final critFails = <bool>[];
    exam.pass.perCatMin.forEach((cat, min) {
      final present = answers.where((a) => a.cat == cat).isNotEmpty;
      if (present) critFails.add(_pctFor((a) => a.cat == cat) >= min);
    });
    final pass = passOverall && !critFails.contains(false);

    if (spec.isMogi) gStore.setBest(exam.id, pct);

    final good = pct >= exam.pass.overall;
    final ringColor = pct >= 80 ? kOk : (good ? exam.color : kNg);

    return Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(spec.isMogi ? '模試 結果' : '結果',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SoftCard(
              tint: ringColor,
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FadeSlideIn(
                        delayMs: 250,
                        child: Bobbing(
                          amplitude: 4,
                          child: Image.asset(
                            good
                                ? 'assets/mascot/shikakutori-correct.png'
                                : 'assets/mascot/shikakutori-wrong.png',
                            width: 100,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 130,
                        height: 130,
                        child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                          if (good) const StarBurst(size: 210),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: pct / 100),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => SizedBox(
                              width: 130,
                              height: 130,
                              child: CircularProgressIndicator(
                                value: v,
                                strokeWidth: 12,
                                strokeCap: StrokeCap.round,
                                backgroundColor: cs.surfaceContainerHighest,
                                color: ringColor,
                              ),
                            ),
                          ),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: pct.toDouble()),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => Text('${v.round()}%',
                                  style: const TextStyle(
                                      fontSize: 30, fontWeight: FontWeight.w800)),
                            ),
                            Text('正答率', style: TextStyle(fontSize: 11, color: cs.outline)),
                          ]),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('$total問中 $correct問正解', style: TextStyle(color: cs.outline)),
                  const SizedBox(height: 4),
                  Text(
                    total - correct == 0
                        ? '全問クリア！この問題たちはもう卒業！'
                        : (good ? 'ナイス！この調子！' : 'あと少し！'),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: good ? kOk : kNg),
                  ),
                  if (total - correct > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '正解した$correct問はもうやらなくてOK。\nまちがえた${total - correct}問だけ「弱点復習」でつぶせば、合格がグッと近づく！',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.outline, height: 1.6),
                      ),
                    ),
                  if (spec.isMogi) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: (pass ? kOk : kNg).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: pass ? kOk : kNg),
                      ),
                      child: Text(pass ? '✔ 合格ライン' : '✕ 合格基準に未達',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: pass ? kOk : kNg)),
                    ),
                    const SizedBox(height: 14),
                    _crit(context, '全体の正答率', '合格基準 ${exam.pass.overall}% 以上', pct,
                        exam.pass.overall, passOverall, null, cs),
                    ...exam.pass.perCatMin.entries
                        .where((e) => answers.any((a) => a.cat == e.key))
                        .map((e) {
                      final cp = _pctFor((a) => a.cat == e.key);
                      final n = answers.where((a) => a.cat == e.key).length;
                      final short = exam.catMap[e.key]?.short ?? e.key;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _crit(context, short, '合格基準 ${e.value}% 以上', cp, e.value,
                            cp >= e.value, n, cs),
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
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(15),
                  backgroundColor: exam.color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('もう一度',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('ホームへ',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
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
        child: Text('分野別 正答率',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.outline)),
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
          SizedBox(width: 84, child: Text(c.short, style: TextStyle(fontSize: 12.5, color: cs.outline))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: cp / 100,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: c.color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
              width: 40,
              child: Text('$cp%',
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
      ));
    }
    return rows;
  }

  Widget _crit(BuildContext context, String title, String cap, int val, int thr, bool ok,
      int? denom, ColorScheme cs) {
    final color = ok ? kOk : kNg;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('$title${denom != null ? '（$denom問）' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            Text('$val% ${ok ? '✔' : '✕'}',
                style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 7),
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: val / 100, minHeight: 9, backgroundColor: cs.surface, color: color),
            ),
            Positioned(
              left: (thr / 100) * (MediaQuery.of(context).size.width - 32 - 44 - 26),
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

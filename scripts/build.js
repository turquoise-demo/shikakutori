/*
 * 複数試験対応ビルド。data/ を正本として検証し、Flutter/Web へ反映する。
 *  - data/exams.json      … 試験マニフェスト（区分・色・合格基準）
 *  - data/questions.json  … { examId: [ {id,cat,q,choices,correct,exp,year?} ... ] }
 * 出力:
 *  - flutter/assets/exams.json, flutter/assets/questions.json
 *  - web/index.html（EXAMS/QUESTIONS を埋め込んだ複数試験Webアプリ）
 * 使い方: node scripts/build.js
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DATA_DIR = path.join(ROOT, "data");
const FLUTTER_ASSETS = path.join(ROOT, "flutter", "assets");
const WEB_DIR = path.join(ROOT, "web");

const exams = JSON.parse(fs.readFileSync(path.join(DATA_DIR, "exams.json"), "utf8")).exams;
const qdata = JSON.parse(fs.readFileSync(path.join(DATA_DIR, "questions.json"), "utf8"));

const errs = [];
const summary = [];
for (const ex of exams) {
  const cats = new Set(ex.cats.map(c => c.key));
  const list = qdata[ex.id] || [];
  const seen = new Set();
  const byCat = {};
  list.forEach((q, i) => {
    const tag = `${ex.id}#${q.id || i}`;
    if (!q.id || seen.has(q.id)) errs.push(tag + ":id");
    seen.add(q.id);
    if (!Array.isArray(q.choices) || q.choices.length !== 4) errs.push(tag + ":choices");
    if (typeof q.correct !== "number" || q.correct < 0 || q.correct > 3) errs.push(tag + ":correct");
    if (!q.q || !q.exp) errs.push(tag + ":text");
    if (!cats.has(q.cat)) errs.push(tag + ":cat(" + q.cat + ")");
    byCat[q.cat] = (byCat[q.cat] || 0) + 1;
  });
  summary.push({ id: ex.id, name: ex.name, total: list.length, byCat });
}
if (errs.length) { console.error("検証NG:\n" + errs.slice(0, 50).join("\n")); process.exit(1); }

// Flutter アセット
fs.mkdirSync(FLUTTER_ASSETS, { recursive: true });
fs.writeFileSync(path.join(FLUTTER_ASSETS, "exams.json"), JSON.stringify({ exams }, null, 2) + "\n");
fs.writeFileSync(path.join(FLUTTER_ASSETS, "questions.json"), JSON.stringify(qdata, null, 2) + "\n");

// Web（データ＋マスコットSVG埋め込み）
fs.mkdirSync(WEB_DIR, { recursive: true });
const tplPath = path.join(WEB_DIR, "app.template.html");
const brand = (p) => fs.readFileSync(path.join(ROOT, "brand", p), "utf8");
if (fs.existsSync(tplPath)) {
  const tpl = fs.readFileSync(tplPath, "utf8");
  const html = tpl
    .replace("/*__EXAMS__*/", JSON.stringify({ exams }))
    .replace("/*__QUESTIONS__*/", JSON.stringify(qdata))
    .replace('"__SVG_CORRECT__"', JSON.stringify(brand("shikakutori-correct.svg")))
    .replace('"__SVG_WRONG__"', JSON.stringify(brand("shikakutori-wrong.svg")))
    .replace('"__SVG_BADGE__"', JSON.stringify(brand("shikakutori-badge.svg")))
    .replace('"__SVG_ICON__"', JSON.stringify(brand("shikakutori-icon.svg")));
  fs.writeFileSync(path.join(WEB_DIR, "index.html"), html);
}

// サマリ
console.log("=== ビルド完了 ===");
summary.forEach(s => {
  console.log(`${s.name} (${s.id}): ${s.total}問`, JSON.stringify(s.byCat));
});
console.log("出力: flutter/assets/{exams,questions}.json" + (fs.existsSync(tplPath) ? ", web/index.html" : ""));

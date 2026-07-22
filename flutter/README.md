# 管工事 一問一答（Flutter ネイティブ版）

1級管工事施工管理技士 第一次検定の学習アプリ。Web試作（`../kankouji-quiz.html`）と**同じ問題データ・同じ機能**をネイティブ化したもの。

## 構成
```
flutter/
  pubspec.yaml         依存（shared_preferences ほか）
  lib/main.dart        アプリ本体（ホーム/出題/結果、進捗保存、ライト/ダーク）
  assets/questions.json 問題データ（正本 ../data/questions.json のコピー）
```

## セットup（初回のみ）
1. Flutter SDK を導入（未インストール）
   - 公式手順: https://docs.flutter.dev/get-started/install/macos
   - Homebrew でも可: `brew install --cask flutter`
   - iOS実機/シミュレータには Xcode、Android には Android Studio が必要
2. 確認: `flutter doctor`

## 実行
```bash
cd flutter
flutter create .        # ios/android/ など各プラットフォームの雛形を生成（初回のみ）
flutter pub get
flutter run             # 接続中の端末/シミュレータで起動
```
> `flutter create .` は既存の pubspec.yaml / lib / assets を保持したまま、iOS・Android等のプロジェクトファイルを補完します。

## 問題データの更新フロー（重要）
問題の正本は **`../data/questions.json`**。編集は次のいずれか：
- 追加問題を `../scripts/extra-questions.js` に足す
- または `../data/questions.json` を直接編集

その後、プロジェクトルートで同期スクリプトを実行：
```bash
cd ..
node scripts/build.js
```
これで **Web版HTML と flutter/assets/questions.json の両方**へ自動反映されます（重複ID・4択・正解番号・区分・年度を検証）。

## ストア公開に向けて（今後）
- アプリアイコン・スプラッシュ・アプリ名の設定
- iOS: Apple Developer Program（年 $99）、Android: Google Play Console（初回 $25）
- プライバシーポリシー、スクリーンショット、審査対応
- （フェーズ2）ログイン＋クラウド同期、App内課金、学習リマインド通知

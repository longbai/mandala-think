# MandalaThink

[English](../README.md) · [简体中文](README.zh-Hans.md) · 日本語 · [한국어](README.ko.md)

MandalaThink は、iPhone と iPad で使える九マスの思考ツールです。3×3 表示で一つのテーマを整理し、9×9 表示でその枝をまとめて見渡せます。各マスにはメモ、写真、添付ファイル、アクションを登録でき、色も付けられます。画面表示は日本語、英語、簡体字中国語、韓国語に対応しています。

## マンダラ思考法

3×3 の中央に問いや目標を書き、周囲の八マスに関連する考えを書き出します。さらに掘り下げたい考えは、別の九マスの中央に置きます。たとえば「発表を準備する」の周りに「聞き手」「資料」「時間」を置き、「資料」から事例や画像、参考文献へと広げられます。[MandalArt の紹介](https://www.atpress.ne.jp/news/11958)

## 使い方

1. **プロジェクトを作成するか、開く。** 「新規」で名前と中央のテーマを入力します。「開く」から `.mprj` を開いたり、共有用の `.mandalaprj` や旧形式の `.mandala` を読み込んだりできます。
2. **マスを編集して展開する。** 空のマスをタップして入力すると自動保存されます。テキストのプレビューには最初の空白でない行を使います。マスをタップすると詳細が開き、右上のボタンで次の階層へ進みます。
3. **表示を切り替える。** ボード上部で 3×3 と 9×9 を切り替えます。9×9 は全体表示から始まり、ピンチで拡大縮小、ドラッグで移動できます。「全体表示」で元に戻ります。
4. **メディアとアクションを追加する。** 編集画面から写真、カメラ、ファイルを利用できます。マスの詳細からアクションを Apple のリマインダーに送り、リマインダーのリンクでプロジェクトに戻れます。
5. **共有またはバックアップする。** ボードのメニューから `.mandalaprj` または旧形式の `.mandala` に書き出せます。パッケージの構造は[形式仕様](mandala-format-v1.md)を参照してください。

### ブラウザーリーダー

`mandala-web-reader` を起動し、[http://127.0.0.1:8080](http://127.0.0.1:8080) を開きます。旧形式の `.mandala` ファイルを選ぶか、ドラッグ＆ドロップしてください。[sample.mandala](../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala) で試せます。ファイルはブラウザー内で読み込みます。ポートを変更するには `-listen 127.0.0.1:8081` を指定します。

## ビルドとテスト

### iPhone と iPad

リポジトリのルートにある [mandala-think.xcodeproj](../mandala-think.xcodeproj) を Xcode で開きます。`mandala-think` スキームと iPhone または iPad のシミュレータを選び、Run を実行します。iOS または iPadOS 17 以降が必要です。実機では **Signing & Capabilities** で開発チームを選択してください。既定のバンドル ID は `org.mandalathink.app` です。

形式テストはリポジトリのルートから実行します。

```sh
swift test --package-path MandalaCore
```

UI テストは Xcode の **Product → Test** で実行できます。旧形式の読み込みテストでは、テスト端末上のアプリの Documents フォルダに `sample.mandala` を置き、`TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1` を設定して `xcodebuild test` を実行します。写真のテストでは `simctl addmedia` で画像を追加し、`TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1` を設定します。

### ブラウザーリーダー

Go 1.22 以降を使い、リポジトリのルートで実行します。

```sh
go -C apps/web-reader build -buildvcs=false -o ../../mandala-web-reader .
```

[apps/web-reader/dist](../apps/web-reader/dist) の HTML、CSS、JavaScript は実行ファイルに埋め込まれます。実行ファイルだけをコピーして起動できます。

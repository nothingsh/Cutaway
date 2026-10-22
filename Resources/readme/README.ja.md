<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — iOS のインターフェースを、レイヤーごとに調べる。" width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | **日本語** | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*これは翻訳です。内容が異なる場合は [英語版の README](../../README.md) が優先されます。*

Cutaway は、実行中の iOS アプリのインターフェースの内部を調べるための macOS アプリです。[CutawayServer](https://github.com/nothingsh/CutawayServer) をアプリに追加し、シミュレータか USB で接続したデバイスで実行すると、Cutaway のリストに表示されます。それを選ぶと、Cutaway はアプリのレイヤーツリー、2D に平面で並べるか 3D で離して配置したすべてのレイヤーのスクリーンショット、そして選択したレイヤーの属性と Auto Layout 制約を表示します。属性に加えた編集は、実行中のアプリに適用されます。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway がアプリを 3D で検査している様子：レイヤーツリー、離して表示したレイヤー、選択したレイヤーの属性。" width="850">
  </picture>
</p>

<a id="features"></a>
## 機能

- **インターフェイスの組み立てを見る。** すべてのウインドウのレイヤーツリー。ビューコントローラと、各ビューを保持するメンバー変数が示されます。 [レイヤーリスト](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **3D で分解して見る。** すべてのレイヤーのスクリーンショットを 2D で平らに、または 3D で離して表示。回転、ズーム、間隔の調整ができます。 [プレビュー](https://nothingsh.github.io/Cutaway/guide/preview)
- **計測する。** ⌥ を押したまま別のレイヤー（プレビューまたはリスト）を指すと、ポイント単位の距離が表示されます。 [計測](https://nothingsh.github.io/Cutaway/guide/measuring)
- **実行中に変更する。** 属性を編集すると、実行中のアプリにすぐ反映されます。⌘Z で取り消せます。 [属性](https://nothingsh.github.io/Cutaway/guide/attributes)
- **制約をたどる。** ビューのすべての Auto Layout 制約と、有効でないもの、もう一方の端。 [制約](https://nothingsh.github.io/Cutaway/guide/constraints)
- **ダークモードや大きな文字を試す。** アプリの外観、文字サイズ、レイアウト方向、サイズクラスを上書きします。 [環境](https://nothingsh.github.io/Cutaway/guide/environment)
- **コードへ移動する。** クラスを Xcode で開き、アセットや String Catalog の名前を確かめ、LLDB コマンドをコピーできます。 [ソースコード](https://nothingsh.github.io/Cutaway/guide/source)
- **見つけたものを残す。** 検査をアーカイブに保存し、デバイスなしで任意の Mac で開けます。レイヤーを PNG に書き出せます。 [アーカイブと書き出し](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway が通信するのは、この Mac 上のアプリと USB ケーブルで接続されたアプリだけです。分析も、クラッシュレポートもありません。
英語、簡体字中国語、繁体字中国語、日本語、韓国語に対応しています。

<a id="requirements"></a>
## 動作要件

- macOS 14 以降。Metal に対応した GPU を搭載した Mac（macOS 14 が動作するすべての Mac）。
- [CutawayServer](https://github.com/nothingsh/CutawayServer) を組み込んだアプリ。iOS Simulator、または USB で Mac に接続した iPhone か iPad で実行されているもの。

<a id="installation"></a>
## インストール

[Releases](https://github.com/nothingsh/Cutaway/releases) ページから `Cutaway-<バージョン>.dmg` をダウンロードして開き、Cutaway をアプリケーションフォルダにドラッグしてください。Cutaway はオープンソースで、そのビルドは Apple の公証を受けていません。そのため初めて開くとき、macOS は開発元を検証できないと表示します。**システム設定 › プライバシーとセキュリティ** を開いて **このまま開く** を選ぶか、次を実行してください。

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › アップデートを確認…** で、新しいリリースが出ているかを確かめられます。

## クイックスタート

1. iOS アプリに [CutawayServer](https://github.com/nothingsh/CutawayServer) を追加し、起動時に `CutawayServer.start()` を 1 回呼び出します。Debug ビルドにのみコンパイルされます。
2. アプリをシミュレータ、またはケーブルで Mac に接続したデバイスで実行します。
3. Cutaway を開きます。数秒以内にアプリがリストに表示されます。それを選んでください。

すべての手順、UIKit と SwiftUI のコード、アプリが表示されないときに確認することは、[はじめにのガイド](https://nothingsh.github.io/Cutaway/guide/getting-started)にあります。

<a id="documentation"></a>
## ドキュメント

そのほかの内容はすべて [Cutaway のウェブサイト](https://nothingsh.github.io/Cutaway/)にあります（現在は英語と簡体字中国語のみ）。

- [ガイド](https://nothingsh.github.io/Cutaway/guide/getting-started)：作業ごとの Cutaway の使い方と、すべての[キーボードショートカット](https://nothingsh.github.io/Cutaway/guide/shortcuts)。
- [組み込み](https://nothingsh.github.io/Cutaway/integrate/)：アプリへの CutawayServer の追加、Debug と Release のビルド、アプリ独自の情報の表示。
- [プロトコル](https://nothingsh.github.io/Cutaway/protocol/)：Cutaway と CutawayServer の通信方法と、組み合わせて使えるバージョン。
- [FAQ とトラブルシューティング](https://nothingsh.github.io/Cutaway/resources/faq)、[プライバシーとセキュリティ](https://nothingsh.github.io/Cutaway/resources/privacy)、[パフォーマンス](https://nothingsh.github.io/Cutaway/resources/performance)、[リリースノート](https://nothingsh.github.io/Cutaway/resources/releases)、[ロードマップ](https://nothingsh.github.io/Cutaway/resources/roadmap)。

<a id="development"></a>
## 開発

Cutaway のビルドとテストの方法、変更のレビューの流れは [CONTRIBUTING.md](../../CONTRIBUTING.md) にあります。
3 つのリポジトリの関係は、ウェブサイトの [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) のページで説明しています。

## ライセンス

Cutaway はフリーソフトウェアで、GNU General Public License v3.0 の下で公開されています。[LICENSE](../../LICENSE) を参照してください。[FlatBuffers](https://github.com/google/flatbuffers)（Apache License 2.0）、[DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)（MIT）、[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)（MIT）を使って作られており、それぞれのライセンスは「Cutaway について」パネルと [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements) にあります。[Cutaway プロトコル](https://github.com/nothingsh/CutawayProtocol)は MIT ライセンスです。

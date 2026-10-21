<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — 逐層檢視 iOS 介面。" width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | **繁體中文** | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*本文為譯文；若與[英文 README](../../README.md) 有出入，以英文版為準。*

Cutaway 是一個用來查看正在執行的 iOS App 介面內部的 macOS App。把
[CutawayServer](https://github.com/nothingsh/CutawayServer) 加入你的 App，在模擬器中或在透過 USB
連接的裝置上執行它，Cutaway 就會列出它。選擇它，Cutaway 便會顯示該 App 的圖層樹、每個圖層的截圖
（平鋪成 2D 或在 3D 中分開展示），以及你所選取圖層的屬性和 Auto Layout 約束。你對屬性所做的編輯會
套用到正在執行的 App。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway 以 3D 檢視一個 App：圖層樹、分層展開並帶測量的預覽，以及所選圖層的屬性。" width="850">
  </picture>
</p>

<a id="features"></a>
## 功能

- **看清介面是如何建構的。** 每個視窗的圖層樹，標出視圖控制器，以及持有各個視圖的成員變數。 [圖層列表](https://nothingsh.github.io/Cutaway/guide/hierarchy)
- **在 3D 中拆開來看。** 每個圖層的截圖，平鋪為 2D 或在 3D 中分開展示；可以旋轉、縮放、改變層間距。 [預覽](https://nothingsh.github.io/Cutaway/guide/preview)
- **測量。** 按住 ⌥ 並指向另一個圖層（在預覽或列表中），就能看到以點為單位的距離。 [測量](https://nothingsh.github.io/Cutaway/guide/measuring)
- **在執行中修改。** 編輯屬性，修改會立即套用到正在執行的 App；⌘Z 可以還原。 [屬性](https://nothingsh.github.io/Cutaway/guide/attributes)
- **跟隨約束。** 視圖的每一條 Auto Layout 約束，標出未生效的，以及它們的另一端。 [約束](https://nothingsh.github.io/Cutaway/guide/constraints)
- **試試深色模式和更大的文字。** 覆寫 App 的外觀、文字大小、版面方向和尺寸類別。 [環境](https://nothingsh.github.io/Cutaway/guide/environment)
- **跳到你的程式碼。** 在 Xcode 中打開類別，看到 asset 和 String Catalog 裡的名稱，拷貝 LLDB 指令。 [原始碼](https://nothingsh.github.io/Cutaway/guide/source)
- **保留你的發現。** 把一次檢查存成封存檔，在任何一台 Mac 上不需裝置即可打開；把圖層輸出為 PNG。 [封存檔與輸出](https://nothingsh.github.io/Cutaway/guide/archives)

Cutaway 只與這台 Mac 上和透過 USB 傳輸線連接的 App 通訊：沒有分析統計，也沒有當機報告。
介面提供英文、簡體中文、繁體中文、日文和韓文。

<a id="requirements"></a>
## 需求

- macOS 14 或更新版本，Mac 需有支援 Metal 的 GPU（每一台能執行 macOS 14 的 Mac 都支援）。
- 一個包含 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的 App，在 iOS 模擬器中
  執行，或在透過 USB 連接到 Mac 的 iPhone 或 iPad 上執行。

<a id="installation"></a>
## 安裝

從 [Releases](https://github.com/nothingsh/Cutaway/releases) 頁面下載 `Cutaway-<版本號碼>.dmg`，打開後把 Cutaway 拖到「應用程式」。
Cutaway 是開源專案，它的建置沒有經過 Apple 公證，所以第一次打開時 macOS 會提示無法驗證開發者。
打開**系統設定 › 隱私權與安全性**，選擇**強制打開**；或者執行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 檢查更新…**會告訴你有沒有更新的版本。

## 快速上手

1. 把 [CutawayServer](https://github.com/nothingsh/CutawayServer) 加入你的 iOS App，並在啟動時呼叫一次 `CutawayServer.start()`。它只會編譯進
   Debug 建置。
2. 在模擬器中執行你的 App，或在用傳輸線連接到 Mac 的裝置上執行。
3. 開啟 Cutaway。幾秒鐘內你的 App 就會出現在列表中。選擇它。

[入門指南](https://nothingsh.github.io/Cutaway/guide/getting-started)列出了每一步、UIKit 和 SwiftUI 的程式碼，以及 App 沒有出現時要檢查什麼。

<a id="documentation"></a>
## 文件

其餘內容都在 [Cutaway 網站](https://nothingsh.github.io/Cutaway/)上（目前只有英文）：

- [指南](https://nothingsh.github.io/Cutaway/guide/getting-started)：依工作講解 Cutaway 的用法，以及所有[鍵盤快速鍵](https://nothingsh.github.io/Cutaway/guide/shortcuts)。
- [整合](https://nothingsh.github.io/Cutaway/integrate/)：把 CutawayServer 加入你的 App、Debug 與 Release 建置，以及顯示 App 自己的資訊。
- [協定](https://nothingsh.github.io/Cutaway/protocol/)：Cutaway 與 CutawayServer 如何通訊，以及哪些版本可以搭配使用。
- [常見問題與疑難排解](https://nothingsh.github.io/Cutaway/resources/faq)、[隱私權與安全性](https://nothingsh.github.io/Cutaway/resources/privacy)、[效能](https://nothingsh.github.io/Cutaway/resources/performance)、[版本紀錄](https://nothingsh.github.io/Cutaway/resources/releases)、[路線圖](https://nothingsh.github.io/Cutaway/resources/roadmap)。

<a id="development"></a>
## 開發

如何建置和測試 Cutaway、修改如何審閱，見 [CONTRIBUTING.md](../../CONTRIBUTING.md)。
網站的 [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) 一頁說明三個儲存庫如何配合。

## 授權

Cutaway 是自由軟體，以 GNU General Public License v3.0 發佈；見
[LICENSE](../../LICENSE)。它使用 [FlatBuffers](https://github.com/google/flatbuffers)（Apache
License 2.0）、[DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)（MIT）和
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)（MIT）建置；它們的授權條款在
「關於」面板和 [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements) 中。[Cutaway 協定](https://github.com/nothingsh/CutawayProtocol)採用 MIT 授權條款。

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

**看清介面是怎麼組成的**

- 每個視窗的圖層樹，並標出視圖控制器的根視圖，以及持有各個圖層或視圖的成員變數，讓圖層可以
  回溯到程式碼。
- 每個圖層的截圖，平鋪成 2D 或在 3D 中分開展示。用滑鼠或觸控式軌跡板旋轉、縮放和平移；調整
  圖層之間的間距；顯示被隱藏的圖層。
- 每個位置、大小、旋轉和縮放都和裝置螢幕上一致，包括 3D 變換。
- 測量：按住 ⌥ 並指向另一個圖層，即可看到它與所選圖層之間的距離，2D 和 3D 皆可。

**處理細節**

- 所選圖層和視圖的屬性，依用途分成五個區段，相關的屬性（例如邊框的寬度和顏色）放在同一列。可編輯
  的屬性有對應的控制項：文字、數字、核取方塊、顏色欄位，以及列舉用的彈出式選單和分段控制項。更改會
  立即套用到正在執行的 App，⌘Z 可以還原。
- 參照所選視圖的 Auto Layout 約束，標出其中未生效的。指向某條約束即可在預覽中標出它的另一端，也可以
  全部標出。按一下另一端即可前往。
- 搜尋圖層樹、聚焦於某個子樹、展開到指定深度、單獨重新整理某個子樹。

**保留你的發現**

- 把一次檢視儲存為 `.cutaway` 封存檔，之後在任何一台 Mac 上都能打開，不需要裝置：圖層樹、截圖、
  屬性和約束都在，連你當時的顯示方式也一併保留。
- 把某個圖層的截圖輸出為 PNG，可以只含圖層本身，也可以包含其子圖層。

**為日常使用而設計**

- 自動找到 App：在這台 Mac 上的模擬器中，以及透過 USB 連接的裝置上。
- 先顯示圖層樹，截圖到達時再逐一顯示；大型圖層樹依然保持回應。
- App 回來時會重新連線。跟上 App 的狀態：當它進入背景時，Cutaway 會說明，並在它回來後繼續。
- 提供英文、簡體中文、繁體中文、日文和韓文。
- 只和這台 Mac 上的 App 以及 USB 線另一端的 App 通訊。沒有分析數據，沒有當機報告。

<a id="requirements"></a>
## 需求

- macOS 14 或更新版本，Mac 需有支援 Metal 的 GPU（每一台能執行 macOS 14 的 Mac 都支援）。
- 一個包含 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的 App，在 iOS 模擬器中
  執行，或在透過 USB 連接到 Mac 的 iPhone 或 iPad 上執行。

Cutaway 沒有沙箱化，因為它用來透過 USB 連接裝置的 socket 位於沙箱之外。這也是它在 Mac App Store
之外發佈的原因。

<a id="installation"></a>
## 安裝

從 [Releases](https://github.com/nothingsh/Cutaway/releases) 頁面下載 `Cutaway-<版本號碼>.dmg`，打開後把 Cutaway 拖到「應用程式」。
Cutaway 是開源專案，它的建置沒有經過 Apple 公證，所以第一次打開時 macOS 會提示無法驗證開發者。
打開**系統設定 › 隱私權與安全性**，選擇**強制打開**；或者執行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 檢查更新…**會告訴你有沒有更新的版本。你也可以從原始碼建置 Cutaway；見[開發](#development)。

## 快速上手

1. 把 [CutawayServer](https://github.com/nothingsh/CutawayServer) 加入你的 iOS App，並在啟動時呼叫一次 `CutawayServer.start()`。伺服器的
   [README](https://github.com/nothingsh/CutawayServer#readme) 提供了 UIKit 和 SwiftUI 各自需要的
   兩行程式碼。它只會編譯進 Debug 建置。
2. 在模擬器中執行你的 App，或在用傳輸線連接到 Mac 的裝置上執行。
3. 開啟 Cutaway。幾秒鐘內你的 App 就會出現在列表中。選擇它。

## 使用 Cutaway

### 圖層列表

側邊欄以樹狀列出每個視窗的圖層。每一列顯示圖層的類別、它所支撐的視圖、以它為根視圖的視圖控制器，
以及持有它的成員變數，例如 `HomeViewController.titleLabel`。變暗的列代表已隱藏或完全透明的圖層。
圖示代表圖層的種類，App 自己的類別為實心，系統的類別為空心。捲動時，最上方那一列的祖先會固定在它
上方。

- 用最上方的欄位**過濾**圖層樹：標題或類別包含該文字的列會留下來，連同它們的祖先。
- **聚焦**於某個圖層（⌥⌘↓），在列表和預覽中都只顯示它的子樹；列表上方的路徑可以回到外層。
- 從過濾欄位旁的選單**展開**到指定的層級或全部展開（⌥⌘→ 和 ⌥⌘← 為全部展開和全部收合）。
  第一次檢視某個 App 時，圖層樹會一路展開到畫面上的視圖控制器。
- **按兩下**某一列可以展開或收合它。在預覽中按兩下某個圖層的效果相同。

### 預覽

預覽在圖層樹到達時，以及之後每張截圖到達時，把每個可見的圖層連同它的截圖畫在它在螢幕上的位置。

- 在工具列選擇 **2D 或 3D**（⌘1、⌘2）。在 3D 中，圖層會沿著深度分開排列；收合列表中的某一列會把
  它的子樹摺回一層。
- 在 3D 中拖移可**旋轉**；捲動可**平移**，在 2D 中拖移也可以；捏合或按住 ⌘ 並使用滾輪可**縮放**，
  以指標為中心。**重設視圖**（⌘0）回到初始狀態。
- 3D 中的**圖層間距**由預覽下方的滑桿控制，範圍從 0 到 200 點。
- **顯示隱藏的圖層**（⇧⌘H）也會以獨特的樣式畫出已隱藏或透明的圖層。**邊框**以單一顏色或依類別
  （使用列表中圖示的顏色）為圖層加上外框，也可以只限於 App 自己的類別；**顯示邊框**（⇧⌘B）可以關閉
  和重新打開邊框。**顯示約束的另一端**（⇧⌘K）會標出所選視圖各條約束的每一個另一端。這些也在預覽
  下方。
- **測量**：選取一個圖層後，按住 ⌥ 並指向另一個圖層。兩者之間的距離會連同以點為單位的數值一起
  畫出來，2D 和 3D 皆可。
- 按一下圖層可以選取它；列表和屬性會隨之更新。指標下方的圖層會被突顯。所選圖層旁邊的標籤會顯示
  它的名稱和大小。

### 屬性

右側的檢閱器顯示所選圖層及其視圖。圖層名稱下方是它最近的幾層祖先，沿著圖層樹往上排列；
**選擇父圖層**（⌘↑）和**選擇第一個子圖層**（⌘↓）沿著它移動。接著是依用途分成五個區段的屬性：
內容、外觀、佈局、行為和物件。屬於同一組的屬性共用一列，例如 Frame、邊框、陰影和圓角。Cutaway
自己沒有屬性清單：顯示的就是 [CutawayServer](https://github.com/nothingsh/CutawayServer) 送來的內容，所以 App 所用版本的伺服器知道什麼，它就顯示什麼。

- 用列表上方的欄位依標題或 ID **過濾**屬性。各區段可以收合；捲動時，最上方那個區段的標題會一直
  留在畫面中，按住 ⌥ 按一下標題可以收合或展開所有區段。
- App 標記為可編輯的屬性有對應的控制項：文字欄位、數字欄位、核取方塊、附十六進位值和不透明度的
  顏色欄位、列舉用的彈出式選單或分段控制項，以及點、大小、矩形、內距和變換的逐分量欄位。長度標明
  以點為單位；不透明度這類比例以百分比顯示和輸入，不透明度另外還有滑桿。
- 更改會在你確認時立即送出；拖移不透明度滑桿或使用顏色選擇器時則會持續送出。超出 App 接受範圍的
  值不會送出，欄位會說明原因。App 會回應該圖層的屬性，因此隨另一個屬性連動的屬性（例如圖層的
  不透明度隨視圖的 alpha 變化）也會一併更新。
- ⌘Z 還原上一次更改，⇧⌘Z 重做，在檢視期間一直有效。
- App 拒絕的更改會在該列說明原因，並恢復先前的值。

更改之後，Cutaway 會重新整理可能受到影響的圖層的截圖。

### 約束

佈局區段按 App 回報的方式列出視圖的 Auto Layout 約束：
`self.leading = Safe Area of UIView.leading + 16`，優先順序低於 1000 時附上優先順序，有識別碼時
附上識別碼。未生效的約束會變暗並加上標記；UIKit 產生的約束會摺成一列。按一下約束的另一端即可
選取那個視圖。指向某條約束即可在預覽中標出它的另一端；**顯示約束的另一端**（⇧⌘K）會一次標出
所有的另一端。

### 重新整理

Cutaway 顯示的是 App 在被詢問當時的樣子。**重新整理**（⌘R）會重新要求整棵圖層樹和每一張截圖，
並保留你的選取、展開狀態和相機。**重新整理所選子樹**（⇧⌘R，也在該列的右鍵選單中）只要求該圖層的
子樹。如果 App 進入背景，Cutaway 會等待；如果連線中斷，最後的畫面會留著，Cutaway 會在再次找到
同一個 App 時重新連線。

### 封存檔

**儲存封存檔…**（⌘S）把圖層樹、圖像，以及每個圖層（包括隱藏的）的截圖、屬性和約束，連同視窗
當時的樣子，收進一個 `.cutaway` 檔案。這個檔案可以用**打開…**（⌘O）、從 Finder，或拖放到
Cutaway 的圖像上打開，會在它自己的視窗中開啟，除了編輯之外，一切都和線上時一樣。可以同時打開
多個封存檔，和即時檢視並列。

**輸出圖層截圖…**（⇧⌘E）和**輸出含子圖層的截圖…**（⌥⇧⌘E）把所選圖層的影像以裝置的縮放比例
寫成 PNG，保留透明度，不含圖層自身的變換和不透明度。

### 設定

**設定…**（⌘,）有兩頁。**一般**選擇語言（跟隨系統，或五種語言之一）和外觀（系統預設、淺色或
深色）。**預覽**選擇新的檢視如何開始：2D 或 3D、圖層間距、是否顯示隱藏的圖層、邊框的樣式，以及
是否標出每條約束的另一端。已打開的視窗保持原樣。

### 鍵盤快速鍵

| 動作 | 按鍵 |
|---|---|
| 打開封存檔 | ⌘O |
| 儲存封存檔 | ⌘S |
| 輸出所選圖層的截圖，單獨 / 含子圖層 | ⇧⌘E / ⌥⇧⌘E |
| 還原 / 重做更改 | ⌘Z / ⇧⌘Z |
| 過濾圖層列表 | ⌘F |
| 重新整理全部 / 所選子樹 | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| 放大 / 縮小 / 重設視圖 | ⌘= / ⌘- / ⌘0 |
| 顯示隱藏的圖層 / 顯示邊框 / 顯示約束的另一端 | ⇧⌘H / ⇧⌘B / ⇧⌘K |
| 選擇父圖層 / 第一個子圖層 | ⌘↑ / ⌘↓ |
| 聚焦於所選圖層 / 顯示所有圖層 | ⌥⌘↓ / ⌥⌘↑ |
| 全部展開 / 全部收合 | ⌥⌘→ / ⌥⌘← |
| 顯示或隱藏側邊欄 / 檢閱器 | ⌃⌘S / ⌥⌘I |
| 顯示 App 列表 | ⇧⌘0 |
| 設定 | ⌘, |

## 效能

大型介面也應該感覺即時。Cutaway 圍繞這一點設計，而且測試套件在每次執行時都要求它達到下表的數字。
這些數字是在 Debug 建置中，針對一棵產生出來、形狀像真實 App 的 10,000 個圖層的樹（視窗、容器、
一條導覽列和一長串的列表 cell，每個 cell 各有一個圖示、數個標籤和一條分隔線）測得的：

| 操作 | 限制 |
|---|---|
| 圖層樹到達 → 列表顯示在畫面上 | 2 s |
| 佈局場景 | 1 s |
| 相機移動後的新一幀 | 16 ms |
| 繪製一幀 | 16 ms |
| 選取一列 → 預覽和檢閱器跟上 | 100 ms |
| 搜尋列表 | 200 ms |
| 全部展開 / 全部收合 | 1 s |
| 打開圖層樹的封存檔 → 列表顯示在畫面上 | 2 s |

它是怎麼做到的：

- **截圖保持壓縮狀態。** 模型只保留收到的壓縮位元組。它們在主執行緒以外解壓縮、上傳到 GPU，
  然後像素就被釋放。
- **預覽只在有變化時繪製。** 沒有任何東西在動時，不會送出任何一幀。
- **讀取跟上繪製的步調。** 當截圖到達的速度快過使用的速度時，Cutaway 會停止從連線讀取，由 TCP
  告訴 App 等待。記憶體中不會堆積任何東西。
- **不會累積任何東西。** 測試套件在 5,000 個圖層上把每個操作重複十次，並檢查沒有留下任何截圖、
  紋理、請求或視窗；更長的長時間測試（`scripts/soak.sh`）會印出一百輪之間的記憶體曲線。
- **錯誤的資料不會讓它當機。** 每個訊框在解碼前都會先經過驗證，而且每次執行都會用經過變異、截斷
  和拼接的訊框對解析器做模糊測試。

## 在 Mac 上的行為

- Cutaway 每兩秒嘗試一次 `127.0.0.1` 上的 48160 到 48167 連接埠（[CutawayServer](https://github.com/nothingsh/CutawayServer) 在模擬器中監聽的
  位置），以及透過 USB 連接的每台裝置上的相同連接埠（經由系統的 `usbmuxd`）。回應交握的 App 會被
  列出。
- 每個 App 一條連線，在 App 列在列表中的期間一直保持。已經有用戶端的 App 不會被打擾。
- 10 秒內沒收到任何位元組的請求會被放棄；App 送出[協定](https://github.com/nothingsh/CutawayProtocol)禁止的內容時，連線會被關閉。
- Cutaway 不會建立其他任何網路連線，只有你選擇**檢查更新…**時例外：這時它向 GitHub 取得本儲存庫的發行列表，不傳送任何關於你的 Mac 的資訊。
- 偏好設定存放在 `UserDefaults`；最近使用的封存檔在系統的最近使用過的文件列表中。

## 路線圖

以下是 1.0 之後規劃的方向，與 [CutawayServer](https://github.com/nothingsh/CutawayServer) 共用。順序和範圍可能會變動。

- **互動分析。** 顯示手勢辨識器和 target–action 配對；啟用和停用手勢；在物件上呼叫方法。
- **供宿主 App 使用的擴充 API。** 自訂屬性、虛擬子節點，以及像是預設收合的類別、顏色別名和從影像
  中排除的視圖等設定。
- **大型階層。** 只擷取可見圖層的快速模式；對超大影像分塊傳輸。
- **更多連線方式和平台。** 經過驗證和加密的 Wi-Fi 連線；tvOS 和 visionOS。
- **SwiftUI。** 與圖層樹並列的 SwiftUI 視圖語意階層。

## 常見問題

**我的 App 沒有出現在列表中。**
請確認建置包含 [CutawayServer](https://github.com/nothingsh/CutawayServer)（它只會編譯進 Debug 建置）並呼叫了 `CutawayServer.start()`、App 位於
前景，而且在實機上時，裝置已用傳輸線連接並信任這台 Mac。伺服器會使用 48160 到 48167 中第一個
空閒的連接埠；協定版本是 Cutaway 無法溝通的 App 也會列出，並顯示兩邊的版本。

**Cutaway 需要網路嗎？**
不需要。它透過回送位址和模擬器通訊，透過 USB 和裝置通訊。它從不連線到自己的任何伺服器。

**為什麼模糊、影片或 Metal 視圖是空白的？**
這些內容由系統的算繪伺服器在 App 行程之外合成，因此 [CutawayServer](https://github.com/nothingsh/CutawayServer) 無法從圖層樹算繪出來。

**沒有裝置時能查看 App 嗎？**
在裝置連接時儲存一份封存檔，之後在任何地方都能打開。開發時，測試支援程式庫也能把封存檔當成
模擬器中的 App 回放（`scripts/replay.sh`）。

**檢視會改變我的 App 嗎？**
只有你所做的編輯會。擷取會還原它動過的一切，讀取屬性也不會觸發佈局；請參閱 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的
README。

<a id="development"></a>
## 開發

Cutaway 以 Swift 6 搭配 AppKit 和 Metal 寫成。程式碼是一個本機 Swift 套件 `CutawayKit`，App
target 只負責把它組裝起來：

| Target | 內容 |
|---|---|
| `CutawayWire` | 訊框、以值型別表示的協定訊息，以及封存檔格式 |
| `CutawayTransport` | 尋找 App、`usbmuxd`、工作階段和請求 |
| `CutawayModel` | 圖層樹、截圖和屬性，以及各視窗共用的狀態 |
| `CutawayScene` | 每個圖層畫在哪裡、以什麼順序，以及點擊測試；純 Swift |
| `CutawayRender` | 用 Metal 繪製場景 |
| `CutawayUI` | 視窗、列表、預覽、檢閱器、設定 |
| `CutawayTestSupport` | 回放協定夾具的 mock 伺服器、合成的樹、仿造的 `usbmuxd` |

線路格式定義在 [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol)，以 submodule 的
形式簽出在 `Protocol/`；它的 Swift 程式碼由 schema 產生並簽入儲存庫。除了協定之外，沒有任何東西
和 [CutawayServer](https://github.com/nothingsh/CutawayServer) 共用。

複製儲存庫後執行一次 `./setup.sh`。它會簽出協定的 submodule、檢查 Xcode、XcodeGen 和 jq、把固定
版本的工具安裝到 `.tools/`、設定 git hooks，並從 `project.yml` 產生 `Cutaway.xcodeproj`。重複執行
也無妨。

| 工作 | 指令 |
|---|---|
| 以 CI 的方式建置並測試（只依賴程式碼） | `scripts/check.sh` |
| 只測試套件 | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| 格式化，然後 lint | `scripts/format.sh` |
| 把封存檔當成模擬器中的 App 提供給正在執行的 Cutaway | `scripts/replay.sh <file.cutaway>` |
| 把每個操作重複一百輪並印出記憶體曲線 | `scripts/soak.sh` |

- 沒有任何東西靠肉眼判斷。場景層由單元測試涵蓋；繪製層在螢幕外算繪，並與 `Baselines/` 中的基準圖
  比對。
- 測試從不需要裝置。連線是在這台 Mac 上，針對回放協定夾具的 mock 伺服器測試的。

## 授權

Cutaway 是自由軟體，以 GNU General Public License v3.0 發佈；見
[LICENSE](../../LICENSE)。它使用 [FlatBuffers](https://github.com/google/flatbuffers)（Apache
License 2.0）、[DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)（MIT）和
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)（MIT）建置；它們的授權條款在
「關於」面板和 [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements) 中。[Cutaway 協定](https://github.com/nothingsh/CutawayProtocol)採用 MIT 授權條款。

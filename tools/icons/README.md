# 圖示產生工具（前端）

把四個來源圖推導成前端（Flutter 六平台）所需的圖示與啟動畫面素材。

> 後端（Go 單一執行檔的內嵌 `.syso`、macOS 應用程式包）的圖示不在這裡：那由後端
> 倉庫自己的 `tools/icons/generate_icons.py` 負責。

## 為什麼需要它

各平台的圖示尺寸表是硬性的（Android 五種密度、iOS 十五格、macOS 七格、Web 四張、
Windows ico），手工匯出必然漂移：換了來源圖之後漏掉某一格不會報錯，只會在發布後
以「某台裝置上圖示還是舊的」的形式出現。這個腳本把尺寸表固化成唯一出口，
來源只有四個檔案，其餘全部推導；`--check` 可以隨時核對現況。

## 用法

```bash
python tools/icons/generate_icons.py          # 產生前端全部圖示與啟動畫面素材
python tools/icons/generate_icons.py --check  # 只核對，不寫入（CI 可用）
```

需要 Pillow（`python -m pip install Pillow`）；不連網、可重複執行，同一來源圖產生
位元組相同的輸出。

## 來源圖

| 檔案 | 用途 | 放哪裡 |
| --- | --- | --- |
| `EvernightRealmFrontendRounded.png` | 圓角、背景透明。用於 macOS、Web、Android 自適應前景、Linux 圖示主題、iOS 啟動畫面 | `assets/icons/` |
| `EvernightRealmFrontendSquare.png` | 正方形、不透明滿版。用於 iOS AppIcon、Android 舊版啟動圖示、店鋪素材 | `assets/icons/` |
| `EvernightRealmFrontendRounded.ico` | Windows 應用程式圖示，原樣沿用 | `assets/icons/` |
| `EvernightRealmFrontendRounded.icns` | macOS 應用程式圖示，原樣沿用 | `assets/icons/` |

**為什麼圓角／正方形要分開選**：iOS 與各應用商店明文禁止圖示自帶圓角與透明
（系統或商店會自己裁切），遞交帶圓角的圖會被判不合格；macOS 與 Linux 則相反，
圖示必須自帶圓角與外圍留白。同一份來源圖不可能同時滿足，所以兩者都留在版本庫。

## 產出去向

| 平台 | 位置 | 什麼時候需要 |
| --- | --- | --- |
| Android | `android/app/src/main/res/mipmap-*/ic_launcher{,_foreground}.png` | 建置前必須先產生（否則建置失敗） |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/`、`LaunchImage.imageset/` | 同上 |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | 同上 |
| Web | `web/icons/`、`web/favicon.png`、`web/favicon.ico` | 同上（否則頁面沒圖示） |
| Windows | `windows/runner/resources/app_icon.ico` | 同上 |
| Linux | `packaging/linux/icons/hicolor/<尺寸>/apps/<應用程式 ID>.png` | 只有打包 Linux 桌面時 |
| 展示／店鋪 | `assets/icons/generated/`（含 Play 512、App Store 1024） | 只有寫文件或上架商店時 |

進版本庫的只有**四張來源圖**與**指向它們的設定檔**（`*.xml`、`Contents.json`、
`manifest*.json`、`index.html`）；上表全部是由來源圖推導出來的，一律由 `.gitignore`
排除。因此**乾淨 clone 上要先跑一次本腳本**，否則 Android／iOS／macOS／Windows
建置會因資源缺失直接失敗、Web 則會沒有圖示：

```bash
python tools/icons/generate_icons.py    # 連同展示圖與 Linux 打包素材一起寫出來
```

由於上表全部不進版控，`--check` 不要求任何一個產物必須存在：已有的會逐張比對內容
與尺寸，缺席的不報錯。這樣乾淨 clone 上的核對才會是綠的；真正的把關在於
「有產生過的圖一定與來源圖一致」。

## 需要人工維護的地方

腳本只寫圖示檔，**不會改寫手寫的黏著設定檔**（產生器改壞手寫檔的代價太高）。
下列設定檔要指到新圖示，改一次即可；改完可以用 `--check` 核對，
它會檢查這些檔案是否仍與腳本內的品牌底色（`BRAND_BG = #2C2740`）一致：

| 檔案 | 要設定的內容 |
| --- | --- |
| `android/app/src/main/res/values/ic_launcher_background.xml` | 品牌底色（`BRAND_BG`） |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | 自適應圖示的兩層 |
| `android/app/src/main/res/drawable{,-v21}/launch_background.xml` | 啟動畫面底色與置中圖示 |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | 啟動畫面底色與 `LaunchImage` 顯示尺寸 |
| `web/index.html` | `favicon.ico`／`favicon.png`、啟動畫面標記 |
| `web/manifest*.json`（共四份） | `background_color`／`theme_color` |
| `linux/runner/my_application.cc` | `gtk_window_set_icon_name(window, APPLICATION_ID)` |
| `packaging/linux/moe.yashi.evernightrealm.desktop` | `Icon=` 要等於圖示主題裡的檔名（即應用程式 ID） |

## 改完之後

```bash
python tools/icons/generate_icons.py --check     # 圖示＋黏著設定檔一致性
flutter build web                                # 前端（其他平台同理）
```

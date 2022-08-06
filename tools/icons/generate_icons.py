#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""由基本來源圖產生長夜幻境前端（Flutter）各平台圖示與啟動畫面素材。

為什麼要有這個出口
==================
各平台的圖示尺寸表（Android 五種密度、iOS 十五格、macOS 七格、Web 四張、Windows ico）
是硬性的，但逐張手工匯出必然漂移：改了來源圖就會漏掉某一格，漏掉的那格不會報錯，
只會在發布後以「某台裝置上圖示還是舊的」的形式出現。本腳本把尺寸表固化成唯一出口，
來源只有四個檔案，其餘全部推導。

來源圖（本倉庫 assets/icons/，進版本庫）
========================================
    EvernightRealmFrontendRounded.png   圓角、背景透明（用於 macOS、Web、Android 自適應前景、Linux）
    EvernightRealmFrontendSquare.png    正方形、不透明滿版（用於 iOS、Android 舊版啟動圖示、商店圖）
    EvernightRealmFrontendRounded.ico   Windows 應用程式圖示（使用者提供，原樣沿用）
    EvernightRealmFrontendRounded.icns  macOS 應用程式圖示（使用者提供，原樣沿用）

用法
====
    python tools/icons/generate_icons.py          # 產生前端全部圖示與啟動畫面素材
    python tools/icons/generate_icons.py --check  # 只核對，不寫入
    python tools/icons/generate_icons.py --repo <倉庫根>

邊界
====
* 只寫入圖示檔；Android／iOS／Web／Linux 的黏著設定檔（launch_background.xml、
  LaunchScreen.storyboard、index.html…）由人手改一次，本腳本只核對其是否仍指向正確的
  設定，不重寫文字檔，避免產生器改壞手寫檔。
* 需要 Pillow，不連網，可重複執行（同一來源圖產生位元組相同的輸出）。
* 進版本庫的分界：只有四張來源圖與「指向它們的設定檔」進版控；由來源圖推導出來的
  圖檔（Android mipmap、iOS／macOS appiconset、web icons、Windows ico、展示圖、
  Linux 圖示主題）全由 .gitignore 排除。因此**乾淨 clone 上要先跑一次本腳本**，
  否則 Android／iOS／macOS／Windows 建置會因資源缺失失敗、Web 會沒圖示。
  判準由 .gitignore 決定（詳見 IGNORED_OUTPUT_MARKERS 與 --check 的一致性核對）。
* 後端（Go 單一執行檔與內嵌 .syso）的圖示由後端倉庫自己的 tools/icons/generate_icons.py
  負責，本腳本只處理這個前端倉庫。
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover - 環境缺件時給出可執行的指示
    sys.exit("需要 Pillow：python -m pip install Pillow")

# ---------------------------------------------------------------------------
# 品牌與路徑常數
# ---------------------------------------------------------------------------

# 啟動畫面、Android 自適應圖示底色與 Web 佈景色的單一來源。
# 取樣自正方形來源圖，前端取紫色外框調暗到與後端同一明度。
# 黏著設定檔內寫的是同一個字面值，--check 會核對兩邊一致。
BRAND_BG = "#2C2740"

# 來源檔名前綴與 Linux 桌面整合用的應用程式 ID。
PREFIX = "EvernightRealmFrontend"
APP_ID = "moe.yashi.evernightrealm"
DESKTOP_NAME = "EvernightRealm"

# 額外推導、不進版控的展示尺寸（供文件、README、店鋪素材使用）。
DISPLAY_SIZES = (16, 32, 48, 64, 128, 256, 512, 1024)
LINUX_HICOLOR_SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)

RESAMPLE = Image.Resampling.LANCZOS

# 已寫入的檔案清單，供結尾輸出（含 OUTPUT= 契約）。
_written: list[Path] = []


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------


def find_repo_root(start: Path) -> Path:
    """自 start 往上找含 pubspec.yaml 的目錄，作為本前端倉庫根。"""
    for candidate in [start, *start.parents]:
        if (candidate / "pubspec.yaml").is_file():
            return candidate
    sys.exit(f"找不到前端倉庫根（沿路徑找不到 pubspec.yaml）：{start}")


def resize(im: Image.Image, size: int) -> Image.Image:
    """縮放到 size×size；先以整數倍折半再收尾，避免大幅縮小時細節崩壞。"""
    w, h = im.size
    work = im
    while w % 2 == 0 and h % 2 == 0 and w // 2 >= size and h // 2 >= size:
        w, h = w // 2, h // 2
        work = work.resize((w, h), Image.Resampling.BOX)
    if (w, h) != (size, size):
        work = work.resize((size, size), RESAMPLE)
    return work


def centered_on_canvas(im: Image.Image, canvas: int, ratio: float,
                       bg: tuple[int, int, int, int] | None = None) -> Image.Image:
    """把 im 縮到 canvas×ratio 後置中貼到透明（或指定底色）畫布上。"""
    out = Image.new("RGBA", (canvas, canvas), bg or (0, 0, 0, 0))
    side = max(1, round(canvas * ratio))
    out.alpha_composite(resize(im, side), ((canvas - side) // 2, (canvas - side) // 2))
    return out


def save_png(im: Image.Image, path: Path, opaque: bool = False) -> None:
    """寫出 PNG；opaque=True 時壓掉 alpha 圖層（iOS 與商店圖示不接受透明）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        flat = Image.alpha_composite(Image.new("RGBA", im.size, (0, 0, 0, 255)),
                                     im.convert("RGBA")).convert("RGB")
        flat.save(path, format="PNG", optimize=True)
    else:
        im.convert("RGBA").save(path, format="PNG", optimize=True)
    _written.append(path)


def copy_file(src: Path, dst: Path) -> None:
    """原樣複製（用於使用者提供的 ico／icns）。"""
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    _written.append(dst)


def hex_to_rgb(value: str) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)


# ---------------------------------------------------------------------------
# 圖示清單（單一來源：產生與核對共用同一份任務表）
# ---------------------------------------------------------------------------

ANDROID_MIPMAPS = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]

# iOS AppIcon：內容為正方形不透明來源，圓角由系統加上（Apple 規定不可自帶圓角與透明）
IOS_APPICON = [
    ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120), ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180), ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152), ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

# iOS 啟動畫面：置中圖示，底色由 LaunchScreen.storyboard 提供（1x 為 120pt）
IOS_LAUNCH = [("LaunchImage.png", 120), ("LaunchImage@2x.png", 240),
              ("LaunchImage@3x.png", 360)]

# macOS AppIcon：內容為圓角透明來源（macOS 圖示自帶圓角與外圍留白）
MACOS_APPICON = [("app_icon_%d.png" % s, s) for s in (16, 32, 64, 128, 256, 512, 1024)]

# Android 自適應圖示：背景為品牌底色，前景為置中的圓角標誌（安全區 72/108）
ADAPTIVE_FOREGROUND_RATIO = 72 / 108


def png_task(path: Path, image: Image.Image, opaque: bool = False) -> dict:
    return {"kind": "png", "path": path, "image": image, "opaque": opaque}


def copy_task(path: Path, src: Path) -> dict:
    return {"kind": "copy", "path": path, "src": src}


def ico_task(path: Path, image: Image.Image, sizes: tuple[int, ...]) -> dict:
    return {"kind": "ico", "path": path, "image": image, "sizes": sizes}


def load_sources(repo_root: Path) -> dict:
    """載入四個來源檔；缺少任何一個就停止（不猜預設圖）。"""
    icon_dir = repo_root / "assets" / "icons"
    paths = {
        "rounded_png": icon_dir / f"{PREFIX}Rounded.png",
        "square_png": icon_dir / f"{PREFIX}Square.png",
        "ico": icon_dir / f"{PREFIX}Rounded.ico",
        "icns": icon_dir / f"{PREFIX}Rounded.icns",
    }
    missing = [str(p) for p in paths.values() if not p.is_file()]
    if missing:
        sys.exit("缺少來源圖，請先放入 assets/icons/：\n  " + "\n  ".join(missing))
    return {
        "root": repo_root,
        "prefix": PREFIX,
        "rounded": Image.open(paths["rounded_png"]).convert("RGBA"),
        "square": Image.open(paths["square_png"]).convert("RGBA"),
        "ico": paths["ico"],
        "icns": paths["icns"],
    }


# 不進版控的產物（相對片段，比對 POSIX 路徑子字串）。必須與本倉庫的 .gitignore 一致：
# 這些產物在乾淨 clone 上本來就不存在，所以核對時允許缺席，有出現才比對內容。
# --check 會用 git check-ignore 交叉核對本清單，出現偏差會直接報出來。
IGNORED_OUTPUT_MARKERS = (
    "/assets/icons/generated/",              # 多尺寸展示圖、商店圖
    "/packaging/linux/icons/",               # Linux 圖示主題（打包時安裝）
    "/ic_launcher.png",                      # Android 舊版啟動圖示
    "/ic_launcher_foreground.png",           # Android 自適應圖示前景
    "/Assets.xcassets/AppIcon.appiconset/",  # iOS／macOS 應用程式圖示
    "/Assets.xcassets/LaunchImage.imageset/",  # iOS 啟動畫面圖
    "/web/favicon.",                         # Web favicon（png 與 ico）
    "/web/icons/",                           # Web manifest 圖示
    "/runner/resources/app_icon.ico",        # Windows 視窗圖示（來源 ico 的複本）
)


def is_ignored_output(path: Path) -> bool:
    """此產物是否屬於「不進版控」的那一類（離線判定：只看上面的清單）。"""
    posix = path.as_posix()
    return any(marker in posix for marker in IGNORED_OUTPUT_MARKERS)


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def git_ignored(paths: list[Path], roots: list[Path]) -> dict[Path, bool] | None:
    """用 git check-ignore 問出每個產物的忽略狀態。

    git 不裝、不在倉庫裡、或呼叫失敗時回傳 None（呼叫方改走離線清單）。
    check-ignore 預設會參考索引，所以「已被追蹤」的檔不會回報為忽略，
    正是我們要的語意：它區分的是「不進版控」而不是「符合忽略樣式」。
    """
    result: dict[Path, bool] = {path: False for path in paths}
    queried = False
    for root in roots:
        group = [p for p in paths if _is_within(p, root)]
        if not group:
            continue
        payload = b"\0".join(
            p.relative_to(root).as_posix().encode("utf-8") for p in group) + b"\0"
        try:
            # 用 -z（NUL 分隔）而不是逐行餵 stdin：Windows 上文字模式的 stdin 會把
            # \n 轉成 \r\n，git 收到帶 \r 的路徑就當成含控制字元，輸出時整條加引號
            # （"path\r"），字典查不中，於是核對永遠判定「忽略清單與 .gitignore
            # 不一致」。NUL 不受換行轉換影響，順帶也免掉引號解析與編碼問題。
            done = subprocess.run(
                ["git", "-C", str(root), "check-ignore", "-z", "--stdin"],
                input=payload, capture_output=True, check=False)
        except (OSError, ValueError):
            return None
        # 0＝有命中、1＝都沒命中，兩者都代表指令正常執行完畢。
        if done.returncode not in (0, 1):
            return None
        queried = True
        for raw in done.stdout.split(b"\0"):
            line = raw.decode("utf-8", "surrogateescape").strip()
            if line:
                result[(root / line).resolve()] = True
    return result if queried else None


def resolve_ignored(tasks: list[dict], roots: list[Path]) -> tuple[dict[Path, bool], list[str]]:
    """決定每個產物是否「不進版控」，並回傳（旗標、與 .gitignore 的偏差）。"""
    flags = {task["path"]: is_ignored_output(task["path"]) for task in tasks}
    by_git = git_ignored(list(flags), roots)
    if by_git is None:
        return flags, []
    drift: list[str] = []
    for path, flag in flags.items():
        actual = by_git.get(path, False)
        if actual != flag:
            drift.append(
                f"忽略清單與 .gitignore 不一致：{path}"
                f"（清單判定{'忽略' if flag else '需存在'}，"
                f".gitignore 判定{'忽略' if actual else '需存在'}）")
    return flags, drift


def display_tasks(root: Path, src: dict) -> list[dict]:
    """推導多尺寸展示圖與店鋪素材（不進版控，需要時再跑）。"""
    out_dir = root / "assets" / "icons" / "generated"
    tasks: list[dict] = []
    for size in DISPLAY_SIZES:
        tasks.append(png_task(out_dir / "png" / "rounded" / f"{size}.png",
                              resize(src["rounded"], size)))
        tasks.append(png_task(out_dir / "png" / "square" / f"{size}.png",
                              resize(src["square"], size), opaque=True))
    # 店鋪素材：Google Play 要求 512×512、無透明、不可自帶圓角；
    # App Store 要求 1024×1024、無透明、不可自帶圓角。
    tasks.append(png_task(out_dir / "store" / "play-512.png",
                          resize(src["square"], 512), opaque=True))
    tasks.append(png_task(out_dir / "store" / "appstore-1024.png",
                          resize(src["square"], 1024), opaque=True))
    return tasks


def linux_hicolor_tasks(root: Path, src: dict) -> list[dict]:
    """Linux 圖示主題（hicolor），供 .desktop 與 GTK 以應用程式 ID 取用。"""
    base = root / "packaging" / "linux" / "icons" / "hicolor"
    tasks = []
    for size in LINUX_HICOLOR_SIZES:
        tasks.append(png_task(base / f"{size}x{size}" / "apps" / f"{APP_ID}.png",
                              resize(src["rounded"], size)))
    return tasks


def frontend_tasks(repo_root: Path, src: dict) -> list[dict]:
    """前端（Flutter）六平台圖示。"""
    root = src["root"]
    rounded, square = src["rounded"], src["square"]
    tasks: list[dict] = []

    # Android：舊版啟動圖示用正方形滿版；自適應圖示另給置中前景。
    res = root / "android" / "app" / "src" / "main" / "res"
    for density, legacy, canvas in ANDROID_MIPMAPS:
        tasks.append(png_task(res / f"mipmap-{density}" / "ic_launcher.png",
                              resize(square, legacy), opaque=True))
        tasks.append(png_task(res / f"mipmap-{density}" / "ic_launcher_foreground.png",
                              centered_on_canvas(rounded, canvas,
                                                 ADAPTIVE_FOREGROUND_RATIO)))

    # iOS：AppIcon 用正方形不透明（系統負責圓角）；啟動畫面為置中標誌。
    ios_icon = root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in IOS_APPICON:
        tasks.append(png_task(ios_icon / name, resize(square, size), opaque=True))
    ios_launch = root / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    for name, size in IOS_LAUNCH:
        tasks.append(png_task(ios_launch / name, resize(rounded, size)))

    # macOS：圖示自帶圓角，用圓角來源。
    macos_icon = root / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in MACOS_APPICON:
        tasks.append(png_task(macos_icon / name, resize(rounded, size)))

    # Web：PWA 的 any 與 maskable 都用正方形滿版（滿版美術在遮罩下表現最好）。
    web_icons = root / "web" / "icons"
    for size in (192, 512):
        tasks.append(png_task(web_icons / f"Icon-{size}.png",
                              resize(square, size), opaque=True))
        tasks.append(png_task(web_icons / f"Icon-maskable-{size}.png",
                              resize(square, size), opaque=True))
    tasks.append(png_task(root / "web" / "favicon.png",
                          resize(square, 32), opaque=True))
    # 瀏覽器分頁圖示另外給一份輕量 ico（使用者提供的 ico 內含 10 格、兩百餘 KB，
    # 當 favicon 太重；Windows 應用程式圖示仍原樣沿用該檔）。
    tasks.append(ico_task(root / "web" / "favicon.ico", rounded, (16, 32, 48)))

    # Windows：直接換掉 Runner.rc 引用的那份圖示。
    tasks.append(copy_task(root / "windows" / "runner" / "resources" / "app_icon.ico",
                           src["ico"]))

    # Linux：視窗圖示由 GTK 依應用程式 ID 從圖示主題取用。
    tasks.extend(linux_hicolor_tasks(root, src))

    tasks.extend(display_tasks(root, src))
    return tasks


# ---------------------------------------------------------------------------
# 執行與核對
# ---------------------------------------------------------------------------


def execute(tasks: list[dict]) -> None:
    for task in tasks:
        kind = task["kind"]
        if kind == "png":
            save_png(task["image"], task["path"], task["opaque"])
        elif kind == "copy":
            copy_file(task["src"], task["path"])
        elif kind == "ico":
            task["path"].parent.mkdir(parents=True, exist_ok=True)
            task["image"].save(task["path"], format="ICO",
                               sizes=[(s, s) for s in task["sizes"]])
            _written.append(task["path"])
        else:  # pragma: no cover - 任務表由本檔產生，不該出現未知型別
            sys.exit(f"未知的任務型別：{kind}")


def check(tasks: list[dict], optional: dict[Path, bool]) -> tuple[list[str], int, int]:
    """核對輸出檔，回傳（問題清單、已核對數、允許缺席而確實缺席數）。"""
    problems: list[str] = []
    verified = 0
    absent = 0
    for task in tasks:
        path = task["path"]
        kind = task["kind"]
        if not path.is_file():
            if optional.get(path, False):
                # 不進版控的產物不要求存在，才不會讓乾淨 clone 上的核對失敗。
                absent += 1
                continue
            problems.append(f"缺少檔案：{path}")
            continue
        verified += 1
        if kind == "png":
            with Image.open(path) as im:
                want = task["image"].size
                if im.size != want:
                    problems.append(f"尺寸不符：{path}（{im.size} != {want}）")
                if task["opaque"] and im.mode != "RGB":
                    problems.append(f"應為不透明卻帶有 alpha：{path}（{im.mode}）")
        elif kind == "copy":
            if path.read_bytes() != task["src"].read_bytes():
                problems.append(f"內容與來源不一致：{path}")
        elif kind == "ico":
            with Image.open(path) as im:
                got = set(im.ico.sizes())
            want = {(s, s) for s in task["sizes"]}
            if not want <= got:
                problems.append(f"ICO 格數不足：{path}（{sorted(got)}）")
    return problems, verified, absent


def check_glue(repo_root: Path) -> list[str]:
    """核對人手改過的黏著設定檔仍與本腳本的品牌底色一致。"""
    rgb = hex_to_rgb(BRAND_BG)
    srgb = tuple(f"{c / 255:.6f}" for c in rgb[:3])
    checks: list[tuple[Path, list[str]]] = [
        (repo_root / "android/app/src/main/res/drawable/launch_background.xml",
         ["@color/ic_launcher_background", "@mipmap/ic_launcher_foreground"]),
        (repo_root / "android/app/src/main/res/drawable-v21/launch_background.xml",
         ["@color/ic_launcher_background", "@mipmap/ic_launcher_foreground"]),
        (repo_root / "android/app/src/main/res/values/ic_launcher_background.xml",
         [BRAND_BG.lower()]),
        (repo_root / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
         ["@color/ic_launcher_background", "@mipmap/ic_launcher_foreground"]),
        (repo_root / "ios/Runner/Base.lproj/LaunchScreen.storyboard",
         ['image="LaunchImage"', f'red="{srgb[0]}"', f'green="{srgb[1]}"',
          f'blue="{srgb[2]}"', 'width="120" height="120"']),
        (repo_root / "web/index.html",
         [BRAND_BG.lower(), "favicon.ico", "icons/Icon-512.png"]),
        (repo_root / "web/manifest.json", [BRAND_BG.lower()]),
        (repo_root / "linux/runner/my_application.cc", ["gtk_window_set_icon_name"]),
        (repo_root / "packaging/linux/moe.yashi.evernightrealm.desktop", [APP_ID]),
    ]

    problems: list[str] = []
    for path, needles in checks:
        if not path.is_file():
            problems.append(f"缺少黏著設定檔：{path}")
            continue
        text = path.read_text(encoding="utf-8")
        low = text.lower()
        for needle in needles:
            if needle.lower() not in low:
                problems.append(f"{path} 未包含預期設定：{needle}")
    return problems


# ---------------------------------------------------------------------------
# 命令列
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="由基本來源圖產生前端各平台圖示與啟動畫面素材")
    parser.add_argument("--repo", default=None,
                        help="前端倉庫根目錄（預設自本檔位置往上找 pubspec.yaml）")
    parser.add_argument("--check", action="store_true",
                        help="只核對現況，不寫入任何檔案")
    args = parser.parse_args(argv)

    repo_root = (Path(args.repo).resolve() if args.repo
                 else find_repo_root(Path(__file__).resolve().parent))

    src = load_sources(repo_root)
    tasks = frontend_tasks(repo_root, src)
    problems = check_glue(repo_root)

    optional, drift = resolve_ignored(tasks, [repo_root])

    if args.check:
        found, verified, absent = check(tasks, optional)
        problems += found + drift
        if problems:
            print("[圖示核對] 發現問題：")
            for line in problems:
                print("  -", line)
            return 1
        if verified:
            print(f"[圖示核對] 通過：{verified} 個輸出檔符合預期；"
                  f"黏著設定檔亦指向正確來源。")
        else:
            print("[圖示核對] 通過：目前沒有任何圖示產物；"
                  "黏著設定檔亦指向正確來源。")
        if absent:
            print(f"[圖示核對] 另有 {absent} 個產物未產生"
                  f"（圖示產物一律不進版控，建置前執行產生即可）。")
        return 0

    if drift:
        print("[圖示產生] 警告：忽略清單與 .gitignore 不一致：")
        for line in drift:
            print("  -", line)

    if problems:
        print("[圖示核對] 黏著設定檔有問題，先修正再產生：")
        for line in problems:
            print("  -", line)
        return 1

    execute(tasks)

    print(f"[圖示產生] 完成 {len(tasks)} 個輸出檔，品牌底色 {BRAND_BG}。")
    for path in _written:
        print(f"OUTPUT={path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

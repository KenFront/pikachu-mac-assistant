# desktop-pokemon

macOS 桌寵：單一檔案 `Pikachu.swift`（AppKit + Core Graphics，無相依套件）。

## 建置與檢查

- 執行：`swiftc -O Pikachu.swift -o pikachu && ./pikachu`（選單列 ⚡ 或在皮卡丘身上按右鍵 →「結束」）
- 自我檢查：`./pikachu --selftest`（不開視窗，模擬甩出去落地、直接放在地上、幾分鐘的隨機行為，確認不會卡住或跑出螢幕；也檢查監控狀態檔的反應與清理）

## 造型（使用者指定）

- 初代 Game Boy 像素風，參考的是灰階像素皮卡丘玩偶：四階灰調色盤、臉頰用棋盤格網點、後耳往側邊倒、尾巴灰色根部深色。
- 身材要「肥胖」：頭身幾乎連成一團、寬高接近 1:1，不要改回瘦長的現代版比例。

## 架構

- 透明無邊框的 `NSPanel`（`.nonactivatingPanel`，點牠不會搶走其他 App 的焦點）跟著皮卡丘移動；`tick()` 60Hz 更新物理，視窗位置對齊像素格（一格 2.5pt），重畫頻率由頂部的 `fps` 控制。
- `pose()` 只依 `act`／`actT`／`t` 算出姿勢。新增動作：在 `Act` 加 case，補 `start()`（時長、對話框）、`tick()`（需要移動時）、`pose()`，再加進 `next()` 的機率表與 `makeMenu()`。
- `next()` 的隨機行為只能放沒有意義的動作（使用者指定：看到有意義的動作就代表真的有事）。揮手、坐下、睡覺、開心、十萬伏特（會放電）都保留給監控，點牠或從選單選還是可以觸發；自我檢查會確認隨機行為不會跑出這些動作。
- 繪圖流程（`draw(_:)`）：身體／耳朵／尾巴用向量畫在 72×54 的低解析度畫布（關反鋸齒）→ 臉頰的洋紅記號色換成網點（`dither`）→ 臉、對話框、Zzz 用手點的像素圖（`plot`，K/D/M/W 對應調色盤）→ 最近鄰放大到視窗。
- 向量座標系：原點在兩腳中間的地面、y 朝上、預設面向右（3/4 側臉），面向左時 `scaleBy(x: -1)` 鏡像；像素臉跟著 `face` 一起鏡像。
- 監控 Claude Code／Grok Build：
  - `~/.claude/settings.json` 的 hooks 會執行 `exec <專案>/pikachu --hook <busy|wait|done|fail|idle>`，寫出 `~/.pikachu/<claude 或 grok 的 PID>`。
  - 檔案第一行是狀態，第二行是選單上的「工具 · 專案」：工具看有沒有 `GROK_HOOK_EVENT`，專案取事件 JSON 的 `cwd`。`fail` 遇到 `error == "rate_limit"` 時，`--hook` 會自己改成 `limit`。
  - Grok 透過 Claude 相容模式讀同一份 hooks；Grok 專有的 `StopCancelled` 另外放在 `~/.grok/hooks/pikachu.json`。
  - `watch()` 每秒讀一次這個資料夾，PID 已經不存在的檔案就刪掉。
  - 各狀態的反應：
    - busy：臉頰放電。
    - wait：每 8 秒揮手。
    - done：開心；如果你已經 `awayAfter` 秒沒碰鍵盤滑鼠，就每 8 秒慶祝一次，等你回來再慶祝一次。
    - fail：坐下說 PIKA...。
    - limit：`next()` 會一直選睡覺，直到恢復。
  - done／fail 只在從 busy／wait 變過來時才有反應。
  - `refreshMenus()` 在狀態有變時重做右鍵選單和選單列 ⚡ 的選單（列出每個 session），⚡ 後面的記號：`!` 等你、`z` 額度用完、`…` 工作中。

## 陷阱

- 小東西（眼睛、嘴、手）用向量在低解析度下會糊成一團，要用 `plot` 手點；線寬要是 `dot` 的倍數，小於 1 像素在關反鋸齒時會斷掉。
- 自建 `CGContext` 的 `convertToDeviceSpace` y 軸是反的，回到像素座標要再用 `convertToUserSpace` 轉回來。
- 對話框文字只能用 `glyphs` 裡有的字（大寫 PIKACHUZ 與 `!?.-`、空白），其他字元會變空白。
- 點擊穿透靠 macOS 預設行為（透明像素不接滑鼠事件）；明確設定 `ignoresMouseEvents = false` 會讓整個視窗擋住點擊。
- CPU 主要花在重畫與搬視窗：待機約 4%、走路約 6%、跑步約 10%。強制 8-bit 圖層（`contentsFormat`、`depthLimit`）沒有效果。
- 終端機沒有螢幕錄影權限，`screencapture` 會失敗。要看畫面時，離屏建立 `Pikachu`、設好 `act`／`actT`，呼叫 `draw(_:)` 畫進 `NSBitmapImageRep` 存成 PNG。
- `-O` 建置下 `precondition` 不會印出訊息，自我檢查要用 `fatalError`。
- Grok 會先自己展開 hook command 裡的 `$VAR`，遇到沒設定的環境變數（例如 `$PPID`）會整個 hook 不執行，所以 command 裡不要放 shell 變數。
- hook 一定要用 `exec` 呼叫，`getppid()` 才會是 claude／grok 本身；沒有 exec 的話拿到的是中間那個 `sh`，它一結束，狀態檔就會被當成 session 已經結束而清掉。
- hooks 裡寫的是 `pikachu` 的絕對路徑：專案搬家或改名時，`~/.claude/settings.json` 和 `~/.grok/hooks/pikachu.json` 都要跟著改。
- Claude Code 的時機限制：
  - hooks 在 session 開始時載入，改完設定要在 `/hooks` 開一次或重開 session 才生效。
  - 按 Esc 中斷不會送任何事件，要等 `idle_prompt`（約 60 秒）才變回 idle。
  - `permission_prompt` 要等約 6 秒才觸發，而且在打字時不會觸發。
- `NSHomeDirectory()` 不理會 `$HOME`：手動測 `--hook` 會寫進真的 `~/.pikachu`（皮卡丘會自動清掉 PID 已不存在的檔案）。

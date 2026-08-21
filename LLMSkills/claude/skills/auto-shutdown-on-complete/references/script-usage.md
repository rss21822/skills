# scripts/shutdown.ps1 の詳細

Git Bash から呼ぶときは常に `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 経由にする。
`-NoProfile` はユーザーのPowerShellプロファイルによる副作用を避けるため、`-ExecutionPolicy Bypass` は
署名なしスクリプトが既定のポリシーで弾かれるのを避けるためで、どちらも省略すると環境によって沈黙して失敗する。

## モード一覧

| コマンド | 動作 | 電源への影響 |
|---|---|---|
| `-Arm -Reason "<完了条件>"` | 予約を状態ファイルに記録 | なし |
| `-Status` | `ARMED` / `NOT_ARMED` を出力。ARMEDなら予約内容のJSONも出す | なし |
| `-Disarm` | 予約を削除 | なし |
| `-Fire [-Delay 360]` | `shutdown.exe /s /t <Delay>` を発行し、予約を削除。`-Delay` 既定値は 360 秒（6分） | **あり** |
| `-Cancel` | `shutdown.exe /a` でタイマーを取り消す | 取消 |

引数なしで呼ぶと使い方を表示して終了コード1を返す。

## ファイルの場所

- 予約状態: `%USERPROFILE%\.claude\auto-shutdown.state`（JSON: `armed_at` / `reason` / `delay`）
- ログ: `%USERPROFILE%\.claude\auto-shutdown.log`

状態ファイルは「このセッションはシャットダウン予約中である」という事実を、文脈が圧縮されても残すためにある。
長時間セッションで自分が予約中かどうか怪しくなったら `-Status` を叩けばよい。

## DRYRUN

`CLAUDE_SHUTDOWN_DRYRUN=1` を立てると `-Fire` / `-Cancel` は `shutdown.exe` を呼ばず、
実行予定のコマンドをログに書くだけになる。判断ロジックを試したいときや、
ユーザーに挙動を見せたいときに使う。Git Bash からは次のように渡す:

```bash
CLAUDE_SHUTDOWN_DRYRUN=1 powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "<skill>/scripts/shutdown.ps1" -Fire -Delay 360
```

## 想定される失敗と対処

- **`shutdown.exe /a` が「タイマーが設定されていません」で失敗する** — 既に猶予が過ぎたか、そもそも
  発行していない。スクリプトはこれを致命的扱いせずログに書いて正常終了する。
- **`-Fire` がアクセス拒否になる** — シャットダウン権限のないアカウント。ユーザーに管理者権限での実行が
  必要である旨を伝え、勝手に昇格を試みない。
- **`powershell.exe` が見つからない** — Git Bash のPATHに Windows のSystem32 が入っていない。
  `/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` をフルパスで指定する。

# APIキーの配置（初回のみ）

Claude Codeはあなたのマシン上で動くので、キーもローカルに置くだけでよい。
方式は2つ。**環境変数が最も楽**で、プロジェクトごとにキーを分けたいときだけファイル方式にする。

チャットにキーを貼るのは避ける。会話履歴に残るうえ、セッションごとに貼り直しになる。

## 方式A: 環境変数（推奨）

一度設定すれば、どのターミナル・どのプロジェクトからも読める。

### PowerShell（履歴に残らない書き方）

```powershell
$k = Read-Host "DeepSeek API Key" -AsSecureString
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY',
  [System.Net.NetworkCredential]::new('', $k).Password, 'User')
```

入力は画面に出ず、コマンド履歴にも残らない。

### 簡易版

```powershell
setx DEEPSEEK_API_KEY "sk-..."
```

手軽だが、キーがコマンド履歴とスクロールバックに残る。個人PCで気にしないならこれでよい。

### 設定後は必ずターミナルを閉じて開き直す

**起動済みのプロセスには新しい環境変数が届かない。** Claude Code、VS Code、
Git Bash など、開いているものは全部再起動する。ここでつまずくことが最も多い。

値を表示せず存在だけ確認:

```powershell
if ([string]::IsNullOrWhiteSpace($env:DEEPSEEK_API_KEY)) { 'unset' } else { 'set' }
```

Git Bash なら:

```bash
test -n "$DEEPSEEK_API_KEY" && echo set || echo unset
```

## 方式B: ファイル

プロジェクトごとにキーを使い分けたい場合、または環境変数を汚したくない場合。

v2.0.0以降はfallbackしない。起動時の`--auth-channel`で次の1箇所だけを選ぶ。

1. `home-file`: `~/.deepseek/api_key` — 全プロジェクト共通
2. `repo-file`: `<リポジトリルート>/.deepseek/api_key` — `.git` を上に辿る
3. `cwd-file`: `./.deepseek/api_key` — カレントディレクトリ

### 作り方（PowerShell）

```powershell
$dir = "$env:USERPROFILE\.deepseek"       # プロジェクト単位ならリポジトリルートに変更
New-Item -ItemType Directory -Force $dir | Out-Null

$key = Read-Host "DeepSeek API key" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($key))

# 末尾改行もBOMも付けずに書く
[IO.File]::WriteAllText("$dir\api_key", $plain.Trim(),
    (New-Object Text.UTF8Encoding $false))
```

`Set-Content`（`-NoNewline` なし）や `>` でのリダイレクトは BOM や CRLF を付けることがある。
スクリプト側で除去はしているが、確実なのは上の `WriteAllText` 方式。

### Git Bash から作る場合

```bash
mkdir -p ~/.deepseek
read -rs -p "DeepSeek API key: " k && printf '%s' "$k" > ~/.deepseek/api_key && echo
chmod 600 ~/.deepseek/api_key
```

### Gitに載せない

リポジトリ内に置くなら `.gitignore` に追加する。

```
.deepseek/
```

## 確認

```bash
cd "<project-root>"
python "C:/Users/ryufu/.claude/skills/deepseek-api/scripts/ds_ask.py" \
  --check --model deepseek-v4-pro --effort high --max-tokens 16 \
  --expect-client-version 2.0.0 --sandbox text-only \
  --network deepseek-api-only --auth-channel env \
  --attestation-out "docs/handoffs/out/D0_deepseek_check.json"
```

`OK: authenticated. models available: ...` が出れば完了。file方式なら
`--auth-channel`を該当channelへ変える。`python`が無ければ同じ絶対pathを`py -3`へ渡す。

## キーの更新・失効

DeepSeekのコンソールで既存キーを Delete → 新規発行 → 上の手順で上書き。
環境変数を更新した場合は、やはりターミナルを開き直すこと。

漏らした可能性があるときは、迷わず Delete して作り直す。無料で即座に無効化できる。

---
name: cursor-grok
description: CodexからCursor CLI経由でGrok 4.6、Kimi K3、GLM 5.2、Gemini、GPT系モデルへ自己完結した質問を送り、回答を取得・保存する。このWindows環境ではCursorサブスクリプションのログインを利用し、APIキーは不要。「Grokに聞いて」「Grokで検証」「Cursorのモデルで」「Kimiに」「GLMに」「Geminiに」「別モデルの意見」「セカンドオピニオン」「第三の視点」などの依頼や、cursor-agentの認証・パス・Workspace Trust・タイムアウト問題の診断に使う。
---

# CodexからCursorモデルを呼ぶ

Skill同梱の `scripts/invoke_cursor_agent.ps1` をCodexの `exec_command` で実行する。Claude用MCPサーバーや `mcp__cursor__*` は使わない。

## 標準手順

1. 各ターン最初の呼び出し前に状態を確認する。

```powershell
& 'C:\Users\ryufu\.codex\skills\cursor-grok\scripts\invoke_cursor_agent.ps1' -Action status
```

2. 質問を自己完結させる。Cursor側にはCodexの会話履歴もプロジェクトファイルも見えないため、必要なコード、エラー、制約をプロンプトへ含める。秘密情報は含めない。
3. 用途に合うモデルを選んで実行する。軽い確認は `medium`、難しい設計・根本原因分析は `xhigh` を使う。

```powershell
& 'C:\Users\ryufu\.codex\skills\cursor-grok\scripts\invoke_cursor_agent.ps1' `
  -Action ask `
  -Model 'cursor-grok-4.6-xhigh' `
  -Prompt 'ここに自己完結した質問' `
  -OutFile 'C:\absolute\path\cursor-response.md'
```

4. 終了コード、標準出力、保存ファイルを確認してから回答をユーザーへ伝える。モデル回答を事実として盲信せず、コードや設定に関する主張は手元の証拠と照合する。

長い呼び出しでは `exec_command` の `yield_time_ms` を最大30秒程度にして、セッションIDが返ったら `write_stdin` で追跡する。スクリプト側の既定タイムアウトは600秒。必要な場合だけ `-TimeoutSeconds` を変更する。

## コマンド

### 状態と認証

```powershell
& 'C:\Users\ryufu\.codex\skills\cursor-grok\scripts\invoke_cursor_agent.ps1' -Action status
```

Cursorのログイン状態、解決されたcursor-agentの版とパスを確認する。未ログインなら、ユーザー自身にCursorでログインしてもらう。APIキーを要求しない。

### モデル一覧

```powershell
& 'C:\Users\ryufu\.codex\skills\cursor-grok\scripts\invoke_cursor_agent.ps1' -Action models -Filter 'grok'
```

`models` の一覧は不完全な場合がある。既知のIDが一覧に出なくても、実行時に受理されれば利用できる。無効IDはエラーになる。

### 質問

```powershell
$prompt = @'
目的、入力、制約、必要な出力形式をここへ書く。
'@
& 'C:\Users\ryufu\.codex\skills\cursor-grok\scripts\invoke_cursor_agent.ps1' -Action ask -Model 'cursor-grok-4.6-xhigh' -Prompt $prompt
```

プロンプトに複雑な引用符や改行がある場合はPowerShellのヒアストリングを使う。シェル文字列へ無理にエスケープしない。

## 主要モデル

モデルIDはCursor側で変わり得るため、エラー時は `-Action models` と実際のエラーメッセージを優先する。

- `cursor-grok-4.6-low`: 軽い確認
- `cursor-grok-4.6-medium`: 通常
- `cursor-grok-4.6-high`: 詳細な検討
- `cursor-grok-4.6-xhigh`: 最大推論。難所、設計判断、根本原因分析
- `kimi-k3-max` / `kimi-k3-high`
- `glm-5.2-max` / `glm-5.2-high`
- `gemini-3.1-pro`
- `gpt-5.4-xhigh`

Grok以外をユーザーが明示した場合は、そのモデルファミリーを選ぶ。モデル指定が曖昧な「別モデルの意見」では、まずGrok 4.6を使う。

## 安全性と分離

`cursor-agent --trust` はファイル操作・コマンド実行を許す。ラッパーは必ず空の一時ディレクトリを作業ディレクトリとして使い、終了後に削除する。プロジェクトを直接読ませるために作業ディレクトリを変更しない。必要な情報だけをプロンプトへ含める。

## トラブルシューティング

- `cursor-agent versions directory was not found`: Cursorを起動・更新し、Cursor Agentがインストールされているか確認する。
- `No cursor-agent version`: Cursor更新後、同梱Agentが展開されているか確認する。版パスをハードコードしない。
- 認証エラー: `-Action status` を実行し、Cursorアプリ側でログインする。
- Workspace Trustで停止: ラッパーを使う。ラッパーは `--trust` と空の一時ディレクトリを設定する。
- タイムアウト: `-TimeoutSeconds 900` などへ延長する。xHighは数分かかることがある。
- 応答が途中で切れる: `exec_command` がセッションIDを返した場合は `write_stdin` で完了まで待つ。必要なら `-OutFile` へ保存する。
- 文字化け: ラッパーはUTF-8で標準出力と保存を行う。呼び出し側で別エンコーディングへ変換しない。

## 関連Skill

- `deepseek-api`: DeepSeek APIによる別系統の意見取得

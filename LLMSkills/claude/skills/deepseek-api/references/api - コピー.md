# DeepSeek API リファレンス（2026年8月時点）

`ds_ask.py` が内部で使っている仕様。スクリプト経由で足りるなら読む必要はない。
自前でリクエストを組む・挙動が想定と違う、というときに参照する。

出典: https://api-docs.deepseek.com （2026-08-18 確認）

## モデル

| ID | 実体 | 文脈長 | 最大出力 |
|---|---|---|---|
| `deepseek-v4-pro` | DeepSeek-V4-Pro-0813 (GA 2026-08-13) | 1M | 384K |
| `deepseek-v4-flash` | DeepSeek-V4-Flash-0731 (GA 2026-07-31) | 1M | 384K |

IDは常に最新スナップショットを指すエイリアス。

**旧IDは死んでいる。** `deepseek-chat` / `deepseek-reasoner` は 2026-07-24 15:59 UTC で
完全廃止。移行期間中は v4-flash にルーティングされていたが、現在はもう繋がらない。
古いコードやブログ記事を参考にすると、ここで詰まる。

## エンドポイント

- ベース: `https://api.deepseek.com`（**`/v1` は付けない**。付けても通る場合があるが
  公式ドキュメントの記載は無印なので、こちらに合わせる）
- Anthropic互換: `https://api.deepseek.com/anthropic`
- ベータ機能（prefix completion等）: `https://api.deepseek.com/beta`
- `POST /chat/completions` / `GET /models`
- 認証: `Authorization: Bearer <key>`

## リクエスト

必須は `model` と `messages` のみ。主なパラメータ:

| フィールド | 既定 | 備考 |
|---|---|---|
| `thinking` | `{"type":"enabled"}` | **思考モードは既定でON** |
| `reasoning_effort` | `high` | `low` / `high` / `max` |
| `max_tokens` | 不明（明示推奨） | 入力+出力が文脈長に収まる範囲 |
| `temperature` | 1 | **思考モードでは無視される** |
| `top_p` | 1 | 同上 |
| `stop` | — | 最大16個 |
| `response_format` | `{"type":"text"}` | `json_object` 可 |
| `tools` | — | 最大128関数。思考モードでも使える |
| `frequency_penalty` / `presence_penalty` | — | **非推奨**。移植コードからは削除する |

### 落とし穴: パラメータの黙殺

思考モードで `temperature` を送っても **200が返り、静かに無視される**。警告は出ない。
効かせたいなら `"thinking": {"type": "disabled"}` を明示すること。
`ds_ask.py` は `--no-thinking` のときだけ `temperature` を送るようにしてある。

## レスポンス

```
choices[0].message.content            回答本文
choices[0].message.reasoning_content  思考過程（思考モード時、両モデルで返る）
choices[0].finish_reason              stop / length / content_filter / tool_calls /
                                      insufficient_system_resource
usage.prompt_cache_hit_tokens / prompt_cache_miss_tokens
usage.completion_tokens_details.reasoning_tokens
```

### 落とし穴: マルチターンでの reasoning_content

- **通常の会話**では、次のターンに `reasoning_content` を含める必要はない
- **tool calling を使う場合は、含めて返さないと壊れる**。全後続ターンで渡し続ける

逆にすると agent ループが静かに劣化する。ここは間違えやすい。

## エラー

| コード | 意味 | 対処 |
|---|---|---|
| 400 | リクエスト形式不正 | ボディを直す |
| 401 | 認証失敗 | キーの空白・改行・BOMを疑う |
| 402 | 残高不足 | チャージ |
| 422 | パラメータ不正 | メッセージに従う |
| 429 | 同時実行数超過 | **待つのではなく並列数を減らす** |
| 500 / 503 | サーバ側 | リトライ |

レート制限は RPM/TPM ではなく**同時実行数**ベース。v4-pro は500、v4-flash は2,500。
アカウント単位（APIキーをまたいで合算）。

## 料金（USD / 100万トークン）

| モデル | キャッシュヒット入力 | ミス入力 | 出力 |
|---|---|---|---|
| v4-flash ピーク | $0.014 | $0.44 | $1.32 |
| v4-flash オフピーク | $0.007 | $0.22 | $0.66 |
| v4-pro ピーク | $0.044 | $1.32 | $3.96 |
| v4-pro オフピーク | $0.022 | $0.66 | $1.98 |

**ピークは 01:00-04:00 と 06:00-10:00 UTC のみ**（＝JST 10:00-13:00 と 15:00-19:00）。
残り17時間はオフピークで半額。2026-08-16 から適用。急ぎでない大量処理は
JST夜間〜早朝に回すと半額になる。

## プロンプトキャッシュ

自動。コード変更不要。入力の先頭からの完全一致プレフィックスが対象で、部分一致は効かない。
**システムプロンプトや長い資料を先頭に置き、呼び出し間で1バイトも変えない**のがコツ。
効果は `usage.prompt_cache_hit_tokens` で確認できる。数時間〜数日で自動失効。

## JSON出力

`response_format: {"type":"json_object"}`。条件が2つある:

1. system か user のプロンプトに **"json" という単語を含める**
2. **期待するJSONの例を書く**

満たさないと空文字が返ることがある（公式に既知の問題として記載あり）。
`max_tokens` が小さいと途中で切れて壊れたJSONになるので、余裕を持たせる。

## 長時間リクエスト

- ストリーミング時は `: keep-alive` コメント、非ストリーミング時は空行が
  流れ続ける。JSONパースには影響しない仕様だが、素朴なアイドルタイムアウトは
  長い推論を殺す。`ds_ask.py` は既定900秒。
- 10分間推論が開始しない場合、サーバ側から接続を切られる。

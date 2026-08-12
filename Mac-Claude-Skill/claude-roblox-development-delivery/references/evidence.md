# 実測値とEvidence

このワークフローで最も壊れやすいのは「測っていない値を書いてしまうこと」。一度創作値が入ると、それ以降の検証がすべて無意味になる。

## 実測しないなら書かない

hash・ID・バージョン・URL・errno・件数は、実際に取得したものだけを書く。取得できないなら `[OPEN] blocking: yes|no` として残し、誰がいつ取得するかを書く。

```markdown
> **[OPEN] blocking: no** — <値の名前>は現時点で未取得。<誰が><いつ><どうやって>取得し、<どこへ>登録する。取得前に値を創作またはplaceholder化しない。
```

`blocking: yes` なら進捗記録のblocker欄へも登録する。片方だけだと追跡が切れる。

実運用の例: 5つのツールの期待バイナリhashが未取得だった。placeholderを入れず `[OPEN] blocking: no` として、セットアップ工程で実測してから登録した。照合はこれを「P0開始を妨げない」と判定した。正直に未取得と書いたから、正しく判定できた。

## 値の取得と受け渡し

Fableが実測し、FACTとしてhandoffへ渡す。Codexは渡された値だけを使う。

```bash
shasum -a 256 <file>                    # ファイルhash
<tool> --version                        # バージョン
curl -s <API> | python3 -c "..."        # リリースasset情報
```

ツールのバイナリhashを取るときは、**実際に実行されるバイナリ**を測る。ラッパーやランチャーではない。実運用で、`~/.rokit/bin/` 配下の5つのツール名がすべて同一のランチャー（同じhash）で、実体は別ディレクトリにあった。ランチャーをhashしても、実体は拘束されない。

```bash
find ~/.rokit/tool-storage -type f -perm +111 | while read p; do
  printf "%s  %s\n" "$(shasum -a 256 "$p" | cut -c1-64)" "${p#$HOME/.rokit/tool-storage/}"
done
```

## Evidenceの記録

テスト実行の証跡は、後から独立に検証できる形で残す。含めるもの:

- 対象commit または未commit識別子
- 実行環境（OS・ツールバージョン・Studioバージョン）
- 入力のhash（fixture・config・artifact）
- 出力（生ログと、そのhash）
- 判定結果（各項目のPASS/FAIL）
- 実行時刻

生ログは改変せず保存し、hashを取る。要約だけを残すと、後から「本当にそう出ていたか」を確認できない。

## PII

プレイヤーIDやサーバーのジョブIDは生のまま保存しない。ドメイン分離したハッシュにする。

- saltは実行時に生成し、artifactへ保存しない
- ドメイン文字列を含めて、他用途のhashと衝突しないようにする
- 固定のalias（`PLAYER-1` 等）で代用しない — 匿名化になっていないうえ、同一性の証明にもならない

実運用で、固定aliasだけを記録していたEvidenceが照合で差し戻された。ハッシュに変えて再実行した。

## 決定論

同じ入力から同じ出力が出ることを確認する。2回実行してhashが一致すれば、生成に非決定的要素が混ざっていない。

```bash
<generate command>
shasum -a 256 <output> > /tmp/h1
<generate command>
shasum -a 256 <output> > /tmp/h2
diff /tmp/h1 /tmp/h2 && echo deterministic
```

一致しないなら、時刻・乱数・イテレーション順序・絶対パスのいずれかが混ざっている。

## 不変性の記録

「変えてはいけないもの」は、hashを記録して各段階で照合する。golden fixture、承認済み設定、生成物のcontentHashなど。

commitメッセージにも実測値を書いておくと、後から履歴だけで追跡できる。

```
- config/data-registry.resolved.json: contentHash a7f2aedf…（独立3経路で再計算一致）
- 3 build決定論(2連続hash一致): Lobby 5cf0507b… / Run 7e5ef039… / StudioTest dac1fc73…
```

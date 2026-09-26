# 形式確認と出典範囲

## 方法の由来
ユーザーとの本対話における問題再定義・切り口変更・Roblox比較の議論と、既存の `problem-redefinition-skill/SKILL.md`、`references/reframing-lenses.md`、`references/scoring-rubric.md` をもとに改訂した。
方法の名称、分類、レンズ、採点重みは、この作業用に構成した枠組みである。
普遍的に検証された学術モデルや、特定企業の秘密の開発手法として提示しない。

既存Skillの主要な内容は保持しつつ、二項目ルール、ゲームへの支払者ゲート、橋渡し資産の必須化、比較時の案数強制などを見直した。

## パッケージ形式
2026-09-17確認。
Agent Skills仕様は、Skillフォルダ内のSKILL.mdにYAMLフロントマターと手順を置き、name/descriptionを必須とする形式を示している。
本版は参照資料を分割し、Skill名とフォルダ名を一致させている。

```text
https://agentskills.io/specification
```

OpenAIのBuild skills資料は、SKILL.mdに加えて任意の参照資料とagents/openai.yamlを使う構成、およびCodexのローカル探索先として .agents/skills を説明している。
これは配置例の根拠であり、ユーザーの環境に配置・登録済みであることを示さない。

```text
https://developers.openai.com/codex/skills/
https://learn.chatgpt.com/docs/build-skills
```

## 実作品の資料
今回の目的は方法の改訂であり、ゲーム各作の比較調査をやり直すことではない。
Roblox公式のゲームページと開発者紹介ページへの再取得を試みたが、今回取得された表示からは、教材内の個別仕様や開発意図を十分に再確認できなかった。
そのため実名を含む例題を、現行事実の検証済みケースへ昇格させていない。
この状態を開発者発言が存在しない証拠としても扱わない。

以下は再調査の入口であって、教材の全主張を支持する確認済み出典ではない。

```text
https://devforum.roblox.com/t/creator-spotlight-the-story-behind-99-nights-in-the-forest/4036940
https://www.roblox.com/games/79546208627805/99-Nights-in-the-Forest
https://www.roblox.com/games/116495829188952/Dead-Rails
```

Steal An Eggについては今回同定・仕様・順位の調査を完了しておらず、未確認事例の処理を学ぶためにのみ収録した。
タイミーの例はユーザーの提示した用途解釈で、企業史や法的助言ではない。

## テストの意味
構文・参照・配布の検査は、手順を読めるパッケージになっているかの検査。
例題セルフチェックは、作成した方法に矛盾がないかの点検。
実際のゲーム人気への効果、独立モデルでの再現率、特定アプリへの登録は未検証。

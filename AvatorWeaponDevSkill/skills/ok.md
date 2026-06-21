---
description: ユーザーが「OK」とだけ投稿したら、Stageにある差分を全てコミット・Pushする
---

# OK — Git Commit & Push

ユーザーが「OK」とだけ投稿した場合に実行する。

## 手順

// turbo-all

1. ステージされている変更を確認する
```bash
cd /Users/furunoryuutarou/Documents/GitHub/WorldMealGuessor2 && git status
```

2. ステージされた差分の概要を表示する
```bash
cd /Users/furunoryuutarou/Documents/GitHub/WorldMealGuessor2 && git diff --cached --stat
```

3. ステージされた変更をコミットする（コミットメッセージは変更内容から自動生成）
```bash
cd /Users/furunoryuutarou/Documents/GitHub/WorldMealGuessor2 && git commit -m "<変更内容を要約したメッセージ>"
```

4. リモートにプッシュする
```bash
cd /Users/furunoryuutarou/Documents/GitHub/WorldMealGuessor2 && git push
```

## 注意事項

- ステージされた変更がない場合は「ステージされた変更がありません」と報告して終了する
- コミットメッセージは英語で、変更内容を簡潔に要約する
- pushに失敗した場合はエラー内容を報告する

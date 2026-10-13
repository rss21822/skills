# 検証

## 1. Lune
- テンプレートテストをゲームへコピーし `ROOT` をゲームのコピーへ: `lune run <path>/test_tutorial_templates.luau <copied-assets-dir>/`。全ケース合格（初回のみ・テスター・返却・段階・検出の契約）。
- ゲームの設定で `Config.validate()` が true（basics あり、端末 3 種の prompt、テスター Id が整数、救済秒数）。
- ゲーム固有: ステージ順、server ステージが serverEvent でだけ進む、完了で記録、受け渡し。

## 2. Studio Play（roblox-dev-skill の手順）
1. 自分の UserId を `TESTER_USER_IDS.studio` へ → Play 2 回 → **2 回とも出る**。
2. テスターから外し、メモリストアに `{ v = 1, starts = 1, completedAt = 1 }` → Play → 出ない。
3. 一覧外・記録なし → 出る、途中で Stop → 記録 starts 1（再 Play で同じストアなら出ない）。
4. 各ステップを実入力で: キーボード、Device Simulator のタッチ、可能ならゲームパッド。文言が端末で切り替わるか。
5. 何もしない → 救済で進む。
6. 初成功をサーバーが検出 → complete → 記録 completedAt。
7. スクリーンショット: HUD に馴染むか、トップバー・スティック・ジャンプを隠していないか、スマホ幅で収まるか。

## 3. 公開環境
DataStore・テレポート・JoinData は公開ゲームでしか本物にならない。staging（publish-roblox-private-staging）で: 新規アカウント 1 回目出る / 2 回目出ない / テスター毎回出る / 試合から帰っても出ない。Studio の結果を本番 OK と報告しない。

## 4. 報告
テスト数、Studio で入力したこと、スクショ、未検証、Owner 作業（テスター UserId と環境、チュートリアル PlaceId、公開、RTBF 対象追加）。

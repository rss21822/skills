# SpinOut の事例（2026-10）

- ゲーム: 氷上で回転して相手を弾き出す対戦。移動は独自のスケート（最低速度あり、止まれない）。Lobby / Classic / Death Ball の 3 Place。
- 専用の Tutorial Place（Classic のコピー、Classic のエンジンで動かす）。ロビーが予約サーバーへ一人ずつ送る。
- ステージ: welcome（2 枚のカード）→ basics（W/A/S/D を順に、押し続けの秒数で判定）→ spin_guide（スピン 2 回、サーバーが PASpinStartedAt で数える）→ spin（周回するだけの NPC 1 体を倒す）→ complete（Result → ロビーへ自動帰還）。
- basics 中はラインアウトを無効化し、ラインを越えたら開始地点へ戻す（止まれない移動で新規が落ち続けたため）。
- 初回判定: プロフィールの試合数 0 かつ記録 `SpinOut_Rivals_<env>_v1_tutorial` に開始なし。MAX_STARTS 1、開始は送信前に数え、確実な送信失敗のみ返却。
- テスター: `TUTORIAL_TESTER_IDS`（環境別）。毎ログイン送る、記録は読み書きしない。
- 文言は英語ソース（UI 文字列の 97% がラテン文字）。当初日本語で書いて直した。
- UI: 当初 AI 既定風のカード → 試合 HUD / Result の部品で作り直した（変更はチュートリアル Place だけに限定）。
- 教訓: 文脈を読まずに作ると操作・言語・UI が全部ずれる。毎回表示フラグではなくテスター一覧。PlaceId 未設定（0）の間は送り出しを無効に。

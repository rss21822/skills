# Robloxゲームフォーマット・カタログ

添付資料「Robloxテンプレートゲームフォーマット総覧 2026」の各ゲームカテゴリ表にある「フォーマット」列を基礎に、Web追加調査で確認した再利用可能なゲーム文法を加え、選定に必要な最小限の意味とともに整理したもの。合計141件。IDとフォーマット名を合成素材の正式表記として使用する。

命名テンプレートW01〜W39は原資料の列名が「命名テンプレート」であり、本カタログの合成素材には含めない。

## 目次

- [1. 脱出・移動・Obby系（T01〜T12）](#1-脱出移動obby系t01t12)
- [2. サバイバル・ホラー・危機系（S01〜S16）](#2-サバイバルホラー危機系s01s16)
- [3. 成長・収集・Incremental系（I01〜I18）](#3-成長収集incremental系i01i18)
- [4. Tycoon・建築・経営系（Y01〜Y14）](#4-tycoon建築経営系y01y14)
- [5. 対戦・短ラウンド・競技系（P01〜P18）](#5-対戦短ラウンド競技系p01p18)
- [6. Roleplay・社会・自己表現系（R01〜R14）](#6-roleplay社会自己表現系r01r14)
- [7. RPG・冒険・戦略系（G01〜G16）](#7-rpg冒険戦略系g01g16)
- [8. Party・Puzzle・Physics系（C01〜C19）](#8-partypuzzlephysics系c01c19)
- [9. 車両・職業・現実Sim系（V01〜V14）](#9-車両職業現実sim系v01v14)

## 1. 脱出・移動・Obby系（T01〜T12）

場所や障害を通過することを主目的にする器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| T01 | チェックポイントObby | 障害を越え、チェックポイントから再挑戦しながら先へ進む |
| T02 | テーマ型Escape Obby（Escape X） | 病院、学校、店などの舞台を一本道Obbyと追跡で脱出する |
| T03 | Prison Run／追跡NPC Obby | 追跡者から逃げつつ施設を抜け、安全地帯や章ボスへ進む |
| T04 | 速度育成Escape | 移動で速度を育て、その速度でレースまたは脱出を突破する |
| T05 | Wave／Tsunami Escape | 波が来る前に前進・収集し、安全地帯へ持ち帰る |
| T06 | Dig to Escape | 掘って通路や資源を得て、さらに深く進み脱出する |
| T07 | Vertical Tower／Climb & Jump | 上方向へ登り、落下リスクに耐えて高度を更新する |
| T08 | No-checkpoint Timed Tower | チェックポイントなしで連続障害と制限時間に挑む |
| T09 | Teamwork／Chained Obby | 別役割、同時操作、救助を同期して複数人で進む |
| T10 | Dropper | 落下中に障害を避け、着地点を狙って階層を進む |
| T11 | Cart Ride／Ride Down | 乗り物の物理事故を楽しみながらコースを下る |
| T12 | 技法Parkour／Wall Hop | 特定の移動技術を練習し、連続成功やタイムを証明する |

## 2. サバイバル・ホラー・危機系（S01〜S16）

敵、災害、異変、資源不足などの危機へ判断と協力で対処する器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| S01 | Killer Chase Survival | 怪物から逃げ、隠れ、救助しながら制限時間まで生存する |
| S02 | 非対称Escape（1 vs Many） | 少数の強者と多数の弱者が異なる目的で捕獲、救助、解除を争う |
| S03 | Hide and Seek | 準備後に隠れる側と探す側へ分かれ、発見か時間切れを競う |
| S04 | Infection | 倒された人間が敵側へ移り、感染拡大と最後の生存を争う |
| S05 | Disaster Survival | 毎ラウンド変わる災害を予測し、安全地帯を判断して耐える |
| S06 | Overnight in X | 特定施設で準備、修理、隠密を行い夜襲を越えて朝を迎える |
| S07 | Nights Expedition／Base Defense | 昼に探索・運搬・建築し、夜に拠点を防衛して日数を伸ばす |
| S08 | Job × Anomaly Shift | 日常業務をこなしながら異変を判定・対処し、シフトを継続する |
| S09 | Rooms／Corridor Run | 連続する部屋で敵ギミックを学び、探索と回避で次の扉へ進む |
| S10 | Mascot Task Horror | キャラクター世界で共同作業、敵回避、救助を繰り返し階層を進む |
| S11 | Wave Defense／Last Stand | 準備、敵Wave、修理・強化、Bossを繰り返して耐え抜く |
| S12 | Road Trip Survival | 乗り物で前進し、停車して探索・修理・物資回収して再出発する |
| S13 | Extraction／Loot & Return | 危険地帯へ侵入し、撤退判断に成功したときだけ戦利品を持ち帰る |
| S14 | Apocalypse／Open-world Survival | 広域世界で食料、武器、拠点を整え、襲撃や対人危機を生き延びる |
| S15 | Raft／Sea Survival | 水上で資源を回収し、限られた足場を拡張して航行・生存する |
| S16 | Random Event／Stay Inside | 予測不能な短い危機イベントへ連続して判断・対処する |

## 3. 成長・収集・Incremental系（I01〜I18）

反復、発見、希少性、数値成長、自動化で長期の進行を作る器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| I01 | Zone-unlock Simulator | 作業、通貨、能力強化を繰り返し、新しいZoneを解放する |
| I02 | Training／Clicker | 同じ訓練行動を反復して能力値を上げ、次の相手へ挑む |
| I03 | +1 per Action | 歩く、跳ぶ、押すなどの行動ごとに数値が増え、競争や障害へつながる |
| I04 | Rebirth／Prestige | 進行をリセットして恒久倍率を得て、より速く再走する |
| I05 | Incremental／Idle | 小さな収入を自動化と倍率へ変え、指数的な桁更新を楽しむ |
| I06 | RNG／Aura Roll | Rollで低確率の希少結果を引き、装備・展示して再び狙う |
| I07 | Pet／Egg Hatching | 卵からペットを集め、編成効率を上げて次世界へ進む |
| I08 | Fishing Collection | 場所を選んで釣り、鑑定・売却・図鑑と装備更新を進める |
| I09 | Mining／Digging | 地面や鉱床を掘り、容量・ツールを強化して深層へ進む |
| I10 | Catch／Tame | 世界で対象を発見・捕獲し、育成・編成して新地域へ進む |
| I11 | Card／Unit Collection | カードやユニットを集め、デッキ編成を対戦またはPvEで試す |
| I12 | Craft／Merge／Evolution | 素材を組み合わせ、製作・合成・進化で上位物や図鑑を作る |
| I13 | Loot／Equipment Farm | 戦闘や箱から装備を得て比較・更新し、高難度へ挑む |
| I14 | Garden／Farm／Offline Growth | 植えて待ち、成長や変異を収穫して再投資する |
| I15 | Factory／Automation | 採取から機械、物流、自動化へ置換し、生産網を拡張する |
| I16 | Grow／Eat／Size | 食べる・吸収するほど巨大化し、新しい対象や形態を解放する |
| I17 | Find the X／Badge Hunt | 世界を探索・推理・踏破して隠し対象を発見し、Badgeと図鑑を埋める |
| I18 | Auction／Bid Collection | 他プレイヤーとの入札で収集物を落札し、収益・図鑑・再投資へつなぐ |

## 4. Tycoon・建築・経営系（Y01〜Y14）

所有、建築、運営、可視化された成長を主役にする器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| Y01 | Classic Button Tycoon | 収入で購入パッドを踏み、設備と自動収入を段階的に増やす |
| Y02 | 2 Player Tycoon | 2人が別役割の収入と設備を担当し、一つの基地を共同成長させる |
| Y03 | War／Base Tycoon | 基地を育てて武器・車両を解放し、他基地の攻撃や占領へ進む |
| Y04 | Business／Restaurant Tycoon | 注文、調理・提供、収入、内装・雇用で店舗を成長させる |
| Y05 | Dealership／Sales Management | 商品を仕入れ、陳列・販売し、在庫と店舗を拡張する |
| Y06 | Build a X → Test | 自作物を建築し、走行・航行などで試し、失敗を受けて改造する |
| Y07 | Build & Survive | 準備時間に建築し、その結果で敵や災害の危機を耐える |
| Y08 | Theme Park／Coaster／Waterpark | 娯楽施設を設計し、来客・収益・評価で土地とテーマを広げる |
| Y09 | Industrialist／Production Chain | 原料、加工、搬送、市場の複数工程を最適化して拡張する |
| Y10 | City／Empire Builder | 資源から都市・領土を広げ、経済、外交、戦争を管理する |
| Y11 | Home／Property Builder | 仕事で資金を得て家や部屋を建て、生活・訪問・展示する |
| Y12 | Booth／Donation／Stand Economy | 自分の売り場で訴求・交流し、他者から支援や購入を得る |
| Y13 | My X Ownership Manager | 自分専用の施設・事業を所有し、運営・拡張・展示する |
| Y14 | Collect–Steal–Defend Base | 可視資産を拠点で収益化し、他者から盗み、自分の資産を守り奪い返す |

## 5. 対戦・短ラウンド・競技系（P01〜P18）

即再戦、技能習熟、短い勝敗、観戦性を作る器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| P01 | Ability Battlegrounds | 能力セットを選び、アリーナでコンボ・撃破・即復帰を繰り返す |
| P02 | RIVALS型Short-round | 1v1〜少人数で数分のラウンドを取り合い、即再戦する |
| P03 | X vs Y DUELS | 二分された武器・役割の極端に単純な対面条件で短く再戦する |
| P04 | Arena／FFA | 全員が同じ空間で撃破数を競い、連続復帰しながら戦う |
| P05 | One Tap／Sniper | 命中一発の索敵、精度、死亡・即復帰の緊張を競う |
| P06 | Gun Game／Weapon Rotation | 撃破ごとに武器が変わり、全武器の完走を競う |
| P07 | Tactical Team Shooter | 役割、情報、位置取りを重視してチーム目標とラウンド勝利を狙う |
| P08 | Murder Mystery／Hidden Role | 隠された役職の犯人行動、推理、逃走で誰を信じるかを遊ぶ |
| P09 | Social Deduction／Vote-out | 課題と事件の後、会話・投票で偽者を排除する |
| P10 | Parry Ball | 飛来物をタイミングよく返し、速度と対象を移して最後の1人を狙う |
| P11 | Boxing／Fighting Duel | 間合い、回避、コンボの読み合いで1対1のKOを競う |
| P12 | Ability Sports（Rivals／Zero／Legends） | スポーツの短試合を必殺技とスタイル収集へ変換する |
| P13 | Simulation Sports | 実際のパス、位置取り、役割技能を簡略再現して試合・戦績を競う |
| P14 | Base Objective／BedWars | 資源と装備を集め、自拠点を守りながら敵拠点を破壊する |
| P15 | Battle Royale | 大人数で降下・収集・戦闘し、縮小空間の最後の1人を狙う |
| P16 | Death Game／Multi-stage Elimination | 複数競技を勝ち抜き、脱落と観戦を経て決勝へ進む |
| P17 | Juggernaut／Player Boss | 選ばれた1人の強者と多数側が、時間または撃破条件を争う |
| P18 | Rhythm／Timing Battle | 楽曲に同期した入力精度とコンボを短試合で競う |

## 6. Roleplay・社会・自己表現系（R01〜R14）

役割、関係、生活、自己表現、創作物の共有を主役にする器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| R01 | Open City RP | 自由な街で家、車、役割を選び、会話と即興事件を作る |
| R02 | Life／Family RP | 家族、赤ちゃん、生活上の役割を選び、日常関係を即興する |
| R03 | Job／Institution RP | 学校、病院、店舗など一施設で職業、業務、昇進、会話を演じる |
| R04 | School／Classmate RP | 生徒、教師、友人として授業、放課後、学校事件を演じる |
| R05 | Emergency／Local City RP | 警察、消防、救急、市民が通報、出動、処理を分担する |
| R06 | Creature／Animal RP | 人間以外の種として成長、群れ、捕食、巣、生態関係を演じる |
| R07 | Fandom／IP Character RP | ファンダムのキャラクター、能力、場面を使い即興する |
| R08 | Avatar Catalog／Creator | 衣装を検索・試着・保存し、撮影・共有・購入する |
| R09 | Dress Theme + Vote | お題と制限時間に合わせて着替え、ランウェイと相互投票で競う |
| R10 | Hangout／Voice／Chat | 小さな空間で会話と軽い遊びを通じて関係を作る |
| R11 | Clip／Movie／UGC Creation | アバターと場面を設定し、ゲーム内の短尺作品を撮影・共有する |
| R12 | Makeover／Build & Vote | 個人または共同制作した結果を展示し、他者の投票で競う |
| R13 | In-experience Creator Sandbox／Publish & Play | ゲーム内で作品や小ゲームを作り、公開し、他者が遊び評価する |
| R14 | Player Marketplace／Trade & Negotiate | 所有物の価値を比較し、交渉・交換・売買でCollectionを更新する |

## 7. RPG・冒険・戦略系（G01〜G16）

長期キャリア、探索、戦闘ビルド、物語、領土判断を作る器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| G01 | Anime Open-world Grind RPG | クエストとBossを反復し、能力・装備・地域を長期解放する |
| G02 | Piece／Seas RPG | 島を航海し、クエスト、能力、剣、船で海域を進む |
| G03 | Dungeon Crawler | 部屋戦闘とBossからLootを得る短いダンジョンを周回する |
| G04 | Raid／Boss Farm | 編成とギミック攻略で大型Bossを反復討伐し、希少Dropを狙う |
| G05 | Story／Chapter Adventure | 章ごとの演出、選択、謎、Bossを進めて物語と分岐を解放する |
| G06 | Roguelite Dungeon | 部屋ごとの選択でラン内ビルドを変え、死亡後のMeta解放へつなぐ |
| G07 | Soulslike／Permadeath RPG | 損失リスクと高技能の探索・戦闘で長期キャリアを作る |
| G08 | Turn-based／Retro Story RPG | 探索、コマンド戦闘、会話を通じて仲間と物語を進める |
| G09 | Cultivation／Reincarnation | 修練、突破、転生を繰り返し、境界や血統の階層を上がる |
| G10 | Tower Defense | 経路へユニットを配置・強化し、WaveとBossを止める |
| G11 | World Conquest／Territory Strategy | 国家の経済、軍、外交を操作し、領土と時代を拡大する |
| G12 | Survival Craft | 素材採集、Craft、建築、探索・戦闘で技術木と拠点を育てる |
| G13 | Heist／Co-op Mission | 装備と役割を準備し、侵入、目的達成、脱出を協力して遂行する |
| G14 | Open-world Action Quest | 移動能力と戦闘で広い世界を探索し、任務、装備、地域を進める |
| G15 | Multiple-Ending Micro-Adventure | 小さな舞台を反復探索し、行動順や選択を変えて短いEndingを集める |
| G16 | Versus Tower Defense／Send Waves | 自陣を防衛しながら敵Waveへ投資し、相手側の防衛崩壊を狙う |

## 8. Party・Puzzle・Physics系（C01〜C19）

短い事件、問題、投票、偶然、物理事故で新規流入と共有体験を作る器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| C01 | Minigame Rotation | 投票後に1〜3分の異なる競技を遊び、結果から次へ移る |
| C02 | Game Show／Outlaster | チーム課題と投票で脱落者を決め、統合と決勝へ進む |
| C03 | Teamwork Puzzle | 別情報・別操作を相談し、同時操作して協力問題を解く |
| C04 | Escape Room Puzzle | 閉鎖空間を探索し、暗号、鍵、仕掛けを解いて脱出する |
| C05 | Anomaly Spotting | 正常と異常を比較・報告し、連続正解で進行方向を選ぶ |
| C06 | Trivia／Logo／Knowledge | 知識問題へ素早く移動・選択し、正誤で得点または脱落する |
| C07 | Word／Spelling／Unscramble | 文字を組み、入力速度と語彙で得点・連勝を競う |
| C08 | Logic Puzzle（Minesweeper／Nonogram） | 既知の論理規則で盤面を推論し、完成、失敗、Daily記録を競う |
| C09 | Buckshot／Chance Duel | 少数の道具選択と確率で生死が反転する短い心理戦を行う |
| C10 | Fling／Physics Sandbox | 物を掴み投げ、他者と連鎖的な物理事故を起こす |
| C11 | Ragdoll／Knockout | 衝突、転倒、吹き飛び、場外で短い勝敗を決める |
| C12 | Ride／Slide／Bobsled | コースを滑走し、加速、事故、ゴール、再走を楽しむ |
| C13 | Draw／Build Physics | 描画や簡易建築を物理物体に変え、航行・落下で試して修正する |
| C14 | Destruction Spectacle | 破壊、爆発、落下の視覚報酬を反復し、より大きな対象へ進む |
| C15 | Lucky Block／Chance Event | 箱を壊し、予測不能な報酬または危機を受けて次へ進む |
| C16 | Idle Social Gag | 待つ・無駄な行動を共同体験し、小イベント、記録、会話を楽しむ |
| C17 | Draw & Guess | 1人の描画を他者が時間内に解読し、役割を交代する |
| C18 | Board／Dice & Minigame Party | 盤面状態を維持しながら移動、アイテム、短い競技を重ねて総合順位を争う |
| C19 | Hot Potato／Transfer Hazard | 時限危険物を他者へ渡し、時間切れ時の所持者だけが脱落する |

## 9. 車両・職業・現実Sim系（V01〜V14）

専門技能、地域性、現実の手順、車両操作、複数人の役割分担を作る器。

| ID | フォーマット | 中心となる約束 |
|---|---|---|
| V01 | Open-world Driving | 街を自由走行し、車の購入、仕事・レース、改造、展示を行う |
| V02 | Circuit／Street Racing | コースや公道で順位・タイムを競い、報酬で車を改造する |
| V03 | Highway Chase／Traffic Weaving | 高速道路の追跡、すり抜け、危険回避で速度や距離を競う |
| V04 | Offroad／Mudding | 泥、坂、牽引、スタックと救助を通じて地形走破を楽しむ |
| V05 | Flight Training／Flight World | 航空機を操作し、飛行、任務、着陸、機体解放を行う |
| V06 | Vehicle Combat／Multicrew | 一両・一艦の操縦、武器、修理を複数人で分担して戦う |
| V07 | Emergency Services Simulator | 通報、出動、現場処理を警察、消防、救急で協力して行う |
| V08 | Train／Transport／Local Simulator | 路線、時刻、停車、運転評価を地域の交通として再現する |
| V09 | Job／Work Shift Simulator | 現実の作業手順を受注、作業、品質・速度評価、昇進へ変える |
| V10 | License／Training Simulator | 講習、実技、採点、免許取得を経て上位技能や仕事を解放する |
| V11 | Delivery／Logistics | 荷物・人・資源を積み、経路を選び、安全・高速に納品する |
| V12 | Repair／Mechanic Simulator | 故障を診断、分解、部品交換し、試験で復旧を確認する |
| V13 | Vehicle Building Sandbox | 部品で乗り物を設計・組立・操縦し、破損を受けて改良する |
| V14 | Clean／Sort／Restore ASMR | 汚れや散乱を清掃・分類・再配置し、視覚的なBefore/Afterを完成させる |

## 選定時の読み方

- Primaryには、プレイヤーが最初の30秒から繰り返せるフォーマットを置く。
- Secondaryには、Primaryの結果を変える判断、成長、危機、物理、収集などを置く。
- 3つ目を使う場合は、社会構造または定着を担わせる。
- フォーマット名が複合語でも、表の1行を1フォーマットとして数える。
- 同名の一般ジャンルを自由に追加せず、ID付きの掲載形式とOriginal Spinを区別する。
- R14は自由交渉、価格発見、交換成立がPrimaryのときだけ使い、補助的なTrade機能や寄付中心のY12と区別する。
- V14は清掃・分類・再配置によるBefore／Afterが主報酬のときに使い、一般的な勤務手順のV09や故障診断中心のV12と区別する。

## 出典範囲

基礎資料: 「Robloxテンプレートゲームフォーマット総覧 2026」2026-08-03版、4〜12ページの各カテゴリ表。表の意味を保つため「即時約束」「コアループ」を短く統合している。

追加調査: 2026-08-12にRoblox公式資料、公式ゲームページ、現行チャートを既存129件と照合し、独立したPrimary Sessionとして再利用できる12件（I17〜I18、Y14、P18、R13〜R14、G15〜G16、C17〜C19、V14）を追加した。

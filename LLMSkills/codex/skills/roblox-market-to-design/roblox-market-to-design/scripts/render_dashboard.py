#!/usr/bin/env python3
"""Render research.json as an offline, read-only HTML dashboard. No network calls."""
from __future__ import annotations
import argparse
from html import escape
from pathlib import Path
import re
import sys
from typing import Any
from validate_research import SCHEMA, load_json, safe_url, validate

LABELS = {
 'project_title':'案件', 'project_slug':'保存用名称', 'started_at':'実行開始', 'timezone':'タイムゾーン',
 'mode':'モード','depth':'深度','status':'状態','research_scope':'調査範囲','capabilities':'利用可能な機能',
 'limitations':'制約・限界','unresolved':'未解決','concept':'企画','target_players':'対象者',
 'core_verbs':'コアの動詞','desired_emotions':'目指す感情','success_definition':'成功の定義',
 'fixed_constraints':'固定条件','preferences':'希望','hypotheses':'仮説','undecided':'未決',
 'input_materials':'入力資料','production_constraints':'制作条件','excluded':'採用しないもの',
 'title':'名称','publisher':'発行者','url':'出典URL','local_path':'ローカル資料',
 'published_at':'公開日時','retrieved_at':'取得日時','access_status':'閲覧状態','kind':'種別',
 'locator':'該当箇所','note':'注記','text':'主張','source_ids':'出典','supporting_claim_ids':'根拠の主張',
 'confidence':'確からしさ','confidence_reason':'その理由','alternative_explanations':'別の説明',
 'platform':'媒体','creator':'開発者','official_url':'公式URL','universe_id':'Universe ID',
 'root_place_id':'入口Place ID','identity_status':'同定状態','cohort':'比較群','selection_reason':'選定理由',
 'claim_ids':'関連する主張','metrics':'指標','design_notes':'設計メモ','name':'指標名','value':'値',
 'unit':'単位','definition':'定義','aggregation':'集計','provenance':'値の性質','observed_at':'観察日時',
 'period_start':'対象開始','period_end':'対象終了','population':'母集団','missing_reason':'欠損理由',
 'game_id':'ゲーム','method':'観察方法','context':'条件','observed':'観察したこと',
 'audience':'対象者','unmet_need':'未充足需要','current_alternatives':'現在の代替','barrier':'届かない理由',
 'legacy_value':'歴史から残す価値','why_now':'今の成立条件','execution_advantage':'制作上の強み',
 'evidence_claim_ids':'根拠の主張','counterevidence':'反証','decision_ids':'設計判断','test_ids':'検証',
 'question':'問い','options':'選択肢','recommended_option_id':'AIの推奨','approved_option_id':'ユーザー採用',
 'approval_evidence':'承認の根拠','reasoning':'判断理由','label':'選択肢','rationale':'理由',
 'tradeoffs':'副作用・トレードオフ','implementation_notes':'実装・運営の考慮',
 'premise':'前提','trigger':'引き金','player_action':'プレイヤーの選択','payoff':'画面・音の変化',
 'reaction':'反応','result':'結果','clip_value':'短尺で伝わる価値','naturalness':'自然に起きる条件',
 'risks':'リスク','hypothesis':'検証仮説','design':'試験設計','duration':'期間','criteria':'判断基準',
 'criteria_status':'基準の性質','guardrails':'守る条件','results':'実測結果','topic':'確認事項',
 'checked_at':'確認日時','findings':'確認内容','design_implications':'設計への意味',
 'category':'分類','mitigation':'対策','at':'日時','action':'実行内容','change':'変更',
 'affected_ids':'影響先','details':'詳細'
}
STATES = {'fact':'事実','interpretation':'解釈','hypothesis':'仮説','draft':'下書き',
 'partial':'一部確認','complete':'調査範囲の完了','proposed':'提案・未承認','approved':'承認済み',
 'rejected':'棄却','deferred':'保留','planned':'計画・未実施','running':'実施中','completed':'実施済み',
 'not_run':'未実施','unverified':'未確認','verified':'確認済み','conflict':'資料不一致',
 'accessed':'本文確認','provided':'提供資料','snippet_only':'要約のみ','inaccessible':'未取得',
 'public_observed':'公開観測','creator_reported':'制作者公表','third_party_estimate':'第三者推計',
 'authorized_internal':'許可済み内部データ','planning_assumption':'計画上の仮定','unavailable':'取得不可',
 'confirmed':'同定済み','provisional':'暫定','evidence_based':'根拠あり','user_specified':'ユーザー指定',
 'high':'高','medium':'中','low':'低','unknown':'不明'}
SECTIONS = [
 ('games','作品比較'),('observations','観察'),('opportunities','市場機会'),('decisions','設計判断'),
 ('hooks','SNSフック'),('tests','検証計画'),('claims','主張と根拠'),('sources','出典'),
 ('platform_checks','公式仕様の確認'),('risks','リスク')]


def h(value: Any) -> str:
    return escape(str(value), quote=True)


def render_value(value: Any, key: str = '') -> str:
    if value is None:
        return '<span class="unknown">未設定・未取得</span>'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return h(value)
    if isinstance(value, str):
        if key in ('url','official_url') and safe_url(value):
            return f'<a href="{h(value)}" target="_blank" rel="noopener noreferrer">{h(value)}</a>'
        if key.endswith('_id') and re.fullmatch(r'(?:S|C|G|OBS|OP|D|H|T|P|R)\d{3,}(?:-O\d+)?', value):
            return f'<a class="ref" href="#{h(value)}">{h(value)}</a>'
        if key in ('status','kind','access_status','provenance','confidence','identity_status','criteria_status'):
            return f'<span class="badge">{h(STATES.get(value,value))}</span>'
        return h(value).replace('\n','<br>')
    if isinstance(value, list):
        if not value:
            return '<span class="unknown">記録なし</span>'
        if key.endswith('_ids'):
            return ' '.join(f'<a class="ref" href="#{h(x)}">{h(x)}</a>' for x in value)
        return '<ul>' + ''.join('<li>'+render_value(x, key)+'</li>' for x in value) + '</ul>'
    if isinstance(value, dict):
        anchor = ''
        if re.fullmatch(r'D\d{3,}-O\d+', str(value.get('id',''))):
            anchor = f' id="{h(value["id"])}"'
        return f'<dl class="nested"{anchor}>' + ''.join(
            f'<dt>{h(LABELS.get(k,k))}</dt><dd>{render_value(v,k)}</dd>'
            for k,v in value.items()) + '</dl>'
    raise TypeError(f'Unsupported value: {type(value).__name__}')


def card(item: dict[str, Any], index: str | None = None) -> str:
    identifier = item.get('id', index or '')
    title = item.get('title', item.get('question',item.get('hypothesis',item.get('topic',identifier))))
    badges = ''.join(render_value(item[k],k) for k in ('status','kind','access_status') if k in item)
    body = ''.join(f'<dt>{h(LABELS.get(k,k))}</dt><dd>{render_value(v,k)}</dd>'
                   for k,v in item.items() if k not in ('id','title','question','hypothesis','topic'))
    return f'<article class="record" id="{h(identifier)}"><div class="card-top"><code>{h(identifier)}</code>{badges}</div><h3>{h(title)}</h3><dl>{body}</dl></article>'


def build(data: dict[str, Any]) -> str:
    meta = data['meta']
    nav = '<a href="#brief">ブリーフ</a>' + ''.join(f'<a href="#section-{key}">{h(name)} <small>{len(data[key])}</small></a>' for key,name in SECTIONS) + '<a href="#logs">ログ</a>'
    body = '<section id="brief"><h2>01 / 調査ブリーフ</h2><div class="grid">'+card({'id':'meta','title':'実行範囲と能力',**meta})+card({'id':'project','title':'今回の企画',**data['brief']})+'</div></section>'
    for i,(key,name) in enumerate(SECTIONS,2):
        cards = ''.join(card(x) for x in data[key])
        if not cards:
            cards = '<p class="empty">記録なし。未調査・対象外・未取得はブリーフと調査ログで区別してください。</p>'
        body += f'<section id="section-{key}"><h2>{i:02d} / {h(name)} <span>{len(data[key])}件</span></h2><div class="grid">{cards}</div></section>'
    logs = ''.join(card({'title':'調査ログ',**x},f'log-{i}') for i,x in enumerate(data['research_log']))
    changes = ''.join(card({'title':'変更履歴',**x},f'change-{i}') for i,x in enumerate(data['changes']))
    body += '<section id="logs"><h2>12 / 調査ログ・変更履歴</h2><div class="grid">'+(logs+changes or '<p class="empty">まだ記録がありません。</p>')+'</div></section>'
    css = '''
:root{--ink:#152936;--muted:#62717c;--line:#dbe3e8;--bg:#f4f7f9;--accent:#0b716d;--soft:#e9f4f2}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:25px}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.7 system-ui,-apple-system,"Segoe UI","Noto Sans JP",sans-serif}
header{background:#152936;color:#fff;padding:36px max(24px,calc((100vw - 1180px)/2)) 28px}header .eyebrow{font-size:12px;letter-spacing:.15em;color:#b2d7d3}h1{font-size:clamp(24px,4vw,36px);line-height:1.4;margin:8px 0 12px}header p{color:#d2dce2;max-width:900px}header .badge{color:#fff;background:#34515e;border-color:#456777}
main{max-width:1228px;margin:0 auto;padding:24px}nav{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:20px}nav a{padding:5px 12px;border:1px solid var(--line);border-radius:7px;background:white;text-decoration:none;font-size:13px}nav small{margin-left:5px;color:var(--muted)}a{color:var(--accent);overflow-wrap:anywhere}a:focus-visible,input:focus-visible,button:focus-visible{outline:3px solid #dfb34a;outline-offset:3px}.toolbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:16px}.toolbar input{flex:1;min-width:200px;padding:12px 14px;border:1px solid #a7b8c2;border-radius:7px;font:inherit}.toolbar button{padding:11px 16px;background:white;border:1px solid #a7b8c2;border-radius:7px;cursor:pointer;font:inherit}.note{font-size:13px;color:var(--muted);margin:0 0 24px}.notice{border-left:4px solid var(--accent);background:var(--soft);padding:14px 18px;margin:16px 0 28px}section{margin-bottom:32px}h2{font-size:19px;border-bottom:1px solid var(--line);padding-bottom:12px;margin:24px 0 16px}h2 span{font-size:12px;color:var(--muted);margin-left:10px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;align-items:start}.record{background:white;border:1px solid var(--line);border-radius:10px;padding:22px;min-width:0;box-shadow:0 2px 6px #15293605;break-inside:avoid}.record:target{outline:3px solid #53aaa3}.card-top{display:flex;align-items:center;gap:7px;flex-wrap:wrap;color:var(--muted);font-size:12px}.badge{font-size:11px;padding:2px 8px;border:1px solid #c5dedb;background:var(--soft);color:var(--accent);border-radius:999px;margin:0 4px 4px 0;display:inline-block}h3{font-size:18px;margin:10px 0 18px;overflow-wrap:anywhere}dl{margin:0}dt{font-size:12px;color:var(--muted);font-weight:600;margin-top:12px}dd{margin:2px 0 8px;overflow-wrap:anywhere;word-break:break-word}dl.nested{border-left:2px solid var(--line);padding-left:12px;margin:8px 0}ul{padding-left:18px;margin:4px 0}li{margin:4px 0;min-width:0}.unknown,.empty{font-size:13px;color:#77838b}.ref{display:inline-block;padding:1px 7px;margin:2px;border:1px solid #c5dedb;border-radius:4px;text-decoration:none;font:12px/1.8 ui-monospace,monospace}code{font:12px/1.6 ui-monospace,monospace}footer{padding:24px 0;color:var(--muted);font-size:12px}.record[hidden]{display:none}#count{font-size:12px;color:var(--muted)}
@media(max-width:760px){main{padding:16px}.grid{grid-template-columns:1fr}.record{padding:18px}header{padding:24px 20px}.toolbar input{width:100%}}
@media print{body{background:white}header{background:white;color:black;padding:0}header p,header .eyebrow{color:black}main{padding:0}nav,.toolbar,.note{display:none}.grid{display:block}.record{margin-bottom:16px;box-shadow:none}.record[hidden]{display:block}a{color:inherit}.notice{border:1px solid #aaa;background:white}}
'''
    js = '''
const q=document.getElementById('search');const records=[...document.querySelectorAll('.record')];
function filter(){const s=q.value.trim().toLocaleLowerCase();let n=0;for(const r of records){r.hidden=!!s&&!r.textContent.toLocaleLowerCase().includes(s);if(!r.hidden)n++;}document.getElementById('count').textContent=`表示 ${n} / ${records.length} 件`;}
q.addEventListener('input',filter);document.getElementById('clear').addEventListener('click',()=>{q.value='';filter();q.focus();});
document.addEventListener('click',e=>{const a=e.target.closest('a[href^="#"]');if(!a)return;const id=a.getAttribute('href').slice(1);const target=document.getElementById(id);if(!target)return;q.value='';filter();});filter();
'''
    title = h(meta['project_title'])
    return f'''<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} | Roblox Research</title><style>{css}</style></head>
<body><header><div class="eyebrow">ROBLOX / MARKET TO DESIGN</div><h1>{title}</h1><p>市場とジャンル史から、根拠のある企画判断へ。</p>{render_value(meta['status'],'status')}<span class="badge">{h(meta['mode'])} / {h(meta['depth'])}</span><p>開始：{h(meta['started_at'] or '未設定')}　時間帯：{h(meta['timezone'] or '未設定')}</p></header>
<main><nav aria-label="各セクション">{nav}</nav><div class="toolbar"><label for="search">全項目検索</label><input id="search" type="search" placeholder="ゲーム名・判断ID・未取得など"><button id="clear" type="button">クリア</button><output id="count" aria-live="polite"></output></div><p class="note">閲覧専用。編集・採用判断はCodexへ伝え、research.jsonを更新して再生成してください。</p><div class="notice">「事実・解釈・仮説」と「AIの推奨・ユーザー採用」は別です。欠損は0ではありません。この画面の生成や検証通過は、出典の真偽や企画の成功を保証しません。</div>{body}<footer>Generated locally by roblox-market-to-design. 外部通信・外部CDNなし。正本：research.json。</footer></main><script>{js}</script></body></html>'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('research', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--overwrite', action='store_true')
    parser.add_argument('--schema', type=Path, default=SCHEMA)
    args = parser.parse_args()
    out = args.out or args.research.with_name('dashboard.html')
    try:
        if out.suffix.lower() != '.html':
            raise ValueError('Output must have an .html extension')
        if out.resolve() == args.research.resolve():
            raise ValueError('Refusing to replace the source data')
        data = load_json(args.research)
        errors = validate(data,args.schema)
        if errors:
            raise ValueError('Invalid research data:\n'+'\n'.join(errors[:40]))
        document = build(data)
        out.parent.mkdir(parents=True,exist_ok=True)
        with out.open('w' if args.overwrite else 'x',encoding='utf-8') as f:
            f.write(document)
    except (OSError, ValueError, KeyError, RecursionError) as exc:
        print(f'Cannot render: {exc}', file=sys.stderr)
        return 2
    print(f'Created: {out}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

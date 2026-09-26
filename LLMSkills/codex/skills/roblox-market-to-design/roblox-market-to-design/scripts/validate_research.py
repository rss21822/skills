#!/usr/bin/env python3
"""Validate this Skill's research format with Python's standard library.

This is a validator for the keywords used in the bundled schema, not a general
JSON Schema implementation. It checks structure and references, NOT truth,
permissions, the existence of remote evidence, or commercial success.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import math
from pathlib import Path
import re
import sys
from typing import Any
from urllib.parse import urlsplit

SCHEMA = Path(__file__).resolve().parents[1] / 'assets' / 'research.schema.json'
COLLECTIONS = ('sources', 'claims', 'games', 'observations', 'opportunities',
               'decisions', 'hooks', 'tests', 'platform_checks', 'risks')
REF_FIELDS = {'source_ids': 'sources', 'claim_ids': 'claims',
              'supporting_claim_ids': 'claims', 'evidence_claim_ids': 'claims',
              'decision_ids': 'decisions', 'test_ids': 'tests', 'game_id': 'games'}


def load_json(path: Path) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for key, value in items:
            if key in out:
                raise ValueError(f'Duplicate JSON key: {key}')
            out[key] = value
        return out
    def reject_constant(value: str) -> None:
        raise ValueError(f'Non-finite JSON number: {value}')
    return json.loads(path.read_text(encoding='utf-8-sig'),
                      object_pairs_hook=pairs, parse_constant=reject_constant)


def safe_url(value: str) -> bool:
    if not value or re.search(r'[\s\x00-\x1f\x7f]', value):
        return False
    try:
        p = urlsplit(value)
        return p.scheme.lower() in ('https', 'http') and bool(p.hostname) and not p.username and not p.password
    except ValueError:
        return False


def timestamp(value: str) -> dt.datetime:
    if 'T' not in value:
        raise ValueError('ISO date-time needs T')
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Timezone required')
    return parsed


def schema_errors(data: Any, schema: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    def type_ok(v: Any, t: str) -> bool:
        return {'null': v is None, 'object': isinstance(v, dict),
                'array': isinstance(v, list), 'string': isinstance(v, str),
                'boolean': isinstance(v, bool),
                'integer': isinstance(v, int) and not isinstance(v, bool),
                'number': isinstance(v, (int, float)) and not isinstance(v, bool)
                          and (not isinstance(v, float) or math.isfinite(v))}.get(t, False)
    def walk(v: Any, rule: dict[str, Any], path: str) -> None:
        if '$ref' in rule:
            ref = rule['$ref']
            if not ref.startswith('#/$defs/'):
                errors.append(f'{path}: unsupported schema reference {ref}')
                return
            walk(v, schema['$defs'][ref.split('/')[-1]], path)
            return
        types = rule.get('type')
        if types is not None:
            allowed = types if isinstance(types, list) else [types]
            if not any(type_ok(v, t) for t in allowed):
                errors.append(f'{path}: expected {allowed}, got {type(v).__name__}')
                return
        if 'const' in rule and v != rule['const']:
            errors.append(f'{path}: expected constant {rule["const"]!r}')
        if 'enum' in rule and v not in rule['enum']:
            errors.append(f'{path}: invalid enum value {v!r}')
        if isinstance(v, str):
            if len(v) < rule.get('minLength', 0) or (rule.get('minLength', 0) and not v.strip()):
                errors.append(f'{path}: nonempty text required')
            if 'pattern' in rule and not re.search(rule['pattern'], v):
                errors.append(f'{path}: does not match {rule["pattern"]}')
            try:
                if rule.get('format') == 'date-time':
                    timestamp(v)
                elif rule.get('format') == 'date':
                    dt.date.fromisoformat(v)
                elif rule.get('format') == 'uri' and not safe_url(v):
                    raise ValueError('Only safe http(s) URLs are accepted')
            except ValueError as exc:
                errors.append(f'{path}: {exc}')
        elif isinstance(v, dict):
            properties = rule.get('properties', {})
            for key in rule.get('required', []):
                if key not in v:
                    errors.append(f'{path}: missing {key}')
            for key, child in v.items():
                if key in properties:
                    walk(child, properties[key], f'{path}.{key}')
                elif rule.get('additionalProperties') is False:
                    errors.append(f'{path}: unknown property {key}; use details for extensions')
                elif isinstance(rule.get('additionalProperties'), dict):
                    walk(child, rule['additionalProperties'], f'{path}.{key}')
        elif isinstance(v, list):
            if len(v) < rule.get('minItems', 0):
                errors.append(f'{path}: at least {rule["minItems"]} item(s) required')
            if rule.get('uniqueItems') and len({json.dumps(x, sort_keys=True, ensure_ascii=False) for x in v}) != len(v):
                errors.append(f'{path}: duplicate item')
            if 'items' in rule:
                for i, child in enumerate(v):
                    walk(child, rule['items'], f'{path}[{i}]')
    walk(data, schema, '$')
    return errors


def validate(data: Any, schema_path: Path = SCHEMA) -> list[str]:
    schema = load_json(schema_path)
    errors = schema_errors(data, schema)
    if errors:
        return errors
    maps: dict[str, dict[str, Any]] = {}
    all_ids: set[str] = set()
    for collection in COLLECTIONS:
        maps[collection] = {}
        for item in data[collection]:
            identifier = item['id']
            if identifier in all_ids:
                errors.append(f'Duplicate ID: {identifier}')
            all_ids.add(identifier)
            maps[collection][identifier] = item
    for d in data['decisions']:
        for o in d['options']:
            if o['id'] in all_ids:
                errors.append(f'Duplicate option ID: {o["id"]}')
            all_ids.add(o['id'])

    def refs(v: Any, path: str = '$') -> None:
        if isinstance(v, dict):
            for key, child in v.items():
                if key in REF_FIELDS:
                    values = child if isinstance(child, list) else [child]
                    for identifier in values:
                        if identifier not in maps[REF_FIELDS[key]]:
                            errors.append(f'{path}.{key}: broken reference {identifier}')
                if key == 'affected_ids':
                    for identifier in child:
                        if identifier not in all_ids:
                            errors.append(f'{path}: unknown changed ID {identifier}')
                # Custom details may have independent domain-specific field names.
                if key != 'details':
                    refs(child, f'{path}.{key}')
        elif isinstance(v, list):
            for i, child in enumerate(v):
                refs(child, f'{path}[{i}]')
    refs(data)

    def read_sources(values: list[str]) -> bool:
        return bool(values) and all(maps['sources'].get(x, {}).get('access_status') in ('accessed', 'provided') for x in values)

    for s in data['sources']:
        if not s['url'] and not (s['local_path'] or '').strip():
            errors.append(f'{s["id"]}: URL or actual local source reference is required')
        if s['access_status'] in ('accessed', 'provided') and s['retrieved_at'] is None:
            errors.append(f'{s["id"]}: accessed/provided source needs retrieved_at')
    for c in data['claims']:
        if c['kind'] == 'fact' and not read_sources(c['source_ids']):
            errors.append(f'{c["id"]}: fact requires directly accessed/provided sources')
        if c['kind'] == 'interpretation' and not (c['source_ids'] or c['supporting_claim_ids']):
            errors.append(f'{c["id"]}: interpretation needs an evidence basis')
    visited: set[str] = set()
    active: set[str] = set()
    def cycle(identifier: str) -> None:
        if identifier in active:
            errors.append(f'{identifier}: circular supporting_claim_ids')
            return
        if identifier in visited or identifier not in maps['claims']:
            return
        active.add(identifier)
        for target in maps['claims'][identifier]['supporting_claim_ids']:
            cycle(target)
        active.remove(identifier)
        visited.add(identifier)
    for identifier in maps['claims']:
        cycle(identifier)

    for g in data['games']:
        if g['identity_status'] == 'confirmed' and (not g['creator'] or not g['official_url'] or not read_sources(g['source_ids'])):
            errors.append(f'{g["id"]}: confirmed identity needs creator, official_url and accessed evidence')
        for m in g['metrics']:
            label = f'{g["id"]}.{m["name"]}'
            if m['value'] is None and not (m['missing_reason'] or '').strip():
                errors.append(f'{label}: null needs missing_reason')
            if m['value'] is not None and m['missing_reason'] is not None:
                errors.append(f'{label}: numeric value conflicts with missing_reason')
            if m['provenance'] == 'unavailable' and m['value'] is not None:
                errors.append(f'{label}: unavailable value must be null')
            if m['value'] is not None and m['provenance'] != 'planning_assumption':
                if not read_sources(m['source_ids']) or m['observed_at'] is None:
                    errors.append(f'{label}: observed/estimated value needs source and observed_at')
            if m['provenance'] in ('planning_assumption', 'third_party_estimate') and not m['limitations']:
                errors.append(f'{label}: assumption/estimate needs limitations')
            if m['period_start'] and m['period_end'] and timestamp(m['period_start']) > timestamp(m['period_end']):
                errors.append(f'{label}: period_start is after period_end')
    for o in data['observations']:
        if not read_sources(o['source_ids']):
            errors.append(f'{o["id"]}: observation needs accessed evidence')
        if o['method'] == 'client_play' and data['meta']['capabilities'].get('roblox_client') == 'unavailable':
            errors.append(f'{o["id"]}: client_play conflicts with unavailable client')
    for d in data['decisions']:
        options = {o['id'] for o in d['options']}
        for o in d['options']:
            if not o['id'].startswith(d['id'] + '-O'):
                errors.append(f'{d["id"]}: option must use its parent decision ID')
        for field in ('recommended_option_id', 'approved_option_id'):
            if d[field] is not None and d[field] not in options:
                errors.append(f'{d["id"]}: {field} is not one of its options')
        if d['status'] == 'approved':
            if not d['approved_option_id'] or not (d['approval_evidence'] or '').strip():
                errors.append(f'{d["id"]}: approved requires option and explicit approval evidence')
        elif d['approved_option_id'] is not None or d['approval_evidence'] is not None:
            errors.append(f'{d["id"]}: unapproved decision must not contain approval fields')
    for t in data['tests']:
        if t['status'] == 'completed' and (not (t['results'] or '').strip() or not read_sources(t['source_ids'])):
            errors.append(f'{t["id"]}: completed test needs results and accessed evidence')
        if t['status'] in ('planned', 'not_run') and t['results'] is not None:
            errors.append(f'{t["id"]}: unexecuted test must not have results')
        if t['criteria_status'] == 'evidence_based' and not read_sources(t['source_ids']):
            errors.append(f'{t["id"]}: evidence-based criteria need accessed evidence')
    for p in data['platform_checks']:
        if p['status'] == 'verified' and (p['checked_at'] is None or not read_sources(p['source_ids'])):
            errors.append(f'{p["id"]}: verified check needs date and accessed evidence')
    if data['meta']['status'] == 'complete':
        if not data['meta']['started_at'] or not data['meta']['timezone']:
            errors.append('complete run needs started_at and timezone')
        if not data['sources'] or not data['claims']:
            errors.append('complete run needs evidence and claims')
        if data['meta']['mode'] in ('full', 'audit') and not data['decisions']:
            errors.append('complete full/audit run needs design decisions')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('research', type=Path)
    parser.add_argument('--schema', type=Path, default=SCHEMA)
    parser.add_argument('--json', action='store_true', help='Print machine-readable validation results')
    args = parser.parse_args()
    try:
        errors = validate(load_json(args.research), args.schema)
    except (OSError, ValueError, KeyError, RecursionError) as exc:
        print(f'Cannot validate: {exc}', file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({'valid': not errors, 'errors': errors,
                          'scope': 'Structure and references only; not factual or market validation.'}, ensure_ascii=False, indent=2))
    elif errors:
        print('\n'.join('ERROR: ' + x for x in errors[:80]), file=sys.stderr)
        print(f'{len(errors)} validation error(s)', file=sys.stderr)
    else:
        print('PASS: structure, references, missing values and approval consistency.')
        print('Evidence truth, actual access, user approval authenticity and market success are NOT verified.')
    return 1 if errors else 0

if __name__ == '__main__':
    raise SystemExit(main())

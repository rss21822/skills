"""Write reviewed sources to new additive CSV batches; no network operations."""
import argparse
import csv
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--batch-size', type=int, default=50)
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error('batch-size must be positive')
    entries = json.loads(args.input.read_text(encoding='utf-8-sig'))
    if not isinstance(entries, list) or not entries:
        parser.error('input must be a non-empty JSON array')
    rows, pairs, keys = [], {}, {}
    fields = ['Key', 'Context', 'Source', 'Example']
    for index, item in enumerate(entries):
        if not isinstance(item, dict) or set(item) - set(fields):
            parser.error(f'entry {index}: unknown fields or non-object')
        if any(not isinstance(value, str) for value in item.values()):
            parser.error(f'entry {index}: all values must be strings')
        row = {field: item.get(field, '') for field in fields}
        if not row['Source'].strip():
            parser.error(f'entry {index}: Source must not be blank')
        pair = (row['Source'], row['Context'])
        if pair in pairs:
            if pairs[pair] != row:
                parser.error(f'entry {index}: conflicting Source/Context')
            continue
        if row['Key'] and row['Key'] in keys:
            parser.error(f'entry {index}: duplicate Key')
        pairs[pair] = row
        if row['Key']:
            keys[row['Key']] = pair
        rows.append(row)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    files = []
    for offset in range(0, len(rows), args.batch_size):
        path = args.output_dir / f'sources-{offset // args.batch_size + 1:03d}.csv'
        with path.open('x', encoding='utf-8-sig', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\r\n')
            writer.writeheader()
            writer.writerows(rows[offset:offset + args.batch_size])
        files.append(str(path.resolve()))
    print(json.dumps({'sources': len(rows), 'files': files}, ensure_ascii=False))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Extract EDTF test vectors from edtf-validate's test file."""
import re
import sys

src = open('/tmp/edtf-test-corpora/edtf-validate/tests/test_valid_edtf.py').read()

def extract_list(name):
    # Find `name = [...]` block
    pat = re.compile(rf'{re.escape(name)}\s*=\s*\[(.*?)\]', re.DOTALL)
    m = pat.search(src)
    if not m:
        return []
    body = m.group(1)
    # Grab quoted string literals
    strings = re.findall(r"'([^']*)'", body)
    return strings

names = [
    'L0_Intervals',
    'L1_Intervals',
    'L2_Intervals',
    'invalid_edtf_dates',
    'invalid_edtf_intervals',
    'invalid_edtf_datetimes',
]

# Level0, Level1, Level2 use list(chain([...], Lx_Intervals)) — extract the inline list
def extract_level(name):
    pat = re.compile(rf'{re.escape(name)}\s*=\s*list\(chain\(\[(.*?)\]', re.DOTALL)
    m = pat.search(src)
    if not m:
        return []
    body = m.group(1)
    return re.findall(r"'([^']*)'", body)

data = {}
for n in names:
    data[n] = extract_list(n)

data['Level0_dates'] = extract_level('Level0')
data['Level1_dates'] = extract_level('Level1')
data['Level2_dates'] = extract_level('Level2')

for name, vals in data.items():
    print(f"# {name}: {len(vals)}")

# Now emit an Elixir module
out = []
out.append('''# AUTO-GENERATED from the `unt-libraries/edtf-validate` test corpus
# (https://github.com/unt-libraries/edtf-validate) licensed BSD-3-Clause
# Copyright (c) 2014, Regents of the University of North Texas.
#
# This file must not be edited by hand. Re-run
# `ruby|python scripts/import_edtf_corpus.py` to refresh it.
defmodule Tempo.Iso8601.Edtf.Corpus do
  @moduledoc false

  # EDTF is the format that was folded wholesale into ISO 8601-2:2019.
  # The L0/L1/L2 distinction matches the standard's Level 0/1/2.''')

def emit_attr(name, vals, comment):
    out.append(f'\n  # {comment}')
    out.append(f'  @{name} [')
    seen = set()
    for v in vals:
        if v in seen:
            continue
        seen.add(v)
        # Elixir string literal with escaping
        escaped = v.replace('\\', '\\\\').replace('"', '\\"')
        out.append(f'    "{escaped}",')
    out.append('  ]')
    out.append(f'  def {name}, do: @{name}')

emit_attr('level0_dates', data['Level0_dates'], 'Level 0 dates (excluding intervals)')
emit_attr('level1_dates', data['Level1_dates'], 'Level 1 dates (excluding intervals)')
emit_attr('level2_dates', data['Level2_dates'], 'Level 2 dates (excluding intervals)')
emit_attr('level0_intervals', data['L0_Intervals'], 'Level 0 intervals')
emit_attr('level1_intervals', data['L1_Intervals'], 'Level 1 intervals')
emit_attr('level2_intervals', data['L2_Intervals'], 'Level 2 intervals')
emit_attr('invalid_dates', data['invalid_edtf_dates'], 'Invalid dates')
emit_attr('invalid_intervals', data['invalid_edtf_intervals'], 'Invalid intervals')
emit_attr('invalid_datetimes', data['invalid_edtf_datetimes'], 'Invalid datetimes')

out.append('end\n')

open('/Users/kip/Development/tempo/test/support/edtf_corpus.ex', 'w').write('\n'.join(out))
print(f"\nWrote test/support/edtf_corpus.ex")

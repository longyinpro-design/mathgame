"""Copy existing UI regressions into an isolated evidence destination.
No legacy runtime file is modified. A frame observer captures only states that
that level's own validator accepts as complete, for campaign adapter testing.
"""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tests/archipelago/generated'; OUT.mkdir(exist_ok=True)
for island,prefix in [('market','MK'),('workshop','GW')]:
 for n in range(1,19):
  ident=f'{prefix}{n:02}'
  path=ROOT/f'tests/{island}/{ident.lower()}_playtest.gd'
  source=path.read_text().replace('res://docs/playtest/', 'res://docs/playtest/archipelago/legacy/')
  match=re.search(r'(func _initialize\([^\n]*:\s*)([^\n]*)',source)
  # Insert immediately after the signature, preserving inline initializers.
  source=re.sub(r'func _initialize\(\) -> void:([^\n]*)',lambda m:'func _initialize() -> void:\n\tprocess_frame.connect(_capture_campaign_evidence)'+ ('\n\t'+m[1].strip() if m[1].strip() else ''),source,count=1)
  source += f'''\nvar campaign_captured = false
func _capture_campaign_evidence() -> void:
\tif campaign_captured: return
\tfor child in root.get_children():
\t\tvar value = child.get("state")
\t\tif not value is Dictionary or value.get("stage") != "complete": continue
\t\tvar verifier = load("res://scripts/{island}/{ident.lower()}_rules.gd")
\t\tif not verifier.validate(value): continue
\t\tvar output = FileAccess.open("res://docs/playtest/archipelago/proofs/{ident}.json",FileAccess.WRITE)
\t\toutput.store_string(JSON.stringify(value)); output.close()
\t\tcampaign_captured = true
'''
  (OUT/f'{ident.lower()}_playtest.gd').write_text(source)
print('Prepared 36 isolated copies of existing native UI checks')

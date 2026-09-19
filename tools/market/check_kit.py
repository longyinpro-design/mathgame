#!/usr/bin/env python3
"""Read-only exact-pixel, region, alpha, path, anchor and source-integrity checks."""
import hashlib,json
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
def main():
    manifest=json.loads((ROOT/'art/market-kit-v1/manifest.json').read_text())
    checks=[]; sources={}; covered={}
    def check(ok,label):
        checks.append({'check':label,'pass':bool(ok)})
    for path,h in manifest['source_sha256'].items():
        p=ROOT/path;check(hashlib.sha256(p.read_bytes()).hexdigest()==h,'source unchanged '+path)
        sources[path]=np.array(Image.open(p));covered[path]=np.zeros(sources[path].shape[:2],dtype=bool)
    for item in manifest['sprites']:
        p=ROOT/item['png']; image=Image.open(p);arr=np.array(image);x,y,w,h=item['source_rect']; source=sources[item['source']]
        check(image.mode=='RGBA' and image.size==(w,h),item['id']+' RGBA dimensions')
        check(np.array_equal(arr,source[y:y+h,x:x+w]),item['id']+' exact source pixels and alpha')
        check((arr[:,:,3]==0).any() and (arr[:,:,3]>128).any(),item['id']+' transparency and visible body')
        check(not covered[item['source']][y:y+h,x:x+w].any(),item['id']+' region disjoint')
        covered[item['source']][y:y+h,x:x+w]=True
        check((ROOT/item['atlas']).is_file(),item['id']+' atlas exists')
        for name,point in {'anchor':item['anchor_px'],**item['attachments_px']}.items():
            check(0<=point[0]<w and 0<=point[1]<=h,item['id']+' '+name+' within crop')
    for path,mask in covered.items():
        uncovered=int(((sources[path][:,:,3]>8)&~mask).sum())
        check(uncovered==0,path+' all visible source pixels covered (alpha > 8); missing='+str(uncovered))
    for scene in manifest['scenes']:
        im=Image.open(ROOT/scene['background']);check(im.size==(1672,941),scene['id']+' background dimensions')
        for name,(x,y) in scene['stations'].items():check(0<=x<1280 and 0<=y<720,scene['id']+' '+name+' logical position')
    old=json.loads((ROOT/'docs/playtest/market-mk01-reasoning/verification.json').read_text())
    check(all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in old['source_sha256'].items()),'all 41 existing MK01 inputs unchanged')
    report={'status':'PASS' if all(c['pass'] for c in checks) else 'FAIL','checks':checks,'passed':sum(c['pass'] for c in checks),'total':len(checks),'manifest_sha256':hashlib.sha256((ROOT/'art/market-kit-v1/manifest.json').read_bytes()).hexdigest(),'output_sha256':{item['png']:hashlib.sha256((ROOT/item['png']).read_bytes()).hexdigest() for item in manifest['sprites']},'limits':['Pixel checks do not prove game logic or character/boss animation.','Alpha <= 8 outside authored regions is treated as invisible generation residue; original sheets retained.']}
    (ROOT/'docs/playtest/market-kit-v1/verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(f"MARKET KIT CHECK {report['passed']}/{report['total']} {report['status']}")
    for c in checks:
        if not c['pass']:print('FAIL',c['check'])
    return 0 if report['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())

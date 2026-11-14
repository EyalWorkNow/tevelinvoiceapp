#!/usr/bin/env python3
"""Source-contract audit. Read-only discovery; never calls production APIs or reads secrets."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--backend', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
backend = Path(args.backend).resolve()
env = dict(os.environ)
node20 = Path.home()/'.nvm/versions/node/v20.19.0/bin'
if node20.exists(): env['PATH'] = str(node20)+os.pathsep+env['PATH']
code = "import {ROUTES} from './apps/api/src/routes'; console.log(JSON.stringify(ROUTES.map(({method,path,auth})=>({method,path,auth}))));"
run = subprocess.run(['pnpm','exec','tsx','-e',code], cwd=backend, env=env, text=True, capture_output=True, check=True)
routes = json.loads(run.stdout.strip().splitlines()[-1])
direct = []
for file in [backend/'apps/api/src/auth-routes.ts', backend/'apps/api/src/public-share-routes.ts', backend/'apps/api/src/public-quote-routes.ts']:
    if not file.exists(): continue
    for line_number,line in enumerate(file.read_text().splitlines(),1):
        for path in re.findall(r"['\"](/(?:auth|mobile|q|d)/[^'\"]*)['\"]",line):
            direct.append({'path':path,'file':str(file.relative_to(backend)),'line':line_number})

invite_source=backend/'apps/api/src/auth-routes.ts'
for method,path in [('GET','/auth/invite/:token'),('POST','/auth/invite/:token/accept')]:
    direct.append({'method':method,'path':path,'file':'apps/api/src/auth-routes.ts','line':next(i for i,l in enumerate(invite_source.read_text().splitlines(),1) if 'const inviteMatch' in l)})

# Dynamic client and server segments are compared as templates, not concrete IDs.
def template(path):
    path = re.sub(r'\$\{[^}]+\}', ':dynamic', path)
    path = re.sub(r'\$[A-Za-z_]\w*(?:\.\w+)*', ':dynamic', path)
    return path.split('?')[0].rstrip('/') or '/'
def intersects(a,b):
    aa,bb=template(a).split('/'),template(b).split('/')
    return len(aa)==len(bb) and all(x==y or x.startswith(':') or y.startswith(':') for x,y in zip(aa,bb))

methods={'getBytes':'GET','postBytes':'POST','putBytes':'PUT','getForBusiness':'GET','postForBusiness':'POST','putForBusiness':'PUT'}
pattern = re.compile(r"(?:_api|\bapi|ApiClient\.instance)\s*\.\s*(getForBusiness|postForBusiness|putForBusiness|getBytes|postBytes|putBytes|get|post|put|patch|delete)\s*\(\s*(?:[^,\n]+,\s*)?(['\"])(/(?:\$\{[^}\n]*\}|[^'\"\n])*)\2",re.M)
requests=[]
markers=[]
marker=re.compile(r'isMissingRoute|NOT_IMPLEMENTED|NOT_SUPPORTED|UNAVAILABLE|NotImplementedError|UnimplementedError|(?://.*\b(?:TODO|FIXME)\b)|web.handoff|WebHandoff|fallback|notConfigured|PUSH_SERVICE_NOT_CONFIGURED',re.I)
for file in sorted((root/'lib').rglob('*.dart')):
    source=file.read_text()
    for match in pattern.finditer(source):
        method=methods.get(match.group(1),match.group(1).upper())
        path=match.group(3)
        matches=[r for r in routes if r['method']==method and intersects(path,r['path'])]
        auth_matches=[r for r in direct if intersects(path,r['path'])]
        state='ROUTE_PRESENT' if matches else 'DIRECT_HANDLER_REVIEW' if auth_matches else 'UNMATCHED_REVIEW'
        requests.append({'method':method,'path':path,'template':template(path),'file':str(file.relative_to(root)), 'line':source[:match.start()].count('\n')+1,'state':state,'serverRoutes':[r['method']+' '+r['path'] for r in matches]})
    for line_number,line in enumerate(source.splitlines(),1):
        if marker.search(line): markers.append({'file':str(file.relative_to(root)),'line':line_number,'text':line.strip()[:220]})
features={}
for name in ['apps/api/src/commerce','apps/api/src/routes/v2','apps/worker/src']:
    for file in (backend/name).glob('*.ts'):
        names=sorted(set(re.findall(r'process\.env\.([A-Z][A-Z0-9_]*)',file.read_text())))
        if names: features[str(file.relative_to(backend))]=names
result={'generatedFor':'2026-11-09','scope':'source contracts only; not deployment or provider-delivery verification','backend':str(backend),'registeredRouteCount':len(routes),'requests':requests,'directHandlers':direct,'reviewMarkers':markers,'configurationNames':features}
output=root/'docs/backend-audit'
output.mkdir(parents=True,exist_ok=True)
(output/'api-coverage.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
lines=['# Mobile / backend connection audit','','Generated from the actual registered server route table and mobile source on 2026-11-09. This is a source-contract inventory, not evidence that a provider or production deployment is configured. Dynamic paths are compared as templates; conditional direct handlers require review.','','| Method | Mobile path | Source | Status | Server route |','|---|---|---|---|---|']
for r in requests:
    lines.append('| '+ ' | '.join([r['method'],r['path'].replace('|','\\|'),f"{r['file']}:{r['line']}",r['state'],', '.join(r['serverRoutes'])])+' |')
lines += ['','## Local/fallback/unsupported markers','','Every marker requires interpretation: cache fallbacks and deliberate desktop handoffs are not automatically defects.','']
for r in markers: lines.append(f"- `{r['file']}:{r['line']}` — {r['text']}")
(output/'API-COVERAGE.md').write_text('\n'.join(lines)+'\n')
counts={state:sum(r['state']==state for r in requests) for state in ['ROUTE_PRESENT','DIRECT_HANDLER_REVIEW','UNMATCHED_REVIEW']}
print(json.dumps({'registeredRoutes':len(routes),'mobileCalls':len(requests),'status':counts,'markers':len(markers)},ensure_ascii=False))
for r in requests:
    if r['state']=='UNMATCHED_REVIEW': print(r['method'],r['path'],r['file'],r['line'])

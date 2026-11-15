"""Local disposable fixtures only; prints assertions, never credentials or tokens."""
import json, re, time, urllib.request, urllib.error
from pathlib import Path
BASE='http://127.0.0.1:55321'
MAIL='http://127.0.0.1:55324'
env=Path('/Users/ivan/workplace/pawtrip-app/pawtrip/.env.development.local').read_text()
key=re.search(r'^EXPO_PUBLIC_SUPABASE_KEY\s*=\s*(.+)$',env,re.M).group(1).strip().strip('"\'')
def call(path, body=None, token=None, method=None):
 headers={'apikey':key,'Content-Type':'application/json'}
 if token: headers['Authorization']='Bearer '+token
 req=urllib.request.Request(BASE+path, data=None if body is None else json.dumps(body).encode(),headers=headers,method=method or ('POST' if body is not None else 'GET'))
 try:
  with urllib.request.urlopen(req,timeout=30) as r: return r.status,json.load(r)
 except urllib.error.HTTPError as e:
  raw=e.read()
  try: payload=json.loads(raw)
  except json.JSONDecodeError: payload={}
  return e.code,payload
status,session=call('/auth/v1/token?grant_type=password',{'email':'alex@test.local','password':'password123'})
assert status==200, 'local test fixture sign-in failed'
status,profiles=call('/rest/v1/profiles?select=handle&id=eq.00000000-0000-4000-8000-0000000000a1',token=session['access_token'])
assert status==200 and len(profiles)==1
handle=profiles[0]['handle']
status,unknown=call('/functions/v1/id-login',{'action':'send','identifier':'no_such_user_98765'})
assert status==200 and unknown=={'accepted':True}, 'unknown handle must not reveal account existence'
print('PASS: unknown ID send response is generic')
status,wrong=call('/functions/v1/id-login',{'action':'verify','identifier':'no_such_user_98765','token':'000000'})
assert status==401 and 'session' not in wrong
print('PASS: unknown ID cannot receive a session')
status,malformed=call('/functions/v1/id-login',{'action':'send','identifier':'bad id!'})
assert status==400
print('PASS: malformed ID rejected')
started=time.time()
status,sent=call('/functions/v1/id-login',{'action':'send','identifier':'@'+handle.upper(),'redirectTo':'http://localhost:8081'})
assert status==200 and sent==unknown, 'known and unknown send responses differ'
print('PASS: existing ID send response reveals no email')
code=None
for _ in range(20):
 with urllib.request.urlopen(MAIL+'/api/v1/messages') as r: messages=json.load(r)['messages']
 for m in messages:
  if any(t.get('Address')=='alex@test.local' for t in m.get('To',[])):
   from datetime import datetime
   ts=datetime.fromisoformat(m['Created'].replace('Z','+00:00')).timestamp()
   match=re.search(r'\b(\d{6})\b',m.get('Snippet',''))
   if ts>=started-1 and match: code=match.group(1); break
 if code: break
 time.sleep(.3)
assert code, 'test OTP mail did not arrive (check local Auth cooldown)'
status,result=call('/functions/v1/id-login',{'action':'verify','identifier':handle,'token':code})
assert status==200 and result.get('session',{}).get('access_token') and result['session'].get('refresh_token')
status,user=call('/auth/v1/user',token=result['session']['access_token'])
assert status==200 and user['id']=='00000000-0000-4000-8000-0000000000a1'
print('PASS: ID + OTP authenticates the correct local fixture')
status,replay=call('/functions/v1/id-login',{'action':'verify','identifier':handle,'token':code})
assert status==401 and 'session' not in replay
print('PASS: OTP replay rejected')

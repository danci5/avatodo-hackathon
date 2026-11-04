import argparse, base64, json, pathlib, re, struct, subprocess, sys, tempfile, time

parser=argparse.ArgumentParser(description='Live Meta checks using fictional notes. Reads only the development Keychain item; provider usage charges may apply.')
parser.add_argument('--run-live',action='store_true',help='Explicitly allow live language requests')
parser.add_argument('--include-images',action='store_true',help='Also request one image and one reference edit')
parser.add_argument('--output-dir',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]/'artifacts'/'meta-access-check')
ARGS=parser.parse_args()
if not ARGS.run_live: parser.error('Pass --run-live to send requests; add --include-images for image checks.')
OUTPUT=ARGS.output_dir
OUTPUT.mkdir(parents=True,exist_ok=True)
key_result=subprocess.run(['/usr/bin/security','find-generic-password','-a','avatodo','-s','app.avatodo.development.meta','-w'],capture_output=True,text=True)
if key_result.returncode: raise SystemExit('Development credential not accessible')
KEY=key_result.stdout.rstrip('\r\n')
if not KEY or any(ord(c)<33 or ord(c)>126 for c in KEY): raise SystemExit('Invalid credential characters')
results=[]

def request(path,payload,timeout=90):
 start=time.monotonic()
 with tempfile.TemporaryDirectory(prefix='avatodo-request-') as temp:
  p=pathlib.Path(temp)/'request.json';p.write_text(json.dumps(payload));p.chmod(0o600)
  r=subprocess.run(['/usr/bin/curl','-q','--silent','--show-error','--proto','=https','--connect-timeout','15','--max-time',str(timeout),'--header','@-','--data-binary','@'+str(p),'--write-out','\n%{http_code}','https://api.meta.ai/v1/'+path],input='Authorization: Bearer '+KEY+'\nContent-Type: application/json\n',capture_output=True,text=True)
 if r.returncode: raise RuntimeError('Network request failed, curl status '+str(r.returncode))
 body,_,status=r.stdout.rpartition('\n')
 if status!='200':
  safe=body.replace(KEY,'[redacted]')
  try: detail=json.loads(safe).get('error',{}).get('message','')[:350]
  except ValueError: detail='Non-JSON response'
  raise RuntimeError('HTTP '+status+' '+detail)
 return json.loads(body),round(time.monotonic()-start,2)

def record(name,seconds,**details):
 result={'check':name,'passed':True,'seconds':seconds,**details}
 results.append(result)
 (OUTPUT/'results.json').write_text(json.dumps({'scope':'Mac direct-API checks using fictional notes; not iPhone/Watch integration','checks':results},indent=2))
 print(json.dumps(result),flush=True)

def tool(name,props):
 return {'type':'function','function':{'name':name,'description':{'create_checklist':'Create a new saved checklist. Use only for a user request to create a list.','rename_item':'Change the label of an existing item, preserving identity.','complete_items':'Check off existing items by their stable IDs.'}[name],'strict':True,'parameters':{'type':'object','properties':props,'required':list(props),'additionalProperties':False}}}
S={'type':'string'};A={'type':'array','items':S}
tools=[tool('create_checklist',{'title':S,'items':A}),tool('rename_item',{'note_id':S,'item_id':S,'title':S}),tool('complete_items',{'note_id':S,'item_ids':A})]
messages=[{'role':'system','content':'You are Avatodo, a friendly concise companion. Normal conversation must never create a note or call a tool. For requested checklist changes use the provided tools and actual stable IDs from their results. Do not claim success before a tool succeeds. After a successful result give one short spoken sentence. This is fictional test data; do not invent IDs.'}]
fixture={}

def chat():
 data,seconds=request('chat/completions',{'model':'muse-spark-1.3','messages':messages,'tools':tools,'parallel_tool_calls':False,'reasoning_effort':'low','max_completion_tokens':800})
 message=data['choices'][0]['message']
 full={'role':'assistant','content':message.get('content') or ''}
 if message.get('tool_calls'): full['tool_calls']=message['tool_calls']
 messages.append(full)
 return full,seconds

def turn(prompt,expected):
 messages.append({'role':'user','content':prompt})
 used=[];duration=0
 for _ in range(3):
  msg,seconds=chat();duration+=seconds
  calls=msg.get('tool_calls',[])
  if not calls:
   if not msg.get('content','').strip(): raise RuntimeError('No assistant reply')
   if used!=expected: raise RuntimeError('Unexpected tool selection '+repr(used))
   return round(duration,2),used
  for call in calls:
   name=call['function']['name'];args=json.loads(call['function']['arguments']);used.append(name)
   if name=='create_checklist':
    if fixture: raise RuntimeError('Unexpected duplicate creation')
    if not isinstance(args['title'],str) or not isinstance(args['items'],list) or not all(isinstance(x,str) for x in args['items']): raise RuntimeError('Invalid create arguments')
    fixture.update({'id':'note-grocery-fixture','title':args['title'],'revision':1,'items':[{'id':'item-'+str(i+1),'title':text,'done':False} for i,text in enumerate(args['items'])]})
   elif name=='rename_item':
    if args['note_id']!=fixture['id']: raise RuntimeError('Wrong note target')
    items=[i for i in fixture['items'] if i['id']==args['item_id']]
    if len(items)!=1: raise RuntimeError('Wrong item target')
    items[0]['title']=args['title'];fixture['revision']+=1
   elif name=='complete_items':
    if args['note_id']!=fixture['id']: raise RuntimeError('Wrong note target')
    ids=args['item_ids'];valid={i['id'] for i in fixture['items']}
    if not isinstance(ids,list) or not set(ids)<=valid: raise RuntimeError('Unknown completion target')
    for item in fixture['items']:
     if item['id'] in ids: item['done']=True
    fixture['revision']+=1
   else: raise RuntimeError('Unknown tool')
   messages.append({'role':'tool','tool_call_id':call['id'],'content':json.dumps({'ok':True,'committed':True,'note':fixture})})
 raise RuntimeError('Tool loop exceeded smoke-test limit')

try:
 duration,names=turn('How are you today?',[])
 if fixture: raise RuntimeError('Conversation created a note')
 record('normal_reply_without_note',duration,model='muse-spark-1.3',tool_calls=0)
 duration,names=turn('Create a shopping checklist called Grocery run with milk, eggs and bread.',['create_checklist'])
 if {i['title'].lower() for i in fixture['items']}!={'milk','eggs','bread'}: raise RuntimeError('Unexpected created items')
 record('create_checklist_and_confirm_tool_result',duration,model='muse-spark-1.3',tools=names)
 duration,names=turn('Actually, change milk to oat milk.',['rename_item'])
 if {i['title'].lower() for i in fixture['items']}!={'oat milk','eggs','bread'}: raise RuntimeError('Correction failed')
 record('multiturn_correction_same_note',duration,model='muse-spark-1.3',tools=names)
 duration,names=turn('I bought eggs and bread. Check off both; leave oat milk unfinished.',['complete_items'])
 if {i['title'].lower() for i in fixture['items'] if i['done']}!={'eggs','bread'}: raise RuntimeError('Completion failed')
 record('multiturn_checkoff_two_items',duration,model='muse-spark-1.3',tools=names,fixture_note=fixture)
 if not ARGS.include_images:
  print('Four language/tool checks passed. Image requests skipped.',flush=True)
  sys.exit(0)
 print('Starting one character image generation...',flush=True)
 image,seconds=request('images/generations',{'model':'muse-image-1.0','prompt':'An original cute little lion companion wearing black Wayfarer-style sunglasses, no logos, full body sitting, facing straight toward the viewer, friendly closed-mouth smile, warm golden fur and orange mane, simple expressive rounded 2D illustration with clean shapes, no text, no props, centered alone with generous margin on a solid pure white background. Designed as a small Apple Watch companion.','n':1,'output_format':'png','response_format':'b64_json'},180)
 data=base64.b64decode(image['data'][0]['b64_json'],validate=True)
 if data[:8]!=b'\x89PNG\r\n\x1a\n': raise RuntimeError('Generated image is not PNG')
 width,height=struct.unpack('>II',data[16:24]);(OUTPUT/'lion-generated.png').write_bytes(data)
 record('character_image_generation',seconds,model='muse-image-1.0',width=width,height=height,bytes=len(data),artifact='lion-generated.png')
 print('Starting one reference-based speaking expression edit...',flush=True)
 edited,seconds=request('images/edits',{'model':'muse-image-1.0','prompt':'Keep exactly this same lion character, sunglasses, colors, body pose, scale, placement and pure white background. Change only the mouth into a small friendly open-mouth speaking expression. Keep the entire original canvas and character consistent. No text or logos.','images':[{'image_url':'data:image/png;base64,'+base64.b64encode(data).decode()}],'n':1,'output_format':'png','response_format':'b64_json'},180)
 data=base64.b64decode(edited['data'][0]['b64_json'],validate=True)
 if data[:8]!=b'\x89PNG\r\n\x1a\n': raise RuntimeError('Edited image is not PNG')
 width,height=struct.unpack('>II',data[16:24]);(OUTPUT/'lion-speaking.png').write_bytes(data)
 record('reference_based_expression_edit',seconds,model='muse-image-1.0',width=width,height=height,bytes=len(data),artifact='lion-speaking.png')
 print('All six direct-API checks passed. No native app, speech, animation or Watch synchronization claim.',flush=True)
except Exception as error:
 safe=str(error).replace(KEY,'[redacted]')
 (OUTPUT/'results.json').write_text(json.dumps({'scope':'Mac direct-API smoke checks, fictional fixture data','checks':results,'failure':safe},indent=2))
 print('CHECK FAILED: '+safe,flush=True)
 sys.exit(1)

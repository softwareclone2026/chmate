import pathlib,struct,json,hashlib
src=pathlib.Path('/Applications/ChMate.app/Contents/Resources/app.asar')
raw=src.read_bytes(); a=struct.unpack('<4I',raw[:16]); header=json.loads(raw[16:16+a[3]]); base=8+a[1]; blobs=[]; offset=0
updates={}
for folder in ['electron','dist']:
 for p in pathlib.Path('recovered-app',folder).rglob('*'):
  if p.is_file(): updates[f'{folder}/{p.relative_to(pathlib.Path("recovered-app",folder)).as_posix()}']=p.read_bytes()
def ensure_file(tree, parts):
 for part in parts[:-1]: tree=tree['files'].setdefault(part,{'files':{}})
 tree['files'].setdefault(parts[-1],{'size':0,'offset':'0'})
for key in updates: ensure_file(header,key.split('/'))
def walk(d,prefix=''):
 global offset
 for name,v in d['files'].items():
  key=prefix+name
  if 'files' in v: walk(v,key+'/'); continue
  if 'offset' not in v: continue
  content=updates[key] if key in updates else raw[base+int(v['offset']):base+int(v['offset'])+v['size']]
  v['offset']=str(offset);v['size']=len(content)
  if 'integrity' in v or key in updates:
   block=4194304;v['integrity']={'algorithm':'SHA256','hash':hashlib.sha256(content).hexdigest(),'blockSize':block,'blocks':[hashlib.sha256(content[i:i+block]).hexdigest() for i in range(0,len(content),block)]}
  blobs.append(content);offset+=len(content)
walk(header)
h=json.dumps(header,separators=(',',':'),ensure_ascii=False).encode(); pad=b'\0'*((-len(h))%4); payload=struct.pack('<I',len(h))+h+pad; hp=struct.pack('<I',len(payload))+payload
pathlib.Path('repair-build/app.asar').write_bytes(struct.pack('<II',4,len(hp))+hp+b''.join(blobs))
pathlib.Path('repair-build/header-hash.txt').write_text(hashlib.sha256(h).hexdigest())

"""Measure source-image ink bounds and register the React text legends to them."""
from pathlib import Path
import subprocess,re,json
from collections import deque
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'index.html';page=p.read_text();match=re.search(r'const KEY_DATA: KeySpec\[\] = (.*?);\nconst ART',page,re.S);keys=json.loads(match[1])
W=2443
raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/'reference.webp'),'-f','rawvideo','-pix_fmt','rgba','-'])
def brightness(x,y):
 i=(y*W+x)*4
 return sum(raw[i:i+3])/3

def bound(k,text,roi,size=24):
 x0,y0,x1,y1=roi
 ox=542+k['x'];oy=390+k['y']
 points=set();queue=deque()
 for y in range(round(oy+y0),round(oy+y1)):
  for x in range(round(ox+x0),round(ox+x1)):
   if brightness(x,y)>145:points.add((x,y));queue.append((x,y,0))
 while queue:
  x,y,d=queue.popleft()
  if d>=2:continue
  for xx,yy in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
   if round(ox+x0)<=xx<round(ox+x1) and round(oy+y0)<=yy<round(oy+y1) and (xx,yy) not in points and brightness(xx,yy)>105:
    points.add((xx,yy));queue.append((xx,yy,d+1))
 if not points:raise ValueError((k['id'],text,roi))
 l=min(x for x,y in points);t=min(y for x,y in points);r=max(x for x,y in points)+1;b=max(y for x,y in points)+1
 return dict(text=text,x=l-ox,y=t-oy,width=r-l,height=b-t,fontSize=size)
def split_word(k,label):
 chars=list(label['text'].replace(' ',''))
 if len(chars)<2:return [label]
 ox=round(542+k['x']+label['x']);oy=round(390+k['y']+label['y'])
 points=[(x,y) for y in range(label['height']) for x in range(label['width']) if brightness(ox+x,oy+y)>135]
 columns=sorted(set(x for x,y in points));runs=[]
 for x in columns:
  if not runs or x>runs[-1][-1]+1:runs.append([x])
  else:runs[-1].append(x)
 # At this source resolution two adjacent anti-aliased letters touch.
 if k['id']=='70' and label['text']=='start':runs=[list(range(0,4)),list(range(5,9)),list(range(10,16)),list(range(18,22)),list(range(22,27))]
 if k['id']=='74' and label['text']=='opt':runs=[list(range(0,9)),list(range(11,20)),list(range(20,26))]
 if len(runs)!=len(chars):return [label]
 result=[]
 for index,(char,run) in enumerate(zip(chars,runs)):
  ink=[(x,y) for x,y in points if run[0]<=x<=run[-1]]
  x0=min(x for x,y in ink);x1=max(x for x,y in ink)+1
  y0=min(y for x,y in ink);y1=max(y for x,y in ink)+1
  result.append(dict(text=char,x=label['x']+x0,y=label['y']+y0,width=x1-x0,height=y1-y0,fontSize=label['fontSize'],word=label['text'],letterIndex=index))
 return result

for k in keys:
 a=k['primary'];b=k['secondary'];w=k['width'];h=k['height'];kind=k['kind'];labels=[]
 if kind=='standard':
  if b:labels=[bound(k,a,(8,7,w-8,38)),bound(k,b,(8,38,w-8,h-7))]
  else:labels=[bound(k,a,(8,8,w-8,h-8))]
 elif kind=='wide':labels=[bound(k,a,(10,12,w-9,h-10))]
 elif kind=='function':
  if k['id']=='00':labels=[bound(k,a,(20,15,55,35),18)]
  elif k['id']=='14':labels=[bound(k,a,(8,10,w-8,34),18)]
  else:labels=[bound(k,b,(w-28,37,w-3,h-3),10)]
 elif kind=='modifier':
  if a=='cmd':
   labels=[bound(k,'⌘',(14,14,36,36),18),bound(k,'cmd',(5,36,45,65),16),bound(k,'alt',(53,10,w-4,65),18)]
   k['divider']={'x':49,'y':10,'height':56}
  elif a=='opt':
   labels=[bound(k,'⌥',(5,12,33,35),18),bound(k,'opt',(4,35,34,66),18),bound(k,b,(42,12,w-4,65),12 if b=='start' else 18)]
   k['divider']={'x':37,'y':10,'height':56}
  else:labels=[bound(k,a,(8,10,w-8,h-8),18)]
 elif kind=='arrow':labels=[bound(k,dict(Left='◀',Right='▶',Up='▲',Down='▼')[a],(8,5,w-8,h-5),16)]
 k['legends']=[char for label in labels for char in split_word(k,label)]
page=page[:match.start(1)]+json.dumps(keys,ensure_ascii=False,indent=2)+page[match.end(1):]
p.write_text(page)
print('Measured',sum(len(k['legends']) for k in keys),'text legends across',len(keys),'keys.')
for k in keys:
 if k['id'] in ('56','67'):print(k['id'],k['primary'],k['legends'])

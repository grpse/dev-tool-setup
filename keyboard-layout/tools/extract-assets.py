"""Reproduce key silhouettes and extract printed artwork from reference.webp.
Requires Python 3 and ffmpeg. No generated substitute characters are used.
"""
from pathlib import Path
import subprocess, struct, zlib, re, json
from collections import deque
ROOT=Path(__file__).resolve().parents[1]
W,H=2443,1374
raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/'reference.webp'),'-f','rawvideo','-pix_fmt','rgba','-'])
def png(path,w,h,data):
 def chunk(t,b):return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
 scan=b''.join(b'\0'+bytes(data[y*w*4:(y+1)*w*4]) for y in range(h))
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b''))
# Extract the actual wordmark, with the rail color removed from its alpha.
logo_points=[]
for ly in range(395,432):
 for lx in range(1190,1260):
  p=(ly*W+lx)*4
  if min(raw[p:p+3])>135:logo_points.append((lx,ly))
logo_x=min(p[0] for p in logo_points)-1;logo_y=min(p[1] for p in logo_points)-1
logo_w=max(p[0] for p in logo_points)-logo_x+2;logo_h=max(p[1] for p in logo_points)-logo_y+2
logo=bytearray()
for ly in range(logo_y,logo_y+logo_h):
 # Sample unprinted metal on either side of the wordmark.
 background=sum(raw[(ly*W+lx)*4] for lx in (1185,1186,1263,1264))/4
 for lx in range(logo_x,logo_x+logo_w):
  p=(ly*W+lx)*4
  alpha=max(0,min(255,round((sum(raw[p:p+3])/3-background)/(220-background)*255)))
  logo.extend((220,220,220,alpha))
png(ROOT/'assets/icons/logi.png',logo_w,logo_h,logo)
def luma(p):return (p[0]*3+p[1]*6+p[2])/10
html=(ROOT/'tools/layout-template.html').read_text()
pattern=re.compile(r'<div class="key ([^"]*)" style="([^"]*)">(.*?)</div>',re.S)
# Source frame with key-shaped holes: preserves the exact visible gutters.
FRAME_X,FRAME_Y,FRAME_W,FRAME_H=536,438,1368,552
frame=bytearray()
for row in range(FRAME_H):frame.extend(raw[((FRAME_Y+row)*W+FRAME_X)*4:((FRAME_Y+row)*W+FRAME_X+FRAME_W)*4])
manifest=[]
icon_names=['escape','device-1','device-2','device-3','backlight-down','backlight-up','dictation','emoji','screenshot','microphone-mute','play-pause','volume-mute','volume-down','volume-up','delete']
def extract(m):
 i=len(manifest);classes,style,content=m.groups();values={a:float(b) for a,b in re.findall(r'--(\w+):([\d.]+)',style)}
 x,y,w,h=[round(values[k]) for k in ('x','y','w','h')]
 # Keep three source pixels around each nominal rectangle to capture its real edge.
 x-=3;y-=3;w+=6;h+=6
 # The stacked arrows share their divider; never include the adjacent key.
 if 'arrow up' in classes:h=min(h,533-y)
 crop=bytearray()
 for v in range(h):crop.extend(raw[((y+390+v)*W+x+542)*4:((y+390+v)*W+x+542+w)*4])
 # Find the dark key body, then fill the printed glyph holes. The surrounding
 # frame has higher luminance; the near-black socket outlines close the shape.
 visited=bytearray(w*h);component=[]
 for seed in range(w*h):
  if visited[seed] or luma(crop[seed*4:seed*4+3])>=70:continue
  visited[seed]=1;queue=deque([seed]);part=[]
  while queue:
   p=queue.popleft();part.append(p);px=p%w;py=p//w
   for nx,ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
    if 0<=nx<w and 0<=ny<h:
     n=ny*w+nx
     if not visited[n] and luma(crop[n*4:n*4+3])<70:visited[n]=1;queue.append(n)
  if len(part)>len(component):component=part
 mask=bytearray(w*h)
 for p in component:mask[p]=1
 # Flood the exterior through all non-body pixels; interior holes are legends.
 outside=bytearray(w*h);queue=deque()
 for p in range(w*h):
  if (p<w or p>=w*(h-1) or p%w in (0,w-1)) and not mask[p]:outside[p]=1;queue.append(p)
 while queue:
  p=queue.popleft();px=p%w;py=p//w
  for nx,ny in ((px-1,py),(px+1,py),(px,py-1),(px,py+1)):
   if 0<=nx<w and 0<=ny<h:
    n=ny*w+nx
    if not mask[n] and not outside[n]:outside[n]=1;queue.append(n)
 for p in range(w*h):mask[p]=not outside[p]
 # Trim transparent padding to the detected socket's actual source bounds.
 occupied=[p for p,v in enumerate(mask) if v]
 if not occupied:raise ValueError(f'No socket found for key {i}')
 left=min(p%w for p in occupied);right=max(p%w for p in occupied)+1
 top=min(p//w for p in occupied);bottom=max(p//w for p in occupied)+1
 trimmed=bytearray();trimmed_mask=bytearray()
 for row in range(top,bottom):
  trimmed.extend(crop[(row*w+left)*4:(row*w+right)*4])
  trimmed_mask.extend(mask[row*w+left:row*w+right])
 x+=left;y+=top;w=right-left;h=bottom-top;crop=trimmed;mask=trimmed_mask
 for py in range(h):
  for px in range(w):
   fx=x+542+px-FRAME_X;fy=y+390+py-FRAME_Y
   if mask[py*w+px] and 0<=fx<FRAME_W and 0<=fy<FRAME_H:frame[(fy*FRAME_W+fx)*4+3]=0
 # Bright printed pixels, plus their antialiased fringe. Avoid the key boundary.
 ink=bytearray(w*h);queue=deque()
 for py in range(5,h-5):
  for px in range(5,w-5):
   p=py*w+px
   if mask[p] and luma(crop[p*4:p*4+3])>145:ink[p]=1;queue.append((p,0))
 while queue:
  p,depth=queue.popleft()
  if depth>=2:continue
  for n in (p-1,p+1,p-w,p+w):
   if 0<=n<w*h and mask[n] and not ink[n] and luma(crop[n*4:n*4+3])>78:
    ink[n]=1;queue.append((n,depth+1))
 surface=bytearray(crop);legend=bytearray(w*h*4)
 for p in range(w*h):
  if not mask[p]:surface[p*4+3]=0
  if ink[p]:
   legend[p*4:p*4+4]=crop[p*4:p*4+4]
   neighbors=[]
   for dy in range(-5,6):
    for dx in range(-5,6):
     nx=p%w+dx;ny=p//w+dy;n=ny*w+nx
     if 0<=nx<w and 0<=ny<h and mask[n] and not ink[n]:neighbors.append(n)
   if neighbors:
    for c in range(3):surface[p*4+c]=sum(crop[n*4+c] for n in neighbors)//len(neighbors)
 name=f'{i:02d}'
 png(ROOT/f'assets/keys/{name}.png',w,h,surface)
 png(ROOT/f'assets/legends/{name}.png',w,h,legend)
 # Each function key gets a separate, tightly bounded transparent icon asset.
 icon=None
 if 'function' in classes:
  # Main icon, excluding the F-number in the bottom right and status LED.
  bounds=(8,12,w-8,h-17)
  if i in (0,14): bounds=(w-29,h-26,w-7,h-6)
  a,b,c,d=bounds;points=[(px,py) for py in range(b,d) for px in range(a,c) if ink[py*w+px]]
  if points:
   a=min(p[0] for p in points);b=min(p[1] for p in points);c=max(p[0] for p in points)+1;d=max(p[1] for p in points)+1
   icon=f'assets/icons/{icon_names[i]}.png';data=bytearray()
   for py in range(b,d):data.extend(legend[(py*w+a)*4:(py*w+c)*4]);legend[(py*w+a)*4:(py*w+c)*4]=bytes((c-a)*4)
   png(ROOT/icon,c-a,d-b,data)
   png(ROOT/f'assets/legends/{name}.png',w,h,legend)
   icon_html=f'<img class="original-icon" src="{icon}" alt="" style="left:{a/w*100:.6f}%;top:{b/h*100:.6f}%;width:{(c-a)/w*100:.6f}%;height:{(d-b)/h*100:.6f}%">'
  else:icon_html=''
 else:icon_html=''
 label=re.sub('<[^>]+>',' ',content).strip()
 manifest.append(dict(id=name,x=x,y=y,width=w,height=h,icon=icon,label=label))
 return f'<div class="key {classes} source-key" style="--x:{x};--y:{y};--w:{w};--h:{h}"><img class="key-surface" src="assets/keys/{name}.png" alt=""><img class="key-legend" src="assets/legends/{name}.png" alt="{label}">{icon_html}</div>'
html=pattern.sub(extract,html)
(ROOT/'index.html').write_text(html)
png(ROOT/'assets/chassis.png',FRAME_W,FRAME_H,frame)
(ROOT/'assets/manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print(f'Extracted {len(manifest)} key silhouettes and legends; {sum(bool(k["icon"]) for k in manifest)} separate icons.')

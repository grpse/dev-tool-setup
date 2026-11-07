/* Orthographic height-field renderer. Rays from each visible surface sample
   travel toward an area light and test for occlusion by neighboring surfaces. */
(() => {
  const board = document.querySelector('.keyboard');
  const canvas = document.createElement('canvas');
  canvas.className = 'lighting';
  canvas.width = 1360; canvas.height = 600;
  canvas.setAttribute('aria-hidden', 'true');
  board.querySelector('.chassis').after(canvas);
  const gl = canvas.getContext('webgl', { alpha: true, antialias: false });
  if (!gl) { canvas.remove(); return; }
  const W = canvas.width, H = canvas.height;
  const pixels = new Uint8Array(W * H * 4);
  const smooth = (a,b,x) => { const t = Math.max(0,Math.min(1,(x-a)/(b-a))); return t*t*(3-2*t); };
  // The chassis is part of the same height field: shadow rays also reach
  // the exposed strips between keys, rather than shading only the keycaps.
  for (let y=48; y<H; y++) for (let x=0; x<W; x++) {
    const qx=Math.abs(x-W/2)-W/2+60;
    const qy=Math.abs(y-324)-276+60;
    const d=Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-60;
    if(d>0) continue;
    const p=(y*W+x)*4;
    pixels[p+1]=230; pixels[p+2]=255; pixels[p+3]=255;
  }
  // Store surface height, material, and coverage in a single geometry texture.
  for (const key of board.querySelectorAll('.key')) {
    const value = n => Number(key.style.getPropertyValue('--'+n));
    const x=value('x'), y=value('y'), w=value('w'), h=value('h');
    const flat = key.matches('.function,.modifier,.arrow');
    const enter = key.classList.contains('enter');
    for (let py=Math.floor(y);py<Math.ceil(y+h);py++) {
      for (let px=Math.floor(x);px<Math.ceil(x+w);px++) {
        const u=px+.5-x, v=py+.5-y;
        // ISO Enter is the union of its top bar and lower vertical stem.
        if (enter && u < 22 && v > 78) continue;
        const left = enter && v>78 ? 22 : 0;
        const radius=flat ? 10 : 12;
        const qx=Math.abs(u-(w+left)/2)-(w-left)/2+radius;
        const qy=Math.abs(v-h/2)-h/2+radius;
        let d=Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-radius;
        if (enter && v<78 && u<22) d=Math.max(d,v-77);
        if (d>0) continue;
        const rim=smooth(0,4,-d);
        const rx=Math.min(w*.45,48), ry=Math.min(h*.45,48);
        // Wide keys have a capsule-shaped dish; regular keys a circular one.
        const cx=Math.max(-(w/2-rx),Math.min(w/2-rx,u-w/2));
        const r=Math.hypot((u-w/2-cx)/rx,(v-h/2)/ry);
        const dish=flat?0:3.6*(1-smooth(.15,1,r));
        const height=1+rim*(7-dish);
        const p=(py*W+px)*4;
        pixels[p]=Math.round(height/16*255);
        pixels[p+1]=flat?115:100;
        pixels[p+2]=Math.round(smooth(0,2,-d)*255);
        pixels[p+3]=255;
      }
    }
  }
  function shader(type,source) {
    const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);
    if(!gl.getShaderParameter(s,gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  try {
    const program=gl.createProgram();
    gl.attachShader(program,shader(gl.VERTEX_SHADER,`attribute vec2 position; varying vec2 uv; void main(){uv=position*.5+.5;gl_Position=vec4(position,0.,1.);}`));
    gl.attachShader(program,shader(gl.FRAGMENT_SHADER,`
      precision highp float;
      varying vec2 uv; uniform sampler2D geometry; uniform vec2 light;
      const vec2 size=vec2(1360.,600.);
      float height(vec2 p){return texture2D(geometry,p/size).r*16.;}
      float visibility(vec3 p,vec3 direction){
        float visible=1.;
        for(int i=1;i<=28;i++){
          float t=float(i)*1.2;
          vec3 ray=p+direction*t;
          float clearance=ray.z-height(ray.xy);
          visible=min(visible,clamp(clearance/(.22*t+.2),0.,1.));
        }
        return visible;
      }
      void main(){
        vec2 p=vec2(uv.x,1.-uv.y)*size;
        vec4 material=texture2D(geometry,p/size);
        float z=height(p);
        if(material.a<.5){gl_FragColor=vec4(0.);return;}
        vec3 n=normalize(vec3(height(p-vec2(1,0))-height(p+vec2(1,0)),height(p-vec2(0,1))-height(p+vec2(0,1)),2.));
        vec3 l=normalize(vec3(light-p,550.));
        float shadow=visibility(vec3(p,z+.35),l);
        float ao=0.;
        for(int i=0;i<8;i++){
          float a=float(i)*.785398;
          vec2 d=vec2(cos(a),sin(a));
          ao+=clamp((height(p+d*5.)-z)/9.,0.,1.);
          ao+=.5*clamp((height(p+d*12.)-z)/14.,0.,1.);
        }
        ao=1.-ao/12.;
        float diffuse=max(dot(n,l),0.);
        float spec=pow(max(dot(n,normalize(l+vec3(0,0,1))),0.),38.);
        float value=(.20+.25*diffuse*shadow)*ao;
        float grain=fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453)-.5;
        vec3 color=vec3(.88,.94,.97)*value*(material.g*1.6)+spec*.09+grain*mix(.008,.07,step(.8,material.g));
        gl_FragColor=vec4(color,material.b);
      }`));
    gl.linkProgram(program);
    if(!gl.getProgramParameter(program,gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
    gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
    const position=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(position);gl.vertexAttribPointer(position,2,gl.FLOAT,false,0,0);
    const texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,W,H,0,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
    const light=gl.getUniformLocation(program,'light');
    const draw=(x,y)=>{gl.uniform2f(light,x,y);gl.drawArrays(gl.TRIANGLES,0,6);};
    draw(350,-220);board.classList.add('traced');
    // Redraw on demand rather than keeping an animation loop running.
    let frame;
    board.addEventListener('pointermove',e=>{
      if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
      const r=board.getBoundingClientRect();
      cancelAnimationFrame(frame);
      frame=requestAnimationFrame(()=>draw((e.clientX-r.left)/r.width*W,(e.clientY-r.top)/r.height*H-350));
    });
    board.addEventListener('pointerleave',()=>{cancelAnimationFrame(frame);draw(350,-220);});
    canvas.addEventListener('webglcontextlost',()=>board.classList.remove('traced'));
  } catch(error) { canvas.remove(); console.warn('Using CSS lighting fallback.',error); }
})();

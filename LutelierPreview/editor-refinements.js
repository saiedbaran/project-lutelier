let showDepthTexture=false,boxSelecting=false,depthSelection=null;
const photo=$('#photo'),depthOverlay=document.createElement('div'),selectionBox=document.createElement('div');
depthOverlay.className='depth-demo';depthOverlay.hidden=true;depthOverlay.innerHTML='<span>Illustrative texture · native Core ML required</span>';photo.append(depthOverlay);
selectionBox.className='depth-selection';selectionBox.hidden=true;photo.append(selectionBox);
const halo=document.createElement('img');halo.className='photo-backlight';halo.alt='';halo.setAttribute('aria-hidden','true');photo.before(halo);
const screenBackdropFrame=document.createElement('div');screenBackdropFrame.className='screen-backdrop-frame';screenBackdropFrame.setAttribute('aria-hidden','true');const screenBackdrop=document.createElement('img');screenBackdrop.className='screen-backdrop';screenBackdrop.alt='';screenBackdropFrame.append(screenBackdrop);$('#phone').prepend(screenBackdropFrame);
let haloFrame=null;
function refreshHalo(){halo.src=source;halo.style.filter=fullFilter()+' blur(38px) saturate(1.55)';halo.style.top=photo.offsetTop+'px';halo.style.height=photo.offsetHeight+'px';screenBackdrop.src=source;screenBackdrop.style.filter=fullFilter()+' blur(55px) saturate(1.25)';}
new ResizeObserver(refreshHalo).observe(photo);
const backlightPaint=paint;paint=()=>{backlightPaint();if(!haloFrame)haloFrame=requestAnimationFrame(()=>{refreshHalo();haloFrame=null;});};paint();
actions['depth-texture']=()=>{showDepthTexture=!showDepthTexture;depthOverlay.hidden=!showDepthTexture;renderControls();};
actions['depth-box']=()=>{boxSelecting=!boxSelecting;photo.classList.toggle('selecting-depth',boxSelecting);renderControls();};
actions['depth-refine']=()=>{toast(depthSelection?'Selection ready. Native Core ML re-estimates this crop, aligns it to the existing map and feathers its boundary. No AI inference runs in this browser.':'Enable Box select and draw a region on the photo first.');};
actions.analyze=()=>{showDepthTexture=true;depthOverlay.hidden=false;renderControls();toast('Illustrative texture only. The native app runs Depth Anything V2 locally.');};
actions.bokeh=v=>{change('bokeh',v);renderControls();toast(v+' aperture selected. Optical shape rendering runs in the native app.');};
const depthLoadSource=loadSource;loadSource=src=>{showDepthTexture=false;boxSelecting=false;depthSelection=null;depthOverlay.hidden=true;selectionBox.hidden=true;photo.classList.remove('selecting-depth');depthLoadSource(src);renderControls();};
const depthTabAction=actions.tab;actions.tab=value=>{if(value!=='Depth'){showDepthTexture=false;boxSelecting=false;depthOverlay.hidden=true;selectionBox.hidden=true;photo.classList.remove('selecting-depth');}depthTabAction(value);};
const photoPointers=new Map();let photoGesture=null,lastPhotoTap=0;
function point(e){const r=photo.getBoundingClientRect();return {x:Math.max(0,Math.min(r.width,e.clientX-r.left)),y:Math.max(0,Math.min(r.height,e.clientY-r.top)),w:r.width,h:r.height};}
function imageRegion(a,b){const img=$('#base'),r=photo.getBoundingClientRect(),scale=Math.max(r.width/img.naturalWidth,r.height/img.naturalHeight)*zoom,iw=img.naturalWidth*scale,ih=img.naturalHeight*scale;const left=(r.width-iw)/2+panX,top=(r.height-ih)*.45+panY;return {x:Math.max(0,Math.min(1,(Math.min(a.x,b.x)-left)/iw)),y:Math.max(0,Math.min(1,(Math.min(a.y,b.y)-top)/ih)),width:Math.min(1,Math.abs(a.x-b.x)/iw),height:Math.min(1,Math.abs(a.y-b.y)/ih)};}
photo.addEventListener('pointerdown',e=>{if(compare)return;photo.setPointerCapture(e.pointerId);const p=point(e);photoPointers.set(e.pointerId,p);if(photoPointers.size===2&&!boxSelecting){const [a,b]=[...photoPointers.values()];photoGesture={type:'pinch',distance:Math.hypot(a.x-b.x,a.y-b.y),zoom};return;}photoGesture={type:boxSelecting?'box':'pan',start:p,panX,panY,moved:false};});
photo.addEventListener('pointermove',e=>{if(!photoPointers.has(e.pointerId)||!photoGesture)return;const p=point(e);photoPointers.set(e.pointerId,p);if(photoGesture.type==='pinch'){if(photoPointers.size<2)return;const [a,b]=[...photoPointers.values()];zoom=Math.max(1,Math.min(8,photoGesture.zoom*Math.hypot(a.x-b.x,a.y-b.y)/Math.max(1,photoGesture.distance)));if(zoom===1)panX=panY=0;paint();return;}const a=photoGesture.start,dx=p.x-a.x,dy=p.y-a.y;photoGesture.moved ||= Math.hypot(dx,dy)>5;if(photoGesture.type==='box'){selectionBox.hidden=false;Object.assign(selectionBox.style,{left:Math.min(a.x,p.x)+'px',top:Math.min(a.y,p.y)+'px',width:Math.abs(dx)+'px',height:Math.abs(dy)+'px'});depthSelection=imageRegion(a,p);}else if(zoom>1){panX=Math.max(-p.w*(zoom-1)/2,Math.min(p.w*(zoom-1)/2,photoGesture.panX+dx));panY=Math.max(-p.h*(zoom-1)/2,Math.min(p.h*(zoom-1)/2,photoGesture.panY+dy));paint();}});
photo.addEventListener('pointerup',e=>{photoPointers.delete(e.pointerId);if(photoGesture?.type==='pan'&&!photoGesture.moved){const now=performance.now();if(now-lastPhotoTap<300){zoom=zoom>1?1:2.5;panX=panY=0;paint();lastPhotoTap=0;}else lastPhotoTap=now;}if(!photoPointers.size)photoGesture=null;});
photo.addEventListener('pointercancel',()=>{photoPointers.clear();photoGesture=null;});

// A single glass surface follows selection and direct touch scrubbing.
let toolContact=null,suppressToolClick=false;
function toolHighlight(lane){let highlight=lane.querySelector('.tool-glass-highlight');if(!highlight){highlight=document.createElement('span');highlight.className='tool-glass-highlight';highlight.setAttribute('aria-hidden','true');lane.prepend(highlight);}return highlight;}
function positionToolHighlight(lane,button,tracking=false){const h=toolHighlight(lane);h.classList.toggle('tracking',tracking);h.style.opacity=button?'1':'0';if(!button)return;const l=lane.getBoundingClientRect(),b=button.getBoundingClientRect();h.style.width=b.width+'px';h.style.height=b.height+'px';h.style.transform=`translate(${b.left-l.left+lane.scrollLeft}px,${b.top-l.top}px)`;}
function syncTabHighlight(){const lane=$('#tabs');positionToolHighlight(lane,lane.querySelector('button.active'));lane.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.classList.contains('active'))));}
new MutationObserver(syncTabHighlight).observe($('#tabs'),{childList:true});new ResizeObserver(syncTabHighlight).observe($('#tabs'));syncTabHighlight();
function buttonAt(lane,e){return [...lane.querySelectorAll('button:not(:disabled)')].find(b=>{const r=b.getBoundingClientRect();return e.clientX>=r.left&&e.clientX<=r.right&&e.clientY>=r.top-12&&e.clientY<=r.bottom+12;});}
document.addEventListener('pointerdown',e=>{const lane=e.target.closest('#tabs,.control-island');if(!lane||!e.isPrimary||e.button!==0)return;const button=buttonAt(lane,e);if(!button)return;toolContact={lane,button,start:button,id:e.pointerId};lane.setPointerCapture(e.pointerId);positionToolHighlight(lane,button,true);});
document.addEventListener('pointermove',e=>{if(e.pointerId!==toolContact?.id)return;const {lane}=toolContact;toolContact.button=buttonAt(lane,e);positionToolHighlight(lane,toolContact.button,true);});
function endToolContact(e,cancel=false){if(e.pointerId!==toolContact?.id)return;const {lane,button}=toolContact;toolContact=null;if(lane.hasPointerCapture(e.pointerId))lane.releasePointerCapture(e.pointerId);positionToolHighlight(lane,lane.id==='tabs'?lane.querySelector('button.active'):null);suppressToolClick=true;setTimeout(()=>suppressToolClick=false,0);if(!cancel&&button){actions[button.dataset.action]?.(button.dataset.value);if(lane.id==='tabs')syncTabHighlight();}}
document.addEventListener('pointerup',e=>endToolContact(e));document.addEventListener('pointercancel',e=>endToolContact(e,true));
document.addEventListener('click',e=>{if(suppressToolClick&&e.target.closest('#tabs,.control-island')){e.preventDefault();e.stopImmediatePropagation();}},{capture:true});
document.addEventListener('click',()=>{toolContact=null;positionToolHighlight($('.control-island'),null);syncTabHighlight();});
for(const lane of [$('#tabs'),$('.control-island')])lane.addEventListener('lostpointercapture',()=>{if(toolContact?.lane===lane){toolContact=null;positionToolHighlight(lane,lane.id==='tabs'?lane.querySelector('button.active'):null);}});
window.addEventListener('blur',()=>{if(toolContact)endToolContact({pointerId:toolContact.id},true);});

const launchBrand=document.createElement('div');launchBrand.className='launch-brand';launchBrand.setAttribute('aria-label','Lutelier. The art of photography.');const launchIcon=document.createElement('img');launchIcon.src=$('.camera-button img').src;launchIcon.alt='Lutelier lens';launchBrand.append(launchIcon);const launchName=document.createElement('strong');launchName.textContent='LUTELIER';launchBrand.append(launchName);const launchTagline=document.createElement('p');launchTagline.textContent='THE ART OF PHOTOGRAPHY';launchBrand.append(launchTagline);$('#phone').append(launchBrand);
function finishLaunch(){if(launchBrand.classList.contains('leaving'))return;launchBrand.classList.add('leaving');setTimeout(()=>launchBrand.remove(),450);}
setTimeout(finishLaunch,1600);launchBrand.addEventListener('click',finishLaunch);

actions['look-category']=value=>{lookCategory=value;renderControls();};

let inspectionTexture='Depth',refinementMethod='Context crop';
const engineRenderControls=renderControls;
renderControls=()=>{engineRenderControls();if(state.tab==='Depth'){
 const panel=document.createElement('div');panel.className='depth-engines';
 panel.innerHTML='<div class="caption">ON-DEVICE DEPTH</div><p class="depth-engine-detail">Depth Anything V2 Small + Apple portrait edges</p><p class="caption">Core ML scene depth, captured portrait/hair mattes and Vision fallback. All depth processing stays on the iPhone.</p><div class="pills">'+pill('Preserve portrait edges',state.protectPortraitEdges,'protect-portrait')+'</div><div class="pills">'+['Photo','Depth','Portrait','Hair'].map(t=>pill(t,t===(showDepthTexture?inspectionTexture:'Photo'),'matte-preview',t)).join('')+'</div><p class="caption">Browser textures are illustrations. Native Hair appears only when the photo contains an Apple hair matte.</p>';
 const modes=document.createElement('div');modes.className='depth-refinement-modes';
 modes.innerHTML='<div class="caption">REGIONAL REFINEMENT · ON IPHONE</div><div class="pills">'+['Context crop','Overlapping tiles'].map(t=>pill(t,t===refinementMethod,'depth-method',t)).join('')+'</div><p class="caption">'+(refinementMethod==='Overlapping tiles'?'Experimental: context + 4 overlapping detail crops. Core ML inference runs sequentially on iPhone; inconsistent tiles are rejected. This is not the trained PatchFusion network.':'One contextual crop, aligned to the saved map. Choose Overlapping tiles for additional detail passes.')+'</p>';
 panel.append(modes);$('#controls').prepend(panel);
}};
function inspectMatte(value){inspectionTexture=value;showDepthTexture=value!=='Photo';depthOverlay.hidden=!showDepthTexture;depthOverlay.dataset.texture=value.toLowerCase();depthOverlay.querySelector('span').textContent='Illustrative '+value.toLowerCase()+' texture - native on-device analysis required';renderControls();}
actions['matte-preview']=inspectMatte;
actions['depth-texture']=()=>inspectMatte(showDepthTexture?'Photo':'Depth');
actions['protect-portrait']=()=>{checkpoint();state.protectPortraitEdges=!state.protectPortraitEdges;renderControls();toast('Native blur '+(state.protectPortraitEdges?'preserves portrait/hair coverage.':'follows depth planes without portrait protection.'));};
actions.analyze=()=>{inspectMatte('Depth');toast('On iPhone: Core ML depth + captured Apple mattes or Vision segmentation. This browser shows an illustrative texture.');};
actions['depth-method']=value=>{refinementMethod=value;renderControls();};
actions['depth-refine']=()=>toast(depthSelection?(refinementMethod==='Overlapping tiles'?'Native iPhone workflow: 1 contextual + 4 overlapping Core ML detail crops, consistency-weighted fusion and unchanged depth outside the box. Experimental; no inference in this browser.':'Native iPhone workflow: one context crop, scale alignment and feathered boundary. No inference in this browser.'):'Enable Box select and draw a region on the photo first.');

// Apple typography, transparent circular lens, motion lighting and glass look changes.
const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
let lookAnimation=null,lookCommitTimer=null,lookFinishTimer=null,lookToken=0,coverAnimations=[];
const glassPane=document.createElement('div');glassPane.id='look-glass';glassPane.setAttribute('aria-hidden','true');$('#photo').append(glassPane);
const incomingPhoto=document.createElement('img');incomingPhoto.className='incoming-look';incomingPhoto.alt='';glassPane.append(incomingPhoto);
const glassSurface=document.createElement('div');glassSurface.className='cover-surface';glassPane.append(glassSurface);
const oldLookAction=actions.look;
function cancelGlass(){++lookToken;clearTimeout(lookCommitTimer);clearTimeout(lookFinishTimer);lookCommitTimer=null;lookAnimation?.cancel();coverAnimations.forEach(a=>a.cancel());coverAnimations=[];lookAnimation=null;glassPane.style.opacity='0';$('#photo').removeAttribute('aria-busy');}
actions.look=id=>{
  if(id===state.look&&!lookCommitTimer)return;
  const token=++lookToken;clearTimeout(lookCommitTimer);clearTimeout(lookFinishTimer);lookAnimation?.cancel();coverAnimations.forEach(a=>a.cancel());coverAnimations=[];
  if(reducedMotion.matches){glassPane.style.opacity='0';oldLookAction(id);return;}
  // The cover carries the next look, not a blurred copy of the current image.
  const target=looks.find(l=>l.id===id)||original;
  const targetFilter=filters(target,state.strength)+fullFilter().slice(filters().length);
  incomingPhoto.src=source;incomingPhoto.style.transform=`translate(${panX}px,${panY}px) scale(${zoom})`;
  incomingPhoto.style.filter=targetFilter+' blur(6px)';
  glassPane.style.opacity='1';$('#photo').setAttribute('aria-busy','true');
  lookAnimation=glassPane.animate([
    {transform:'perspective(850px) translate3d(-116%,12%,90px) rotateY(24deg) rotateX(9deg) rotateZ(-6deg) scale(1.025)',opacity:0},
    {transform:'perspective(850px) translate3d(-64%,5%,60px) rotateY(16deg) rotateX(5deg) rotateZ(-3deg) scale(1.02)',opacity:.7,offset:.2},
    {transform:'perspective(850px) translate3d(0,0,0) rotateY(0deg) rotateX(0deg) rotateZ(0deg) scale(1)',opacity:1,offset:.48},
    {transform:'perspective(850px) translate3d(0,0,0) rotateY(0deg) rotateX(0deg) rotateZ(0deg) scale(1)',opacity:1,offset:.87},
    {transform:'perspective(850px) translate3d(0,0,0) rotateY(0deg) rotateX(0deg) rotateZ(0deg) scale(1)',opacity:0}
  ],{duration:1250,easing:'cubic-bezier(.24,.68,.2,1)',fill:'forwards'});
  coverAnimations.push(incomingPhoto.animate([
    {filter:targetFilter+' blur(6px)',opacity:.4},
    {filter:targetFilter+' blur(6px)',opacity:.88,offset:.48},
    {filter:targetFilter+' blur(0px)',opacity:1,offset:.82},
    {filter:targetFilter+' blur(0px)',opacity:1}
  ],{duration:1250,easing:'ease-in-out',fill:'forwards'}));
  coverAnimations.push(glassSurface.animate([{opacity:1},{opacity:1,offset:.48},{opacity:0,offset:.9},{opacity:0}],{duration:1250,fill:'forwards'}));
  lookCommitTimer=setTimeout(()=>{if(token!==lookToken)return;lookCommitTimer=null;oldLookAction(id);},1000);
  lookFinishTimer=setTimeout(()=>{if(token!==lookToken)return;glassPane.style.opacity='0';lookAnimation?.cancel();coverAnimations.forEach(a=>a.cancel());coverAnimations=[];lookAnimation=null;$('#photo').removeAttribute('aria-busy');},1280);
};
for(const name of ['undo','redo','reset','import','open-photo','shutter']){const action=actions[name];actions[name]=(...args)=>{cancelGlass();return action(...args)};}
document.addEventListener('pointerdown',e=>{if(e.target.matches('[data-range]'))cancelGlass();});
document.addEventListener('keydown',e=>{if(e.target.matches('[data-range]'))cancelGlass();});
const oldMenu=actions.menu;actions.menu=()=>{oldMenu();const b=document.createElement('button');b.dataset.action='enable-tilt';b.textContent='Enable tilt shadow';$('#screen .modal-menu').append(b);};
// Crop the existing bitmap in the view: no changes to the original icon asset.
$$('.brand img').forEach(img=>{const lens=document.createElement('span');lens.className='lens-mark';img.replaceWith(lens);lens.append(img);});
$$('.camera-button,.mini-camera').forEach(el=>el.classList.add('lens-camera'));
let shadowX=0,shadowY=6,shadowFrame=null,tiltEnabled=false;
function setShadow(x,y){shadowX=Math.max(-14,Math.min(14,x));shadowY=Math.max(-14,Math.min(14,y));if(shadowFrame)return;shadowFrame=requestAnimationFrame(()=>{document.documentElement.style.setProperty('--lens-shadow-x',shadowX.toFixed(2)+'px');document.documentElement.style.setProperty('--lens-shadow-y',shadowY.toFixed(2)+'px');shadowFrame=null;});}
document.addEventListener('pointermove',e=>{if(tiltEnabled||reducedMotion.matches)return;const p=$('#phone').getBoundingClientRect();setShadow(-(e.clientX-p.left-p.width/2)/p.width*18,6-(e.clientY-p.top-p.height/2)/p.height*18);});
document.addEventListener('pointerleave',()=>{if(!tiltEnabled)setShadow(0,6)});
function orientationShadow(e){if(reducedMotion.matches||e.beta==null||e.gamma==null)return;tiltEnabled=true;const angle=window.screen.orientation?.angle??window.orientation??0;const x=e.gamma/3,y=(e.beta-45)/4;const a=angle*Math.PI/180;setShadow(-(x*Math.cos(a)+y*Math.sin(a)),6-(-x*Math.sin(a)+y*Math.cos(a)));}
actions['enable-tilt']=async()=>{
  if(reducedMotion.matches){toast('Tilt effects are disabled by your reduced-motion preference.');return;}
  if(!window.DeviceOrientationEvent){toast('Motion sensors are unavailable here. Move your pointer to explore the shadow.');return;}
  try{if(typeof DeviceOrientationEvent.requestPermission==='function'){const result=await DeviceOrientationEvent.requestPermission();if(result!=='granted'){toast('Motion access was not granted. Pointer lighting remains available.');return;}}
    window.addEventListener('deviceorientation',orientationShadow);toast('Tilt shadow enabled on supported phones. Pointer lighting remains available until motion data arrives.');
  }catch{toast('Motion access requires a supported browser and secure origin. Pointer lighting remains available.');}
};
// Touch scrolling remains native; mouse dragging offers the same swipe navigation.
let swipe=null,suppressClick=false;
document.addEventListener('pointerdown',e=>{
  if(e.pointerType!=='mouse'||e.button!==0)return;
  const lane=e.target.closest('.looks,.pills,.tabs');if(!lane||lane.scrollWidth<=lane.clientWidth)return;
  swipe={lane,start:e.clientX,left:lane.scrollLeft,id:e.pointerId,moved:false};
});
document.addEventListener('pointermove',e=>{if(!swipe||e.pointerId!==swipe.id)return;const dx=e.clientX-swipe.start;if(Math.abs(dx)>5){swipe.moved=true;swipe.lane.classList.add('swiping');swipe.lane.scrollLeft=swipe.left-dx;e.preventDefault();}});
document.addEventListener('pointerup',()=>{if(!swipe)return;suppressClick=swipe.moved;swipe.lane.classList.remove('swiping');swipe=null;setTimeout(()=>suppressClick=false,0);});
document.addEventListener('pointercancel',()=>{swipe?.lane.classList.remove('swiping');swipe=null;});
document.addEventListener('click',e=>{if(suppressClick){e.preventDefault();e.stopImmediatePropagation();}},{capture:true});
document.addEventListener('dragstart',e=>{if(e.target.closest('.looks,.pills,.tabs'))e.preventDefault();});
document.addEventListener('wheel',e=>{const lane=e.target.closest('.looks,.pills,.tabs');if(lane&&lane.scrollWidth>lane.clientWidth&&Math.abs(e.deltaY)>Math.abs(e.deltaX)){lane.scrollLeft+=e.deltaY;e.preventDefault();}},{passive:false});
// Replace decorative text-glyph icons with consistent system-style vector icons.
function normalizeIcons(){
  $$('button').forEach(b=>{if(b.querySelector('svg')||b.classList.contains('look')||b.classList.contains('template')||b.classList.contains('camera-button'))return;
    if(/^✧\s/.test(b.textContent)){b.innerHTML=icon('studio')+'<span>'+esc(b.textContent.replace(/^✧\s/,''))+'</span>';b.classList.add('symbol-label');}
    if(b.dataset.action==='add-template')b.innerHTML=icon('plus');
  });
}
new MutationObserver(normalizeIcons).observe($('#phone'),{childList:true,subtree:true});normalizeIcons();
const originalPaint=paint;paint=()=>{originalPaint();if(!compare&&zoom===1)$('#photo-hint').textContent='Double tap or scroll to zoom';};paint();

// Rotate on contact; a drag outside the circular hit area cancels activation.
const rotatingCamera=$('.camera-button');let cameraContact=null,cameraOpenTimer=null;
function cancelCameraContact(){clearTimeout(cameraOpenTimer);cameraOpenTimer=null;if(cameraContact)cameraContact.cancelled=true;rotatingCamera.classList.remove('camera-pressed');}
function cameraContains(e){const r=rotatingCamera.getBoundingClientRect();return Math.hypot(e.clientX-(r.left+r.width/2),e.clientY-(r.top+r.height/2))<=Math.min(r.width,r.height)/2;}
rotatingCamera.addEventListener('pointerdown',e=>{if(!e.isPrimary||e.button!==0)return;clearTimeout(cameraOpenTimer);cameraContact={id:e.pointerId,active:true,cancelled:false,started:performance.now()};rotatingCamera.classList.add('camera-pressed');rotatingCamera.setPointerCapture(e.pointerId);});
rotatingCamera.addEventListener('pointermove',e=>{if(cameraContact?.active&&e.pointerId===cameraContact.id&&!cameraContains(e))cancelCameraContact();});
rotatingCamera.addEventListener('pointerup',e=>{if(e.pointerId!==cameraContact?.id)return;cameraContact.active=false;if(!cameraContains(e))cancelCameraContact();if(rotatingCamera.hasPointerCapture(e.pointerId))rotatingCamera.releasePointerCapture(e.pointerId);});
rotatingCamera.addEventListener('pointercancel',e=>{if(e.pointerId===cameraContact?.id){cameraContact.active=false;cancelCameraContact();}});
rotatingCamera.addEventListener('lostpointercapture',()=>{if(cameraContact?.active){cameraContact.active=false;cancelCameraContact();}});
rotatingCamera.addEventListener('click',e=>{if(e.detail===0&&cameraContact?.cancelled)cameraContact=null;if(cameraContact?.cancelled){e.preventDefault();e.stopImmediatePropagation();cameraContact=null;return;}if(!cameraContact){cameraContact={active:false,cancelled:false,started:performance.now()};rotatingCamera.classList.add('camera-pressed');}},{capture:true});
const unanimatedCameraAction=actions.camera;actions.camera=()=>{if(!cameraContact||cameraContact.cancelled){cameraContact=null;unanimatedCameraAction();return;}const contact=cameraContact;const remaining=reducedMotion.matches?0:Math.max(0,160-(performance.now()-contact.started));cameraOpenTimer=setTimeout(()=>{if(contact.cancelled||cameraContact!==contact)return;unanimatedCameraAction();},remaining);};
const previousCloseScreen=closeScreen;closeScreen=()=>{if(activeScreen==='Camera'){cancelCameraContact();cameraContact=null;}previousCloseScreen();};
window.addEventListener('blur',()=>{cancelCameraContact();cameraContact=null;});
document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelCameraContact();cameraContact=null;}});

Object.assign(paths,{flash:'<path d="m13 2-9 12h7l-1 8 10-13h-7Z"/>',timer:'<circle cx="12" cy="14" r="8"/><path d="M9 2h6M12 6v8l3 2M18 5l2 2"/>',flip:'<path d="M3 8h4l2-3h6l2 3h4v12H3Z"/><path d="M8 12a5 5 0 0 1 8 0m0 4a5 5 0 0 1-8 0m8-7v3h-3m-5 7v-3h3"/>'});
function cameraTopTools(){return `<div class="camera-tools glass">${[['live-camera','camera','Enable live camera',false],['camera-grid','grid','Toggle grid',capture.grid],['camera-flash','flash','Toggle flash',capture.flash],['camera-timer','timer','Cycle capture timer',capture.timer>0],['camera-flip','flip','Switch camera',false]].map(([action,symbol,label,on])=>`<button data-action="${action}" aria-label="${label}" aria-pressed="${on}" class="${on?'active':''}">${icon(symbol)}${action==='camera-timer'&&capture.timer?`<small>${capture.timer}s</small>`:''}</button>`).join('')}</div>`;}
function cameraFrameRatio(){const area=$('#screen').getBoundingClientRect();return capture.ratio==='Full Screen'?area.width/area.height:capture.ratio==='1:1'?1:capture.ratio==='16:9'?9/16:3/4;}
function updateCameraFrame(){if(activeScreen!=='Camera')return;const area=$('#screen').getBoundingClientRect(),feed=$('.camera-feed');if(capture.ratio==='Full Screen'){Object.assign(feed.style,{width:'100%',height:'100%',left:'0',top:'0',transform:'none'});}else{const ratio=cameraFrameRatio(),w=Math.min(area.width,Math.max(180,area.height-215)*ratio);Object.assign(feed.style,{width:`${w}px`,height:`${w/ratio}px`,left:'50%',top:'105px',transform:'translateX(-50%)'});}$$('[data-action=camera-ratio]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.value===capture.ratio));}
actions['camera-pro']=()=>{capture.pro=!capture.pro;$('#pro-settings').hidden=!capture.pro;$('#camera-mode').setAttribute('aria-pressed',capture.pro);};
actions['camera-ratios']=()=>{$('#ratio-menu').hidden=!$('#ratio-menu').hidden;};
actions['camera-ratio']=value=>{capture.ratio=value;$('#camera-format').textContent=value;$('#ratio-menu').hidden=true;updateCameraFrame();};
actions['camera-flash']=()=>{capture.flash=!capture.flash;const b=$('[data-action=camera-flash]');b.classList.toggle('active',capture.flash);b.setAttribute('aria-pressed',capture.flash);toast('Flash selection is supported in the native camera.');};
actions['camera-timer']=()=>{capture.timer=capture.timer===0?3:capture.timer===3?10:0;$('.camera-tools').outerHTML=cameraTopTools();$$('[data-action=timer]').forEach(b=>b.classList.toggle('active',Number(b.dataset.value)===capture.timer));};
actions['camera-flip']=async()=>{capture.facing=capture.facing==='environment'?'user':'environment';if(stream){stopCamera();await enableCamera();}else toast(`${capture.facing==='user'?'Front':'Rear'} camera selected. Enable live camera to use it.`);};
window.addEventListener('resize',updateCameraFrame);
const previousGridAction=actions['camera-grid'];actions['camera-grid']=()=>{previousGridAction();$('[data-action=camera-grid]').setAttribute('aria-pressed',capture.grid);};

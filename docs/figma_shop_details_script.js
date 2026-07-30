// === Shop Details Screen (Screen 09) ===
// Run this in Figma's MCP use_figma tool when the rate limit resets.
// File key: WPy48Xpo70NRPF6yT7VmED
// Page: "App Screens"

const sp = figma.root.children.find(p => p.name === 'App Screens');
await figma.setCurrentPageAsync(sp);
await figma.loadFontAsync({family: 'IBM Plex Sans', style: 'Bold'});
await figma.loadFontAsync({family: 'IBM Plex Sans', style: 'SemiBold'});
await figma.loadFontAsync({family: 'IBM Plex Sans', style: 'Medium'});
await figma.loadFontAsync({family: 'IBM Plex Sans', style: 'Regular'});

const C = {
  primary: {r:0/255,g:137/255,b:148/255,a:1},
  primaryFg: {r:1,g:1,b:1,a:1},
  bg: {r:1,g:1,b:1,a:1},
  fg: {r:22/255,g:22/255,b:22/255,a:1},
  card: {r:253/255,g:253/255,b:253/255,a:1},
  muted: {r:245/255,g:245/255,b:245/255,a:1},
  mutedFg: {r:113/255,g:113/255,b:113/255,a:1},
  accent: {r:220/255,g:248/255,b:250/255,a:1},
  border: {r:228/255,g:228/255,b:228/255,a:1},
  success: {r:34/255,g:197/255,b:94/255,a:1},
};

const SH_SM = [{type:'DROP_SHADOW',visible:true,radius:8,spread:0,color:{r:0,g:0,b:0,a:0.06},offset:{x:0,y:2},blendMode:'NORMAL'}];

function sf(c) { return [{type:'SOLID',color:c,visible:true}]; }
function txt(s,z,w,c) {
  const t = figma.createText();
  t.characters = s;
  t.fontSize = z;
  t.fontName = {family:'IBM Plex Sans',style:w};
  t.fills = sf(c);
  return t;
}
function rect(w,h,f,r) {
  const x = figma.createFrame();
  x.resize(w,h);
  x.fills = sf(f);
  if (r) x.cornerRadius = r;
  return x;
}

// === 09 — Shop Details ===
const shop = rect(390, 844, C.bg, 0);
shop.name = '09 - Shop Details';
shop.clipsContent = true;
shop.x = 3600;
shop.y = 0;

// Header
const hdr = rect(390, 120, C.primary, 0);
shop.appendChild(hdr);
const back = txt('<', 28, 'Regular', C.primaryFg);
back.x = 16; back.y = 64;
hdr.appendChild(back);
const ht = txt('Shop Details', 20, 'Bold', C.primaryFg);
ht.textAlignHorizontal = 'CENTER';
ht.x = 110; ht.y = 62;
hdr.appendChild(ht);

// Shop image area
const shopImg = rect(390, 120, C.accent, 0);
shopImg.y = 120;
shop.appendChild(shopImg);
const shopIcon = txt('S', 48, 'Bold', C.primary);
shopIcon.textAlignHorizontal = 'CENTER';
shopIcon.x = 170; shopIcon.y = 36;
shopImg.appendChild(shopIcon);

// Name card
const nameCard = rect(342, 80, C.card, 16);
nameCard.x = 24; nameCard.y = 260;
nameCard.strokes = sf(C.border);
nameCard.strokeWeight = 1;
nameCard.effects = SH_SM;
shop.appendChild(nameCard);

const sName = txt('Osacc Mall - Spintex', 18, 'Bold', C.fg);
sName.x = 20; sName.y = 16;
nameCard.appendChild(sName);

const sAddr = txt('Spintex Rd, Accra', 13, 'Regular', C.mutedFg);
sAddr.x = 20; sAddr.y = 42;
nameCard.appendChild(sAddr);

const sStatus = rect(60, 22, C.success, 11);
sStatus.x = 20; sStatus.y = 58;
nameCard.appendChild(sStatus);
const sStatT = txt('Open', 10, 'Bold', C.primaryFg);
sStatT.textAlignHorizontal = 'CENTER';
sStatT.x = 16; sStatT.y = 5;
sStatus.appendChild(sStatT);

// Stats cards
const stats = [
  {label: 'Today Sales', val: 'GHS 2,450', col: C.primary},
  {label: 'Transactions', val: '47', col: C.fg},
  {label: 'Items Sold', val: '128', col: C.fg},
];
let sx = 24;
for (const st of stats) {
  const card = rect(106, 72, C.card, 12);
  card.x = sx; card.y = 360;
  card.strokes = sf(C.border);
  card.strokeWeight = 1;
  card.effects = SH_SM;
  shop.appendChild(card);
  const lb = txt(st.label, 10, 'Regular', C.mutedFg);
  lb.x = 12; lb.y = 12;
  card.appendChild(lb);
  const v = txt(st.val, 18, 'Bold', st.col);
  v.x = 12; v.y = 32;
  card.appendChild(v);
  sx += 114;
}

// Shop information section
const dtLbl = txt('SHOP INFORMATION', 11, 'SemiBold', C.mutedFg);
dtLbl.x = 24; dtLbl.y = 460;
shop.appendChild(dtLbl);

const info = [
  {label: 'Phone', val: '+233 24 123 4567'},
  {label: 'Email', val: 'osacc@ledgermind.gh'},
  {label: 'Opening Hours', val: '8:00 AM - 9:00 PM'},
  {label: 'Tax ID', val: 'GRA-001234567'},
  {label: 'Currency', val: 'GHS (Ghana Cedi)'},
];
let iy = 488;
for (const item of info) {
  const row = rect(342, 52, C.card, 0);
  row.x = 24; row.y = iy;
  row.strokes = sf(C.border);
  row.strokeWeight = 1;
  shop.appendChild(row);
  const lb = txt(item.label, 13, 'Medium', C.fg);
  lb.x = 16; lb.y = 16;
  row.appendChild(lb);
  const v = txt(item.val, 13, 'Regular', C.mutedFg);
  v.x = 180; v.y = 16;
  row.appendChild(v);
  iy += 52;
}

// Edit button
const editBtn = rect(342, 48, C.primary, 12);
editBtn.x = 24; editBtn.y = 780;
shop.appendChild(editBtn);
const editT = txt('Edit Shop Details', 15, 'Bold', C.primaryFg);
editT.textAlignHorizontal = 'CENTER';
editT.x = 85; editT.y = 14;
editBtn.appendChild(editT);

return {createdNodeIds: [shop.id], screen: shop.name};

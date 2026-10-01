const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),native=path.join(root,'LutelierIOS','Lutelier');
fs.mkdirSync(path.join(__dirname,'assets','studio'),{recursive:true});
fs.copyFileSync(path.join(native,'Assets.xcassets','BrandIcon.imageset','icon_1024.png'),path.join(__dirname,'assets','icon.png'));
const studio=JSON.parse(fs.readFileSync(path.join(native,'Resources','Studio','templates.json'),'utf8'));
for(const t of studio)fs.copyFileSync(path.join(native,'Resources','Studio',t.file),path.join(__dirname,'assets','studio',t.file));
const looks=JSON.parse(fs.readFileSync(path.join(native,'Resources','Looks','presets.json'),'utf8'));
fs.writeFileSync(path.join(__dirname,'data.js'),'const LOOKS='+JSON.stringify(looks)+';\nconst STUDIO='+JSON.stringify(studio)+';\n');
console.log(`Bundled ${looks.length} looks and ${studio.length} credited studio references.`);

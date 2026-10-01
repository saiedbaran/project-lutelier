"""Contact sheets for visual QA; source reference files are kept unchanged."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[1]
resource=root/'Lutelier/Resources/Studio'
out=root/'studio-research';out.mkdir(exist_ok=True)
templates=json.loads((resource/'templates.json').read_text(encoding='utf-8'))
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',12)
for offset in range(0,len(templates),40):
    sheet=Image.new('RGB',(8*170,5*230),(15,15,20));draw=ImageDraw.Draw(sheet)
    for index,entry in enumerate(templates[offset:offset+40]):
        x=(index%8)*170;y=(index//8)*230
        image=Image.open(resource/entry['file']).convert('RGB');image.thumbnail((160,195))
        sheet.paste(image,(x+(170-image.width)//2,y+(195-image.height)//2))
        draw.text((x+5,y+198),entry['id'],font=font,fill=(255,181,71))
        draw.text((x+5,y+215),entry['sourceTitle'].removeprefix('File:')[:23],font=font,fill='white')
    filename=out/f'contact-{offset//40+1}.jpg';sheet.save(filename,quality=92)
    print(filename)

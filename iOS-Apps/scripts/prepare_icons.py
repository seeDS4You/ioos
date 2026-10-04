"""Translate the existing Android vector icons to SVG without changing their paths."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
android = '{http://schemas.android.com/apk/res/android}'

def color(value):
    if value.startswith('#') and len(value) == 9:
        return '#' + value[3:], int(value[1:3], 16) / 255
    return value, 1

def paths(file, prefix):
    data = ET.parse(file).getroot()
    shapes = []
    definitions = []
    for index, path in enumerate(data.findall('path')):
        fill, alpha = color(path.attrib.get(android + 'fillColor', '#FFFFFF'))
        gradient = path.find('.//gradient')
        if gradient is not None:
            key = prefix + str(index)
            attrs = {name: gradient.attrib.get(android + source, '0') for name,source in [('x1','startX'),('y1','startY'),('x2','endX'),('y2','endY')]}
            stops=[]
            for item in gradient.findall('item'):
                c,a=color(item.attrib[android+'color'])
                stops.append(f'<stop offset="{item.attrib[android+"offset"]}" stop-color="{c}" stop-opacity="{a}"/>')
            definitions.append('<linearGradient id="'+key+'" gradientUnits="userSpaceOnUse" '+ ' '.join(f'{k}="{v}"' for k,v in attrs.items())+'>'+''.join(stops)+'</linearGradient>')
            fill='url(#'+key+')'
        rule='evenodd' if path.attrib.get(android+'fillType')=='evenOdd' else 'nonzero'
        stroke=''
        if android+'strokeColor' in path.attrib:
            c,a=color(path.attrib[android+'strokeColor'])
            stroke=f' stroke="{c}" stroke-opacity="{a}" stroke-width="{path.attrib.get(android+"strokeWidth", "1")}"'
        shapes.append(f'<path d="{path.attrib[android+"pathData"]}" fill="{fill}" fill-opacity="{alpha}" fill-rule="{rule}"{stroke}/>')
    return ''.join(definitions), ''.join(shapes)

for role in ('Staff','Admin','Supervisor'):
    source=root.parent/f'siss-{role.lower()}-android-app/app/src/main/res'
    definitions,foreground=paths(source/'drawable/ic_launcher_foreground.xml', 'fg')
    background='#0B0D14'
    bgfile=source/'drawable/ic_launcher_background.xml'
    bgpaths=''
    if bgfile.exists():
        bgdefs,bgpaths=paths(bgfile, 'bg'); definitions+=bgdefs
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 108 108"><defs>{definitions}</defs><rect width="108" height="108" fill="{background}"/>{bgpaths}{foreground}</svg>'
    directory=root/f'Resources/{role}.xcassets/AppIcon.appiconset'
    directory.mkdir(parents=True,exist_ok=True)
    (root/f'Resources/{role}-icon.svg').write_text(svg,encoding='utf-8')
    (directory/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    (directory.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
print('Copied Android vector path geometry for all three icon catalogs.')

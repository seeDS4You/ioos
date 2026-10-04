"""Windows-safe structural validation. This intentionally does not claim Xcode compilation."""
from pathlib import Path
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
failures = []
checks = []
def check(condition, label):
    (checks if condition else failures).append(label)

for role, target in [('Staff','SISSStaff'),('Admin','SISSAdmin'),('Supervisor','SISSSupervisor')]:
    plist=plistlib.loads((root/f'Config/{role}.plist').read_bytes())
    check('NSAppTransportSecurity' not in plist, role+' uses standard HTTPS security')
    check(plist['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)',role+' configurable signed bundle')
    scheme=ET.parse(root/f'SISSApps.xcodeproj/xcshareddata/xcschemes/{target}.xcscheme').getroot()
    check(scheme.find('.//BuildableReference').attrib['BlueprintName']==target,role+' shared build scheme')
    directory=root/f'Resources/{role}.xcassets/AppIcon.appiconset'
    catalog=json.loads((directory/'Contents.json').read_text())
    check((directory/catalog['images'][0]['filename']).exists(),role+' icon asset present')
    try:
        from PIL import Image
        with Image.open(directory/'AppIcon.png') as image:
            check(image.size==(1024,1024),role+' 1024px icon')
            check('A' not in image.getbands() or image.getextrema()[-1]==(255,255),role+' icon opaque')
    except ImportError:
        pass

project=(root/'SISSApps.xcodeproj/project.pbxproj').read_text()
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]',project.split('\n',1)[1])
cursor=0
def parse_project_value():
    global cursor
    token=tokens[cursor]; cursor+=1
    if token=='{':
        result={}
        while tokens[cursor]!='}':
            key=json.loads(tokens[cursor]); cursor+=1
            assert tokens[cursor]=='='; cursor+=1
            result[key]=parse_project_value()
            assert tokens[cursor]==';'; cursor+=1
        cursor+=1
        return result
    if token=='(':
        result=[]
        while tokens[cursor]!=')':
            result.append(parse_project_value())
            if tokens[cursor]==',': cursor+=1
        cursor+=1
        return result
    return json.loads(token)
parsed=parse_project_value()
check(cursor==len(tokens),'OpenStep project syntax complete')
objects=parsed['objects']
references=re.findall(r'"([A-F0-9]{24})"',project)
check(all(key in objects for key in references),'all project object references resolve')
check(parsed['rootObject'] in objects,'project root exists')
for value in objects.values():
    if value.get('isa')=='PBXNativeTarget' and value.get('productType')=='com.apple.product-type.application':
        source_phases=[objects[ref] for ref in value['buildPhases'] if objects[ref]['isa']=='PBXSourcesBuildPhase']
        files=[objects[objects[ref]['fileRef']]['path'] for ref in source_phases[0]['files']]
        role={'SISSStaff':'Staff','SISSAdmin':'Admin','SISSSupervisor':'Supervisor'}[value['name']]
        check(all(path.startswith(('Shared/',role+'/')) for path in files),value['name']+' isolated role source membership')
        check(any(path.startswith(role+'/') for path in files),value['name']+' includes role implementation')
check(project.count('"isa" = "PBXNativeTarget"')==4,'three apps and one test target')
for path in re.findall(r'"path" = "([^"]+)"',project):
    if path.endswith(('.app','.xctest')): continue
    check((root/path).exists(),'project reference '+path)

api=(root/'Shared/API.swift').read_text()
check('https://yourallsiss.co.uk' in api and 'https://allsiss.co.uk' not in api,'current domain in network client')
check('kSecAttrAccessibleWhenUnlockedThisDeviceOnly' in api,'session stored in device Keychain')
check('NSAllowsArbitraryLoads' not in api,'no HTTP/TLS bypass')
admin=(root/'Admin/Admin.swift').read_text()
check('/api/admin/' not in admin,'no obsolete admin API prefix')
backend=root.parent/'siss-app/src/routes'
routes={'auth':['auth'], 'supervisor':['supervisor'], 'events':['events'], 'people':['people'], 'documents':['documents'], 'dashboard':['dashboard'], 'invoicing':['invoicing'], 'apiScan':['scan'], 'timesheet':['timesheet'], 'qr':['qr']}
known=[]
for file,prefixes in routes.items():
    path=backend/f'{file}.js'
    if not path.exists(): continue
    for method,path in re.findall(r"router\.(get|post|put|delete)\('([^']+)'",path.read_text(encoding='utf-8-sig')):
        for prefix in prefixes:
            route='/api/'+prefix+('' if path=='/' else path)
            pattern=re.sub(r':\w+',r'[^/]+',route)
            known.append((method,route,re.compile('^'+pattern+'$')))
for source in root.rglob('*.swift'):
    if '.validation-tools' in str(source): continue
    text=source.read_text()
    # Validate complete literal call/data routes; interpolated route fragments are checked by Xcode/device QA.
    for route in re.findall(r'(?:call|data)\("(/api/[^"]+)"',text):
        clean=re.sub(r'\\\([^)]*\)','1',route).split('?')[0]
        check(any(pattern.fullmatch(clean) for _,_,pattern in known),'backend route '+clean)

try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
    parser=Parser(Language(tree_sitter_swift.language()))
    for source in root.rglob('*.swift'):
        if '.validation-tools' in str(source): continue
        tree=parser.parse(source.read_bytes())
        check(not tree.root_node.has_error,'Swift grammar '+str(source.relative_to(root)))
except ImportError:
    print('Swift grammar check skipped: install tree-sitter and tree-sitter-swift to enable it.')

print(f'{len(checks)} structural checks passed; {len(failures)} failed.')
for failure in failures: print('FAIL:',failure)
print('Xcode compilation, simulator tests, signing and iPhone runtime verification: NOT RUN.')
sys.exit(bool(failures))

"""Create a self-contained Xcode project; no XcodeGen or package downloads required."""
from pathlib import Path
import hashlib, json
from PIL import Image

root = Path(__file__).resolve().parents[1]
project = root / 'Lutelier.xcodeproj'
project.mkdir(exist_ok=True)
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
objects = []
def obj(name, value):
    key = ident(name)
    objects.append(f'{key} = {{ {value} }};')
    return key
def refs(items): return '(' + ','.join(items) + ',)'
files = []
source_builds = []
for path in sorted((root/'Lutelier/Sources').glob('*.swift')):
    ref = obj(path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Lutelier/Sources/{path.name}"; sourceTree = SOURCE_ROOT;')
    files.append(ref)
    source_builds.append(obj(path.name+'build', f'isa = PBXBuildFile; fileRef = {ref};'))
test_ref = obj('testfile', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LutelierTests/RenderTests.swift; sourceTree = SOURCE_ROOT;')
test_build = obj('testbuild', f'isa = PBXBuildFile; fileRef = {test_ref};')
resources = []
for name, path, kind in [('Looks','Lutelier/Resources/Looks','folder'), ('Studio','Lutelier/Resources/Studio','folder'), ('Assets','Lutelier/Assets.xcassets','folder.assetcatalog')]:
    ref = obj(name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = SOURCE_ROOT;')
    files.append(ref)
    resources.append(obj(name+'build', f'isa = PBXBuildFile; fileRef = {ref};'))
app_product = obj('appproduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Lutelier.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = obj('testproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = LutelierTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = {refs([app_product,test_product])}; name = Products; sourceTree = "<group>";')
group = obj('main', f'isa = PBXGroup; children = {refs(files+[test_ref,products])}; sourceTree = "<group>";')
source_phase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resource_phase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resources)}; runOnlyForDeploymentPostprocessing = 0;')
framework_phase = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
test_phase = obj('testsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs([test_build])}; runOnlyForDeploymentPostprocessing = 0;')
project_configs=[]; app_configs=[]; test_configs=[]
for name in ['Debug','Release']:
    project_configs.append(obj('project'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 27.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if name=='Debug' else '-O')+'"; DEBUG_INFORMATION_FORMAT = "'+('dwarf' if name=='Debug' else 'dwarf-with-dsym')+'"; ENABLE_TESTABILITY = '+('YES' if name=='Debug' else 'NO')+'; };'))
    app_configs.append(obj('app'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ PRODUCT_NAME = Lutelier; PRODUCT_BUNDLE_IDENTIFIER = com.saeedsafikhani.lutelier; INFOPLIST_FILE = Lutelier/Info.plist; GENERATE_INFOPLIST_FILE = NO; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; ENABLE_PREVIEWS = YES; SWIFT_EMIT_LOC_STRINGS = YES; }};'))
    test_configs.append(obj('test'+name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ PRODUCT_NAME = LutelierTests; PRODUCT_BUNDLE_IDENTIFIER = com.saeedsafikhani.lutelier.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Lutelier.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Lutelier"; BUNDLE_LOADER = "$(TEST_HOST)"; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; }};'))
def config(name, ids): return obj(name, f'isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pc=config('projectconfigs',project_configs); ac=config('appconfigs',app_configs); tc=config('testconfigs',test_configs)
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {ac}; buildPhases = {refs([source_phase,framework_phase,resource_phase])}; buildRules = (); dependencies = (); name = Lutelier; productName = Lutelier; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Lutelier;')
dependency = obj('dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
test_target = obj('testtarget', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = {refs([test_phase])}; buildRules = (); dependencies = {refs([dependency])}; name = LutelierTests; productName = LutelierTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
pid = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; TargetAttributes = {{ {target} = {{CreatedOnToolsVersion = 26.0;}}; {test_target} = {{TestTargetID = {target};}}; }}; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([target,test_target])};')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {pid}; }}\n')
scheme_dir=project/'xcshareddata/xcschemes'; scheme_dir.mkdir(parents=True,exist_ok=True)
def buildref(key,name,filename): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{filename}" BlueprintName="{name}" ReferencedContainer="container:Lutelier.xcodeproj"/>'
appref=buildref(target,'Lutelier','Lutelier.app'); testref=buildref(test_target,'LutelierTests','LutelierTests.xctest')
(scheme_dir/'Lutelier.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{testref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
assets=root/'Lutelier/Assets.xcassets'
# App Store icons must have no alpha channel. Keep the original artwork in BrandIcon.
icon_path=assets/'AppIcon.appiconset/icon_1024.png'
Image.open(icon_path).convert('RGB').save(icon_path)
(assets/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}},indent=2))
(assets/'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images':[{'filename':'icon_1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'version':1,'author':'xcode'}},indent=2))
(assets/'BrandIcon.imageset/Contents.json').write_text(json.dumps({'images':[{'filename':'icon_1024.png','idiom':'universal'}],'info':{'version':1,'author':'xcode'}},indent=2))
print('Generated Lutelier.xcodeproj and shared test scheme')

#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
import hashlib
from pathlib import Path
from xml.sax.saxutils import escape
ROOT = Path(__file__).resolve().parents[1]
objects = {}
def ident(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def put(key, value):
    objects[ident(key)] = value
    return ident(key)
def q(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
def render(value):
    if isinstance(value, dict): return '{ ' + ' '.join(f'{k} = {render(v)};' for k,v in value.items()) + ' }'
    if isinstance(value, list): return '( ' + ', '.join(render(x) for x in value) + (',' if value else '') + ' )'
    return q(value)
project = ident('project')
main = ident('mainGroup')
products = ident('products')
package = put('package', {'isa':'XCLocalSwiftPackageReference','relativePath':'.'})
package_product = put('package-product', {'isa':'XCSwiftPackageProductDependency','package':package,'productName':'SmartWakeCore'})
package_build = put('package-build', {'isa':'PBXBuildFile','productRef':package_product})
product_refs = []
groups = []
targets = []

def configs(key, settings):
    ids=[]
    for name in ['Debug', 'Release']:
        actual=dict(settings)
        actual['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if name == 'Debug' else '-O'
        actual['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'
        if name == 'Debug': actual['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG $(inherited)'
        ids.append(put(key+name, {'isa':'XCBuildConfiguration', 'buildSettings':actual, 'name':name}))
    return put(key+'configs', {'isa':'XCConfigurationList','buildConfigurations':ids,'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Release'})

for name, folder, platform, bundle, family in [
    ('SmartWake','iPhoneApp','iphoneos','com.example.smartwake','1'),
    ('SmartWakeWatch','WatchApp','watchos','com.example.smartwake.watchkitapp','4')]:
    references=[]; builds=[]; resource_builds=[]
    for file in sorted((ROOT/folder).glob('*')):
        if file.suffix not in ['.swift','.plist','.entitlements','.xcprivacy','.xcassets']: continue
        filetype={'.swift':'sourcecode.swift','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.xcprivacy':'text.xml','.xcassets':'folder.assetcatalog'}[file.suffix]
        ref=put(str(file.relative_to(ROOT)),{'isa':'PBXFileReference','lastKnownFileType':filetype,'path':file.name,'sourceTree':'<group>'})
        references.append(ref)
        if file.suffix in ['.xcprivacy', '.xcassets']: resource_builds.append(put('resource'+str(file.relative_to(ROOT)),{'isa':'PBXBuildFile','fileRef':ref}))
        if file.suffix=='.swift': builds.append(put('build'+str(file.relative_to(ROOT)),{'isa':'PBXBuildFile','fileRef':ref}))
    groups.append(put(folder,{'isa':'PBXGroup','children':references,'path':folder,'sourceTree':'<group>'}))
    product=put(name+'product',{'isa':'PBXFileReference','explicitFileType':'wrapper.application','includeInIndex':'0','path':name+'.app','sourceTree':'BUILT_PRODUCTS_DIR'})
    product_refs.append(product)
    sources=put(name+'sources',{'isa':'PBXSourcesBuildPhase','buildActionMask':'2147483647','files':builds,'runOnlyForDeploymentPostprocessing':'0'})
    frameworks=put(name+'frameworks',{'isa':'PBXFrameworksBuildPhase','buildActionMask':'2147483647','files':[package_build] if platform=='iphoneos' else [],'runOnlyForDeploymentPostprocessing':'0'})
    resources=put(name+'resources',{'isa':'PBXResourcesBuildPhase','buildActionMask':'2147483647','files':resource_builds,'runOnlyForDeploymentPostprocessing':'0'})
    settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':bundle,'SDKROOT':platform,'SWIFT_VERSION':'5.0','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1.0','GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':folder+'/Info.plist','TARGETED_DEVICE_FAMILY':family,'ENABLE_PREVIEWS':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'SmartWakeIcon','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}
    if platform=='iphoneos': settings.update({'IPHONEOS_DEPLOYMENT_TARGET':'26.0','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO'})
    else:
        settings.update({'WATCHOS_DEPLOYMENT_TARGET':'26.0','SUPPORTED_PLATFORMS':'watchos watchsimulator','SKIP_INSTALL':'YES','COMPANION_APP_BUNDLE_IDENTIFIER':'com.example.smartwake','CODE_SIGN_ENTITLEMENTS':'WatchApp/SmartWakeWatch.entitlements'})
    target=put(name,{'isa':'PBXNativeTarget','buildConfigurationList':configs(name,settings),'buildPhases':[sources,frameworks,resources],'buildRules':[],'dependencies':[],'name':name,'packageProductDependencies':[package_product] if platform=='iphoneos' else [],'productName':name,'productReference':product,'productType':'com.apple.product-type.application'})
    targets.append(target)

# Embed the modern single-target watch app inside the companion iOS app.
watchbuild=put('embedwatchbuild',{'isa':'PBXBuildFile','fileRef':product_refs[1],'settings':{'ATTRIBUTES':['RemoveHeadersOnCopy']}})
embed=put('embedwatch',{'isa':'PBXCopyFilesBuildPhase','buildActionMask':'2147483647','dstPath':'$(CONTENTS_FOLDER_PATH)/Watch','dstSubfolderSpec':'16','files':[watchbuild],'name':'Embed Watch Content','runOnlyForDeploymentPostprocessing':'0'})
proxy=put('watchproxy',{'isa':'PBXContainerItemProxy','containerPortal':project,'proxyType':'1','remoteGlobalIDString':targets[1],'remoteInfo':'SmartWakeWatch'})
dep=put('watchdependency',{'isa':'PBXTargetDependency','target':targets[1],'targetProxy':proxy})
objects[targets[0]]['buildPhases'].append(embed)
objects[targets[0]]['dependencies'].append(dep)
put('products',{'isa':'PBXGroup','children':product_refs,'name':'Products','sourceTree':'<group>'})
put('mainGroup',{'isa':'PBXGroup','children':groups+[products],'sourceTree':'<group>'})
put('project',{'isa':'PBXProject','attributes':{'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2600'},'buildConfigurationList':configs('project',{'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','ALWAYS_SEARCH_USER_PATHS':'NO'}),'compatibilityVersion':'Xcode 14.0','developmentRegion':'en','hasScannedForEncodings':'0','knownRegions':['en','Base'],'mainGroup':main,'productRefGroup':products,'projectDirPath':'','projectRoot':'','packageReferences':[package],'targets':targets})
output=ROOT/'SmartWake.xcodeproj'; output.mkdir(exist_ok=True)
(output/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
scheme_dir=output/'xcshareddata'/'xcschemes'; scheme_dir.mkdir(parents=True,exist_ok=True)
for name,target in zip(['SmartWake','SmartWakeWatch'],targets):
    ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:SmartWake.xcodeproj"/>'
    (scheme_dir/(name+'.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')
print('Generated SmartWake.xcodeproj with iPhone and Watch targets.')

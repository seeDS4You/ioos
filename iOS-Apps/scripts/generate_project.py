"""Generate a text Xcode project on Windows or macOS without third-party tools."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OBJECTS = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def put(name, value):
    key = ident(name)
    OBJECTS[key] = value
    return key

def quote(value):
    return json.dumps(str(value))

def encode(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + quote(k) + " = " + encode(v, indent + 1) + ";\n" for k,v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, indent) for v in value) + ("," if value else "") + ")"
    return quote(value)

def configs(name, settings):
    refs = []
    for mode in ("Debug", "Release"):
        values = {**settings}
        values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"})
        if mode == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = str(values.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "$(inherited)")) + " DEBUG"
            values["ENABLE_TESTABILITY"] = "YES"
        refs.append(put(name + mode, {"isa":"XCBuildConfiguration", "name":mode, "buildSettings":values}))
    return put(name + "configlist", {"isa":"XCConfigurationList", "buildConfigurations":refs, "defaultConfigurationIsVisible":"0", "defaultConfigurationName":"Release"})

def phase(name, kind, files):
    refs = [put(name + path, {"isa":"PBXBuildFile", "fileRef": file_refs[path]}) for path in files]
    return put(name, {"isa":kind, "buildActionMask":"2147483647", "files":refs, "runOnlyForDeploymentPostprocessing":"0"})

roles = {"Staff":"SISSStaff", "Admin":"SISSAdmin", "Supervisor":"SISSSupervisor"}
sources = sorted(p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*.swift") if ".validation-tools" not in str(p))
resources = [f"Resources/{role}.xcassets" for role in roles]
file_refs = {}
for path in sources + resources:
    file_refs[path] = put("file:" + path, {"isa":"PBXFileReference", "lastKnownFileType":"folder.assetcatalog" if path.endswith("xcassets") else "sourcecode.swift", "path":path, "sourceTree":"<group>"})

products = []
targets = []
for role, target in roles.items():
    plist = {
        "CFBundleDevelopmentRegion":"en", "CFBundleExecutable":"$(EXECUTABLE_NAME)", "CFBundleIdentifier":"$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion":"6.0", "CFBundleName":"$(PRODUCT_NAME)", "CFBundleDisplayName": "Siss-Supervisor" if role == "Supervisor" else "SISS " + role,
        "CFBundlePackageType":"APPL", "CFBundleShortVersionString":"$(MARKETING_VERSION)", "CFBundleVersion":"$(CURRENT_PROJECT_VERSION)",
        "LSRequiresIPhoneOS":True, "UIApplicationSceneManifest":{"UIApplicationSupportsMultipleScenes":False},
        "UILaunchScreen": {}, "UISupportedInterfaceOrientations":["UIInterfaceOrientationPortrait"],
        "NSFaceIDUsageDescription":"Unlock your saved SISS session using Face ID.",
    }
    if role != "Staff":
        plist["NSCameraUsageDescription"] = "Scan staff shift QR codes " + ("to record attendance." if role == "Admin" else "to record your allocated team.")
    (ROOT / "Config").mkdir(exist_ok=True)
    (ROOT / "Config" / f"{role}.plist").write_bytes(plistlib.dumps(plist))
    settings = {
        "PRODUCT_BUNDLE_IDENTIFIER":f"com.siss.{role.lower()}", "PRODUCT_NAME":target,
        "MARKETING_VERSION":"1.0.0", "CURRENT_PROJECT_VERSION":"1", "SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0",
        "TARGETED_DEVICE_FAMILY":"1", "SDKROOT":"iphoneos", "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator",
        "CODE_SIGN_STYLE":"Automatic", "INFOPLIST_FILE":f"Config/{role}.plist", "GENERATE_INFOPLIST_FILE":"NO",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS":"$(inherited) " + role.upper(),
        "ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon", "ENABLE_USER_SCRIPT_SANDBOXING":"YES",
        "SUPPORTS_MACCATALYST":"NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD":"NO",
    }
    product = put(target + "product", {"isa":"PBXFileReference", "explicitFileType":"wrapper.application", "path":target + ".app", "sourceTree":"BUILT_PRODUCTS_DIR"})
    products.append(product)
    files = [p for p in sources if p.startswith("Shared/") or p.startswith(role + "/")]
    phases = [phase(target + "sources", "PBXSourcesBuildPhase", files), phase(target + "resources", "PBXResourcesBuildPhase", [f"Resources/{role}.xcassets"]), phase(target + "frameworks", "PBXFrameworksBuildPhase", [])]
    target_id = put(target + "target", {"isa":"PBXNativeTarget", "name":target, "productName":target, "productReference":product, "productType":"com.apple.product-type.application", "buildConfigurationList":configs(target, settings), "buildPhases":phases, "buildRules":[], "dependencies":[]})
    targets.append(target_id)

project_id = ident("project")
test_product = put("testsproduct", {"isa":"PBXFileReference", "explicitFileType":"wrapper.cfbundle", "path":"SISSContractTests.xctest", "sourceTree":"BUILT_PRODUCTS_DIR"})
products.append(test_product)
proxy = put("testproxy", {"isa":"PBXContainerItemProxy", "containerPortal":project_id, "proxyType":"1", "remoteGlobalIDString":ident("SISSSupervisortarget"), "remoteInfo":"SISSSupervisor"})
dependency = put("testdependency", {"isa":"PBXTargetDependency", "target":ident("SISSSupervisortarget"), "targetProxy":proxy})
testsettings = {"PRODUCT_BUNDLE_IDENTIFIER":"com.siss.contracttests", "PRODUCT_NAME":"SISSContractTests", "SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0", "SDKROOT":"iphoneos", "TARGETED_DEVICE_FAMILY":"1", "GENERATE_INFOPLIST_FILE":"YES", "TEST_HOST":"$(BUILT_PRODUCTS_DIR)/SISSSupervisor.app/SISSSupervisor", "BUNDLE_LOADER":"$(TEST_HOST)", "CODE_SIGN_STYLE":"Automatic"}
test_id = put("testtarget", {"isa":"PBXNativeTarget", "name":"SISSContractTests", "productName":"SISSContractTests", "productReference":test_product, "productType":"com.apple.product-type.bundle.unit-test", "buildConfigurationList":configs("Tests", testsettings), "buildPhases":[phase("testsources", "PBXSourcesBuildPhase", ["Tests/ContractTests.swift"]), phase("testframeworks", "PBXFrameworksBuildPhase", [])], "buildRules":[], "dependencies":[dependency]})
targets.append(test_id)
product_group = put("products", {"isa":"PBXGroup", "name":"Products", "children":products, "sourceTree":"<group>"})
main_group = put("main", {"isa":"PBXGroup", "children":list(file_refs.values()) + [product_group], "sourceTree":"<group>"})
OBJECTS[project_id] = {"isa":"PBXProject", "attributes":{"LastUpgradeCheck":"1600", "TargetAttributes":{test_id:{"TestTargetID":ident("SISSSupervisortarget")}}}, "buildConfigurationList":configs("Project", {"CLANG_ENABLE_MODULES":"YES", "SWIFT_VERSION":"5.0", "IPHONEOS_DEPLOYMENT_TARGET":"17.0"}), "compatibilityVersion":"Xcode 14.0", "developmentRegion":"en", "hasScannedForEncodings":"0", "knownRegions":["en", "Base"], "mainGroup":main_group, "productRefGroup":product_group, "projectDirPath":"", "projectRoot":"", "targets":targets}
project = ROOT / "SISSApps.xcodeproj"
(project / "xcshareddata/xcschemes").mkdir(parents=True, exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion":"1", "classes":{}, "objectVersion":"56", "objects":OBJECTS, "rootObject":project_id}) + "\n", encoding="utf-8")

for target in roles.values():
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    attrs = dict(BuildableIdentifier="primary", BlueprintIdentifier=ident(target + "target"), BuildableName=target + ".app", BlueprintName=target, ReferencedContainer="container:SISSApps.xcodeproj")
    ET.SubElement(entry, "BuildableReference", **attrs)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    if target == "SISSSupervisor":
        tests = ET.SubElement(test, "Testables")
        testable = ET.SubElement(tests, "TestableReference", skipped="NO")
        ET.SubElement(testable, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=test_id, BuildableName="SISSContractTests.xctest", BlueprintName="SISSContractTests", ReferencedContainer="container:SISSApps.xcodeproj")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    ET.SubElement(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "BuildableReference", **attrs)
    ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme)
    (project / "xcshareddata/xcschemes" / f"{target}.xcscheme").write_bytes(ET.tostring(scheme, encoding="utf-8", xml_declaration=True))
print("Generated SISSApps.xcodeproj with Staff, Admin, Supervisor and contract-test targets.")

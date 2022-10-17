// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:grinder/grinder.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

import "package:node_preamble/preamble.dart" as preamble;

/// Matches the version line in dart_style's pubspec.
final _versionPattern = RegExp(r'^version: .*$', multiLine: true);

void main(List<String> args) => grind(args);

@DefaultTask()
@Task()
Future<void> validate() async
{
    // Test it.
    await TestRunner().testAsync();

    // Make sure it's warning clean.
    Analyzer.analyze('bin/format.dart', fatalWarnings: true);

    // Format project.
    Dart.run('bin/format.dart', arguments: ["format", ".", "-s", "1", "-l", "90"]);

    // Check if we can get parse all dependencies versions used as constants.
    if (await getDependancyVersion("dart_style") == null)
    {
        throw "Cant parse all dependencies versions";
    }
}

@Task()
Future<void> validateCI() async
{
    // Test it.
    await TestRunner().testAsync();

    // Make sure it's warning clean.
    Analyzer.analyze('bin/format.dart', fatalWarnings: true);

    // Style is applied when bumping.
}

@Task('Compile to native, use --output=filename')
@Depends(validateCI)
Future<void> build() async
{
    TaskArgs args = context.invocation.arguments;
    var outName = args.getOption("output");
    var verbose = !args.getFlag("quiet");

    // Get base normalized output Dir and File name from input.
    var outPath = FilePath(outName);
    if (outPath.parent != null) outName = outPath.name;
    var basePath = outPath.parent?.path ?? "";
    var outDirPath = p.normalize(joinDir(buildDir, [basePath]).path);
    var outDir = getDir(outDirPath);

    // Get pubspec executable targets names
    var pubspecFile = getFile('pubspec.yaml');
    var pubspec = pubspecFile.readAsStringSync();
    var pubspecMap = yaml.loadYaml(pubspec) as yaml.YamlMap;
    var pubspecExecutables = pubspecMap["executables"] as yaml.YamlMap;
    var defaultOutName = pubspecExecutables.keys
        .firstWhere((k) => pubspecExecutables[k] == 'format', orElse: () => null);
    // Use default name from pubspec if not given
    outName ??= defaultOutName;

    // Setup file output to compile
    FilePath(outDir).createDirectory(recursive: true);
    var outFile = joinFile(outDir, [outName!]);
    var binFile = joinFile(binDir, ["format.dart"]);

    // There should be a Dart Compile method but there is not, so we run it manually.
    // (dart compile "-v" flag is not in help messages)
    run(dartVM.path,
        arguments: [
            "compile",
            "exe",
            binFile.path,
            "-o",
            outFile.path,
            verbose ? "-v" : "--verbosity=error"
        ],
        quiet: !verbose);
}

@Task('Compile to node js')
Future<void> node() async
{
    TaskArgs args = context.invocation.arguments;
    var bench = args.getFlag("benchmark");

    var out = 'build/node';

    var pubspecFile = getFile('pubspec.yaml');
    var pubspec = pubspecFile.readAsStringSync();
    var pubspecMap = yaml.loadYaml(pubspec) as Map;
    var repository = pubspecMap['repository'];

    var fileName = 'index.js';

    var outFile = File('$out/$fileName');
    Directory(out).createSync(recursive: true);
    Dart2js.compile(File('tool/node_format_service.dart'), outFile: outFile);

    var dart2jsOutput = outFile.readAsStringSync();
    outFile.writeAsStringSync('${preamble.getPreamble()}$dart2jsOutput');

    // Benchmark Test
    // 10x slower than Dart :(
    if (bench)
    {
        var tempFile = File('${Directory.systemTemp.path}/dart_polish_bench.js');
        Dart2js.compile(File('benchmark/js/benchmark_js.dart'), outFile: tempFile);

        var dart2jsBenOutput = tempFile.readAsStringSync();
        Directory(out).createSync(recursive: true);
        File('$out/bench.js')
            .writeAsStringSync('${preamble.getPreamble()}$dart2jsBenOutput');
    }

    File('$out/package.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'name': 'dart-polisher',
        'version': pubspecMap['version'],
        'description': pubspecMap['description'],
        'main': fileName,
        'typings': 'dart-polisher.d.ts',
        'scripts': {'test': 'echo "Error: no test specified" && exit 1'},
        'repository': {'type': 'git', 'url': 'git+$repository'},
        'author': 'xnfo',
        'license': 'BSD',
        'bugs': {'url': '$repository/issues'},
        'homepage': repository
    }));
    //run('npm', arguments: ['publish', out]);

    log("Package for node had been created in: ${Directory(out).absolute}");
}

/// Gets ready to publish a new version of the package.
///
/// To publish a version, you need to:
///
///   1. Make sure the version in the pubspec is a "-dev" number. This should
///      already be the case since you've already landed patches that change
///      the formatter and bumped to that as a consequence.
///
///   2. Commit the change to develop and Tag it for candidate to release: vX.X.X-betaY.
///
///   3. Merge to master
///
///      git merge --no-commit <BETA_TAG>
///      dart run grinder bump
///      git commit -a
///         Version $THE_VERSION_BEING_BUMPED
///         Merge commit '#DEV_HASH_TO_BASE_RELEASE_OFF' into master
///
///   4. Tag the commit:
///
///         git tag -a "<version>" -m "<version>"
///         git push origin <version>
///
///   5. Publish the package: (not for now)
///
///         pub lish
@Task()
@Depends(validate)
Future<void> bump() async
{
    // Read the version from the pubspec.
    var pubspecFile = getFile('pubspec.yaml');
    var pubspec = pubspecFile.readAsStringSync();
    var version = Version.parse((yaml.loadYaml(pubspec) as Map)['version'] as String);

    // Require a "-dev" version since we don't otherwise know what to bump it to.
    if (!version.isPreRelease) throw 'Cannot publish non-dev version $version.';

    // Don't allow versions like "1.2.3-dev+4" because it's not clear if the
    // user intended the "+4" to be discarded or not.
    if (version.build.isNotEmpty) throw 'Cannot publish build version $version.';

    var bumped = Version(version.major, version.minor, version.patch);

    // Update the version in the pubspec.
    pubspec = pubspec.replaceAll(_versionPattern, 'version: $bumped');
    pubspecFile.writeAsStringSync(pubspec);

    // Update the version constants in formatter_constants.dart.
    var versionFile = getFile('lib/src/dp_constants.dart');
    var versionSource = versionFile.readAsStringSync();
    var versionReplaced = updateVersionConstant(versionSource, "VERSION", bumped);
    // Update the version dependencies in dp_constants.dart.
    var dartStyleVersion = await getDependancyVersion("dart_style");
    if (dartStyleVersion != null)
    {
        versionReplaced = updateVersionConstant(
            versionReplaced, "DART_STYLE_DEP_VERSION", dartStyleVersion);
        versionFile.writeAsStringSync(versionReplaced);
    }
    versionFile.writeAsStringSync(versionReplaced);

    // Update the version in the CHANGELOG.
    // TODO(tekert): create bump header and move Unreleased header
    var changelogFile = getFile('CHANGELOG.md');
    var changelog = changelogFile
        .readAsStringSync()
        .replaceAll(version.toString(), bumped.toString());
    changelogFile.writeAsStringSync(changelog);

    log("Updated version to '$bumped'.");
}

String updateVersionConstant(String source, String constant, Version v)
{
    return source.replaceAll(RegExp("""const String $constant = "[^"]+";"""),
        """const String $constant = "$v";""");
}

Future<Version?> getDependancyVersion(String packageName) async
{
    var packageConfig = await findPackageConfig(Directory(""),
        recurse: false,
        onError: (error) => print("Could not find package config file: $error"));

    if (packageConfig == null) return null;

    Package package;
    try
    {
        package =
            packageConfig.packages.firstWhere((element) => element.name == packageName);
    }
    catch (e)
    {
        print("Package not found: $packageName");
        return null;
    }

    // Get the dependency package pubspec file.
    Version version;
    try
    {
        final pubspecFile = getFile(p.join(p.fromUri(package.root), 'pubspec.yaml'));
        final pubspec = pubspecFile.readAsStringSync();
        version = Version.parse((yaml.loadYaml(pubspec) as Map)['version'] as String);
    }
    catch (e)
    {
        print("Package $packageName pubspec.yaml: $e");
        return null;
    }

    return version;
}

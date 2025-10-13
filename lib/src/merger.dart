import 'dart:io' as dart_io;

import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart' as pubspec_parse;
import 'package:yaml_edit/yaml_edit.dart' as yaml_edit;

/// Class used for merging all of the available source code directories into a single file.
///
class ProjectMerger {
  /// Class used for merging all of the available source code directories into a single file,
  /// according to the provided [configuration].
  ///
  ProjectMerger({
    required Configuration configuration,
    required ObjectCollector collector,
  }) : _configuration = configuration,
       _collector = collector;

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// Property holding the value of the main object collector.
  ///
  final ObjectCollector _collector;

  /// Generates a new `pubspec.yaml` file using the `yaml_edit` package.
  ///
  void _generateMergedPubspecFile() {
    // Base template for the new pubspec file.
    final editor = yaml_edit.YamlEditor(
      [
        'name: merged_app',
        'description: A new merged application.',
        'version: 1.0.0+1',
        'publish_to: \'none\'',
        '',
        'environment:',
        '  sdk: \'>=3.0.0 <4.0.0\'',
        '',
        'dependencies:',
        '  flutter:',
        '    sdk: flutter',
        '',
        'dev_dependencies:',
        '  flutter_test:',
        '    sdk: flutter',
        '',
        'flutter:',
        '  uses-material-design: true',
      ].join(_configuration.formatter.lineEnding ?? '\n'),
    );

    /// Convert a [pubspec_parse.Dependency] object into
    /// a format suitable for the `yaml_edit` package.
    ///
    dynamic _dependencyToYamlNode(
      pubspec_parse.Dependency dep,
    ) {
      if (dep is pubspec_parse.HostedDependency) {
        return dep.version.toString();
      }
      if (dep is pubspec_parse.PathDependency) {
        return {
          'path': dep.path,
        };
      }
      if (dep is pubspec_parse.GitDependency) {
        return {
          'git': {
            'url': dep.url.toString(),
            if (dep.ref != null) 'ref': dep.ref,
            if (dep.path != null) 'path': dep.path,
          },
        };
      }
      if (dep is pubspec_parse.SdkDependency) {
        return {
          'sdk': dep.sdk,
        };
      }
      return {}; // Fallback for other types.
    }

    // Add merged dependencies
    _configuration.sourcePackageDependencies.forEach(
      (name, dep) {
        if (!_configuration.sourcePackages.any(
          (packageId) {
            return packageId == name;
          },
        )) {
          editor.update(
            ['dependencies', name],
            _dependencyToYamlNode(dep),
          );
        }
      },
    );
    _configuration.sourcePackageDevDependencies.forEach(
      (name, dep) {
        editor.update(
          ['dev_dependencies', name],
          _dependencyToYamlNode(dep),
        );
      },
    );
    _configuration.sourcePackageDependencyOverrides.forEach(
      (name, dep) {
        editor.update(
          ['dependency_overrides', name],
          _dependencyToYamlNode(dep),
        );
      },
    );

    // Merge the 'flutter' section (e.g., assets).
    final allAssets = <String>{}; // Use a Set to avoid duplicates
    if (_configuration.sourcePackageFlutterConfiguration != null) {
      final assets = _configuration.sourcePackageFlutterConfiguration!['assets'];
      if (assets is List) {
        allAssets.addAll(assets.cast<String>());
      }
    }
    if (allAssets.isNotEmpty) {
      editor.update(['flutter', 'assets'], allAssets.toList());
    }

    // Write the final result to a file
    final outputFile = _configuration.mergedPubspecFile;
    outputFile.writeAsStringSync(
      editor.toString(),
    );
  }

  /// Outputs all of the [Configuration.sourceDirectories] contents to a single file.
  ///
  Future<void> generateMergedProject() async {
    // File contents string buffer.
    final fileBuffer = StringBuffer();

    // Source code definitions.
    final importSources = <String>{};
    final codeSources = <List<String>>[];

    // Collect the source code lines.
    final directoryFiles = _configuration.sourceDirectoriesCopy
        .listSync(
          recursive: true,
          followLinks: true,
        )
        .whereType<dart_io.File>()
        .where(
          (file) {
            return file.path.endsWith('.dart');
          },
        );
    final copiedDirectoriesLibFolders = _configuration.sourceDirectoriesCopy.listSync().whereType<dart_io.Directory>().map(
      (directory) {
        return path.join(directory.path, 'lib');
      },
    );
    for (final file in directoryFiles) {
      if (copiedDirectoriesLibFolders.any(file.path.contains)) {
        final codeSource = await file.readAsString();
        final codeSourceLines = codeSource.split(dart_io.Platform.lineTerminator);
        final sources = <String>[];
        for (final line in codeSourceLines) {
          if (line.startsWith('import')) {
            importSources.add(line);
          } else if (importSources.isNotEmpty && !importSources.last.trimRight().endsWith(';')) {
            final newImportValue = '${importSources.last}$line';
            importSources.remove(importSources.last);
            importSources.add(newImportValue);
          } else if (!const {
            'import \'',
            'part \'',
            'part of \'',
            'export \'',
            'library;',
            'library \'',
            '//',
          }.any(line.trimLeft().startsWith)) {
            sources.add(line);
          }
        }
        codeSources.add(sources);
      }
    }

    // Record the import sources.
    for (final importSource in _collector.objectDeclarationCollector.importSources) {
      if (_configuration.sourcePackages.every(
        (packageName) {
          return !importSource.contains('package:$packageName/');
        },
      )) {
        fileBuffer.writeln(
          importSource,
        );
      }
    }

    // Record source code.
    for (final sourceLines in codeSources) {
      for (final line in sourceLines) {
        fileBuffer.writeln(line);
      }
      fileBuffer.writeln();
    }

    // Format available output data.
    String formattedCode = fileBuffer.toString();
    try {
      formattedCode = _configuration.formatter.format(
        formattedCode,
      );
    } catch (e) {
      print('Formatter failed:\n$e');
    }

    // Record the outputs to a file.
    await _configuration.outputMergedFile.writeAsString(
      formattedCode,
    );

    // Record the merged `pubspec.yaml` file and run package setup.
    _generateMergedPubspecFile();

    // Run the `flutter pub get` command for the merged project.
    await dart_io.Process.run(
      'flutter',
      const ['pub', 'get'],
      workingDirectory: _configuration.sourceDirectoriesCopy.path,
    );
  }
}

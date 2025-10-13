import 'dart:io' as dart_io;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart' as analyzer_context;
import 'package:args/args.dart' as args;
import 'package:dart_style/dart_style.dart' as dart_style;
import 'package:path/path.dart' as path;
import 'package:obfuscator/src/annotation.dart';
import 'package:pubspec_parse/pubspec_parse.dart' as pubspec_parse;

/// Object defining the basic input options for the obfuscation service.
///
class Configuration {
  /// Creates an instance of the obfuscation run configuration using the command line [arguments].
  ///
  Configuration.fromArguments({
    required List<String> arguments,
  }) : _arguments = arguments;

  /// Command line interface arguments.
  ///
  final List<String> _arguments;

  /// Validate and retrieve the CLI arguments.
  ///
  ({String sourceDirectoriesArg, String outputDirectoryArg, String? publicApiAnnotationsArg}) _processArguments(
    List<String> arguments,
  ) {
    // Define argument identifiers.
    const sourceDirectoriesId = 'sourceDirectories';
    const outputDirectoryId = 'outputDirectory';
    const publicApiAnnotationsId = 'publicApiAnnotations';

    // Instantiate and setup argument parser.
    final argumentParser = args.ArgParser(
      allowTrailingOptions: true,
    );
    for (final argument in <({String id, String alias, String help, bool mandatory})>{
      (
        id: sourceDirectoriesId,
        alias: 'src',
        help: 'Comma-separated directories in which source files to be obfuscated are placed (e.g., "./lib/,./other_lib/").',
        mandatory: true,
      ),
      (
        id: outputDirectoryId,
        alias: 'out',
        help: 'The output directory of the obfuscation command (e.g., "./build/").',
        mandatory: true,
      ),
      (
        id: publicApiAnnotationsId,
        alias: 'pub',
        help:
            'Optional annotation identifier for the classes marked as not to be obfuscated. '
            'Defaults to the "DontObfuscate" annotation provided by the library.',
        mandatory: false,
      ),
    }) {
      argumentParser.addOption(
        argument.id,
        aliases: [argument.alias],
        help: argument.help,
        mandatory: argument.mandatory,
      );
    }
    final cliArguments = argumentParser.parse(arguments);

    // Validate and return argument values.
    final sourceDirectoriesArg = cliArguments.option(sourceDirectoriesId);
    final outputDirectoryArg = cliArguments.option(outputDirectoryId);
    final publicApiAnnotationsArg = cliArguments.option(publicApiAnnotationsId);
    return (
      sourceDirectoriesArg: sourceDirectoriesArg!,
      outputDirectoryArg: outputDirectoryArg!,
      publicApiAnnotationsArg: publicApiAnnotationsArg,
    );
  }

  /// Comma-separated directory paths in which source files to be obfuscated are placed (e.g., `"./lib/,./other_lib/"`).
  ///
  late List<dart_io.Directory> sourceDirectories;

  /// Set and validate the source directories fields.
  ///
  void _initialiseSourceDirectories({
    required String sourceDirectoriesArg,
  }) {
    final sourceDirectoriesPaths = sourceDirectoriesArg.split(',');
    sourceDirectories = sourceDirectoriesPaths.map(
      (dirPath) {
        return dart_io.Directory(dirPath);
      },
    ).toList();
  }

  /// The output directory of the obfuscation command (e.g., `"./build/"`).
  ///
  late dart_io.Directory outputDirectory;

  /// Create and reset any current output directory state.
  ///
  void _initialiseOutputDirectory({
    required String outputDirectoryArg,
  }) {
    outputDirectory = dart_io.Directory(outputDirectoryArg);
    try {
      outputDirectory.deleteSync(
        recursive: true,
      );
    } catch (e) {
      // No output folder is present.
    }
    outputDirectory.createSync(
      recursive: true,
    );
  }

  /// Directory where the source code files are copied to.
  ///
  late dart_io.Directory sourceDirectoriesCopy;

  /// Define locations and copy source code directories to the newly-created `copy` folder.
  ///
  Future<void> _initialiseSourceDirectoriesCopy() async {
    /// Helper method to recursively copy a directory's contents.
    ///
    Future<void> _copyDirectorySync({
      required dart_io.Directory source,
      required dart_io.Directory destination,
    }) async {
      if (!destination.existsSync()) {
        destination.createSync(recursive: true);
      }
      for (final entity in source.listSync()) {
        final newPath = path.join(destination.path, path.basename(entity.path));
        if (entity is dart_io.File) {
          if (path.basename(entity.path) == 'pubspec.yaml') {
            // Remove `resolution: workspace` if detected.
            try {
              String content = entity.readAsStringSync();
              final pattern = RegExp(r'^\s*resolution:\s*workspace\s*$', multiLine: true);
              String newContent = content.replaceAll(pattern, '');
              dart_io.File(newPath)..writeAsStringSync(newContent);
            } catch (e) {
              print('Error processing pubspec.yaml at ${entity.path}: $e');
              entity.copySync(newPath);
            }
          } else {
            entity.copySync(newPath);
          }
        } else if (entity is dart_io.Directory) {
          _copyDirectorySync(
            source: entity,
            destination: dart_io.Directory(newPath),
          );
        }
      }
    }

    final sourceDirectoriesCopyPath = path.join(
      outputDirectory.path,
      'copy',
    );
    sourceDirectoriesCopy = dart_io.Directory(
      sourceDirectoriesCopyPath,
    );
    sourceDirectoriesCopy.createSync(
      recursive: true,
    );
    for (final directory in sourceDirectories) {
      final copiedDirectoryPath = path.join(
        sourceDirectoriesCopyPath,
        path.basename(directory.path),
      );
      final copiedDirectory = dart_io.Directory(
        copiedDirectoryPath,
      );
      _copyDirectorySync(
        source: directory,
        destination: copiedDirectory,
      );
      try {
        await dart_io.Process.run(
          'flutter',
          const ['pub', 'get'],
          workingDirectory: copiedDirectory.path,
        );
      } catch (e) {
        print('Error running flutter pub get in ${copiedDirectory.path}');
      }
    }
  }

  /// File definition for object mappings.
  ///
  late dart_io.File outputMappingsFile;

  /// Allocate output mappings file resources.
  ///
  void _initialiseOutputMappingsFile() {
    final outputMappingsFilePath = path.join(
      outputDirectory.path,
      'mappings.json',
    );
    outputMappingsFile = dart_io.File(
      outputMappingsFilePath,
    );
    outputMappingsFile.createSync(
      recursive: true,
    );
  }

  /// File definition of the merged code file.
  ///
  late dart_io.File outputMergedFile;

  /// Allocate output merged file resources.
  ///
  void _initialiseOutputMergedFile() {
    final outputMergedFilePath = path.join(
      outputDirectory.path,
      'lib',
      'merged.dart',
    );
    outputMergedFile = dart_io.File(
      outputMergedFilePath,
    );
    outputMergedFile.createSync(
      recursive: true,
    );
  }

  /// Set and validate the output directory location and any other relevant fields.
  ///
  Future<void> _initialiseOutputSpecifications({
    required String outputDirectoryArg,
  }) async {
    _initialiseOutputDirectory(
      outputDirectoryArg: outputDirectoryArg,
    );
    await _initialiseSourceDirectoriesCopy();
    _initialiseOutputMappingsFile();
    _initialiseOutputMergedFile();
  }

  /// Optional annotation identifiers for the classes marked as not to be obfuscated.
  ///
  /// Defaults to the [NoObfuscation] annotation provided by the library.
  ///
  final publicApiAnnotations = <String>[
    (NoObfuscation).toString(),
  ];

  /// Set and validate the public API annotation collection.
  ///
  void _initialisePublicApiAnnotations({
    required String? publicApiAnnotationsArg,
  }) {
    if (publicApiAnnotationsArg != null) {
      final specifiedAnnotations = publicApiAnnotationsArg.split(',');
      publicApiAnnotations.addAll(specifiedAnnotations);
    }
  }

  /// The identifiers of the package to be obfuscated, derived from the `pubspec.yaml` file.
  ///
  final sourcePackages = <String>[];

  /// Appends a [packageId] value to the [sourcePackages] collection.
  ///
  void _initialiseSourcePackages({
    required String packageId,
  }) {
    sourcePackages.add(packageId);
  }

  /// Collection of dependencies defined with the source package implementations.
  ///
  final sourcePackageDependencies = <String, pubspec_parse.Dependency>{},
      sourcePackageDevDependencies = <String, pubspec_parse.Dependency>{},
      sourcePackageDependencyOverrides = <String, pubspec_parse.Dependency>{};

  /// Optional configuration specific to Flutter packages.
  ///
  /// May include assets and other settings.
  ///
  Map<String, dynamic>? sourcePackageFlutterConfiguration;

  /// File definition for the merged `pubspec.yaml` file, derived from [sourcePackages].
  ///
  late dart_io.File mergedPubspecFile;

  /// Set and validate the source packages fields.
  ///
  void _processYamlFiles() {
    for (final directory in sourceDirectories) {
      if (!directory.existsSync()) {
        print('Source root "${directory.path}" not found.');
        dart_io.exit(1);
      }
      final pubspecFilePath = path.join(directory.path, 'pubspec.yaml');
      final pubspecFile = dart_io.File(pubspecFilePath);
      final pubspecFileContents = pubspecFile.readAsStringSync();
      final pubspecParser = pubspec_parse.Pubspec.parse(pubspecFileContents);
      _initialiseSourcePackages(
        packageId: pubspecParser.name,
      );
      sourcePackageDependencies.addAll(
        pubspecParser.dependencies,
      );
      sourcePackageDevDependencies.addAll(
        pubspecParser.devDependencies,
      );
      sourcePackageDependencyOverrides.addAll(
        pubspecParser.dependencyOverrides,
      );
      sourcePackageFlutterConfiguration = pubspecParser.flutter;
    }
    final mergedPubspecFilePath = path.join(
      outputDirectory.path,
      'pubspec.yaml',
    );
    mergedPubspecFile = dart_io.File(
      mergedPubspecFilePath,
    );
  }

  /// A collection of analysis contexts.
  ///
  late analyzer_context.AnalysisContextCollection analysisContextCollection;

  /// Assign the analysis context collection values.
  ///
  void _initialiseAnalysisContextCollections() {
    final sourceCopyDirectories = sourceDirectoriesCopy.listSync().whereType<dart_io.Directory>();
    analysisContextCollection = analyzer_context.AnalysisContextCollection(
      includedPaths: sourceCopyDirectories.map(
        (package) {
          return path.join(package.path, 'lib');
        },
      ).toList(),
    );
  }

  /// Dart code formatter.
  ///
  final formatter = dart_style.DartFormatter(
    lineEnding: '\n',
    trailingCommas: dart_style.TrailingCommas.preserve,
    languageVersion: dart_style.DartFormatter.latestLanguageVersion,
  );

  /// Instantiate required class resources.
  ///
  Future<void> init() async {
    final args = _processArguments(_arguments);
    _initialiseSourceDirectories(
      sourceDirectoriesArg: args.sourceDirectoriesArg,
    );
    await _initialiseOutputSpecifications(
      outputDirectoryArg: args.outputDirectoryArg,
    );
    _initialisePublicApiAnnotations(
      publicApiAnnotationsArg: args.publicApiAnnotationsArg,
    );
    _processYamlFiles();
    _initialiseAnalysisContextCollections();
  }
}

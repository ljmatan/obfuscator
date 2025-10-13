import 'dart:io' as dart_io;

import 'package:analyzer/dart/analysis/results.dart' as analyzer_results;
import 'package:analyzer/dart/ast/ast.dart' as analyzer_ast;
import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:obfuscator/src/extensions.dart';
import 'package:package_config/package_config.dart' as package_config;
import 'package:obfuscator/src/config.dart';
import 'package:obfuscator/src/declarations.dart';
import 'package:obfuscator/src/references.dart';

/// Dart source code file reference.
///
class ObjectCollectorSource {
  /// Constructs a new reference of the object collector source [file].
  ///
  ObjectCollectorSource({
    required this.file,
    required this.resolvedUnitResult,
  });

  /// A reference to the source file on the file system.
  ///
  final dart_io.File file;

  /// The result of building a resolved AST for a source file.
  ///
  final analyzer_results.ResolvedUnitResult resolvedUnitResult;
}

/// Class implemented for collecting object declarations and their respective references.
///
class ObjectCollector {
  /// Generates a new instance of the object declaration collector.
  ///
  /// Project [configuration] is provided with the constructor
  /// in order to determine `visitor` specifications.
  ///
  ObjectCollector({
    required Configuration configuration,
  }) : _configuration = configuration {
    objectDeclarationCollector = ObjectDeclarationCollector(
      collector: this,
      configuration: configuration,
    );
    objectReferenceCollector = ObjectReferenceCollector(
      collector: this,
      configuration: configuration,
    );
  }

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// An AST visitor that will recursively visit all of the nodes in an AST structure.
  ///
  /// Defined for collecting of the declaration references for obfuscating.
  ///
  late ObjectDeclarationCollector objectDeclarationCollector;

  /// An AST visitor that will recursively visit all of the nodes in an AST structure.
  ///
  /// Defined for collecting of the object references for obfuscating.
  ///
  late ObjectReferenceCollector objectReferenceCollector;

  /// Results of parsing [dartFiles] as [ObjectCollectorSource] types.
  ///
  final objectCollectorSources = <ObjectCollectorSource>[];

  /// Index of the [objectCollectorSources] currently being processed by the `visitors`.
  ///
  int? _objectCollectorSourcesProcessingIndex;

  /// Value from the [objectCollectorSources] which is currently being processed by the `visitors`.
  ///
  ObjectCollectorSource get currentObjectCollectorSource {
    if (_objectCollectorSourcesProcessingIndex == null) {
      throw Exception(
        'No object collector source is currently being processed.',
      );
    }
    return objectCollectorSources[_objectCollectorSourcesProcessingIndex!];
  }

  /// Searches the AST structure for [node] parent [InterfaceElement].
  ///
  analyzer_element.InterfaceElement? getParentElement(
    analyzer_ast.AstNode node,
  ) {
    dynamic parent = node.parent;
    while (parent != null) {
      if (parent is analyzer_ast.ClassDeclaration) {
        return parent.declaredFragment?.element;
      }
      if (parent is analyzer_ast.EnumDeclaration) {
        return parent.declaredFragment?.element;
      }
      if (parent is analyzer_ast.MixinDeclaration) {
        return parent.declaredFragment?.element;
      }
      parent = parent.parent;
    }
    return null;
  }

  /// Method used for retrieving of the parent object declaration.
  ///
  String? getParentId(
    analyzer_ast.AstNode node,
  ) {
    return getParentElement(node)?.lookupName;
  }

  /// Determines the parent name of a local function.
  ///
  String? getEnclosingFunctionName(
    analyzer_ast.AstNode node,
  ) {
    var current = node.parent;
    while (current != null) {
      if (current is analyzer_ast.MethodDeclaration) {
        return current.name.lexeme; // Declared inside of a class.
      }
      if (current is analyzer_ast.FunctionDeclaration) {
        // Only return if it is a top-level function.
        if (current.parent is analyzer_ast.CompilationUnit) {
          return current.name.lexeme;
        }
        // Otherwise, skip local functions.
      }
      current = current.parent;
    }
    return null;
  }

  /// Collect and store source code information.
  ///
  Future<void> _collectSources() async {
    for (final analyzedContext in _configuration.analysisContextCollection.contexts) {
      for (final filePath in analyzedContext.contextRoot.analyzedFiles()) {
        if (filePath.endsWith('.dart')) {
          final session = analyzedContext.currentSession;
          final resolvedUnit =
              await session.getResolvedUnit(
                    filePath,
                  )
                  as analyzer_results.ResolvedUnitResult;
          objectCollectorSources.add(
            ObjectCollectorSource(
              file: dart_io.File(filePath),
              resolvedUnitResult: resolvedUnit,
            ),
          );
        }
      }
    }
  }

  /// Process source code information to extract any relevant data.
  ///
  void _visitUnits() {
    for (final source in objectCollectorSources.indexed) {
      _objectCollectorSourcesProcessingIndex = source.$1;
      for (final collector in objectDeclarationCollector.collectors) {
        source.$2.resolvedUnitResult.unit.visitChildren(collector);
      }
      for (final collector in objectReferenceCollector.collectors) {
        source.$2.resolvedUnitResult.unit.visitChildren(collector);
      }
    }
    _objectCollectorSourcesProcessingIndex = null;
    if (objectDeclarationCollector.collection.isEmpty) {
      print('No object declarations to obfuscate.');
      dart_io.exit(1);
    }
    if (objectReferenceCollector.collection.isEmpty) {
      print('No object references found.');
      dart_io.exit(1);
    }
  }

  /// Compares elements by their library URI and display name to verify if they're identical.
  ///
  Future<bool> _isSameElement(
    analyzer_element.Element? a,
    analyzer_element.Element? b,
  ) async {
    if (a?.library?.uri == null || b?.library?.uri == null) return false;

    Future<String?> normalizeLibraryUri(
      analyzer_element.Element e,
    ) async {
      if (e.library?.uri == null) return null;
      if (e.library!.uri.scheme == 'package') {
        return e.library!.uri.toString();
      }
      final packageConfig = await package_config.findPackageConfig(
        dart_io.File(e.library!.uri.toString()).parent,
      );
      final pkgUri = packageConfig?.toPackageUri(e.library!.uri);
      if (pkgUri != null) return pkgUri.toString();
      return e.library!.uri.toString();
    }

    try {
      return await normalizeLibraryUri(a!) == await normalizeLibraryUri(b!) &&
          (a.name != null && a.name == b.name || a.displayName.isNotEmpty && a.displayName == b.displayName);
    } catch (e) {
      return false;
    }
  }

  /// Clears any duplicate declaration entries.
  ///
  Future<void> _clearDuplicateDeclarationEntries() async {
    final uniqueDeclarationsIds = <({analyzer_element.Element element, String parentId, String lexeme})>[];
    final uniqueDeclarations = <ObjectDeclaration>[];
    for (final declaration in objectDeclarationCollector.collection) {
      if (declaration.element?.metadata.isOverriden != true &&
          declaration.element != null &&
          declaration.parentId != null &&
          declaration.lexeme != null) {
        if (!uniqueDeclarationsIds.any(
          (declarationId) {
            return declarationId.lexeme == declaration.lexeme && declarationId.parentId == declaration.parentId;
          },
        )) {
          uniqueDeclarationsIds.add(
            (
              element: declaration.element!,
              parentId: declaration.parentId!,
              lexeme: declaration.lexeme!,
            ),
          );
        }
      }
    }
    for (final uniqueDeclarationId in uniqueDeclarationsIds) {
      final relevantDeclarations = <ObjectDeclaration>[];
      for (final declaration in objectDeclarationCollector.collection) {
        final isMatching =
            declaration.lexeme != null &&
            declaration.lexeme == uniqueDeclarationId.lexeme &&
            declaration.parentId != null &&
            declaration.parentId == uniqueDeclarationId.parentId &&
            declaration.element != null &&
            await _isSameElement(declaration.element, uniqueDeclarationId.element);
        if (isMatching) {
          relevantDeclarations.add(declaration);
        }
      }
      uniqueDeclarations.add(
        ObjectDeclaration(
            filePath: relevantDeclarations.first.filePath,
            element: relevantDeclarations.first.element,
            parentId: relevantDeclarations.first.parentId,
            lexeme: relevantDeclarations.first.lexeme,
            type: relevantDeclarations.first.type,
            offset: -1,
          )
          ..references.removeAt(0)
          ..references.addAll(
            [
              for (final declaration in relevantDeclarations) ...declaration.references,
            ],
          ),
      );
    }
    objectDeclarationCollector.collection.clear();
    objectDeclarationCollector.collection.addAll(uniqueDeclarations);
  }

  /// Updates the [ObjectDeclarationCollector.collection] with reference file paths and offsets.
  ///
  Future<void> _appendReferenceOffsets() async {
    for (final reference in objectReferenceCollector.collection) {
      for (final declaration in objectDeclarationCollector.collection) {
        final isMatching =
            declaration.lexeme != null &&
            declaration.lexeme == reference.lexeme &&
            declaration.parentId != null &&
            declaration.parentId == reference.parentId &&
            declaration.element != null &&
            await _isSameElement(declaration.element, reference.parentElement);
        if (isMatching &&
            !declaration.references.any(
              (recordedReference) {
                return recordedReference.filePath == reference.filePath && recordedReference.offset == reference.offset;
              },
            )) {
          declaration.references.add(reference);
          break;
        }
      }
    }
  }

  /// Use the given `visitor` objects to visit all of the specified file contents.
  ///
  Future<void> processUnits() async {
    objectDeclarationCollector.collection.clear();
    objectReferenceCollector.collection.clear();
    objectCollectorSources.clear();
    await _collectSources();
    _visitUnits();
    await _clearDuplicateDeclarationEntries();
    await _appendReferenceOffsets();
    await _configuration.analysisContextCollection.dispose();
  }
}

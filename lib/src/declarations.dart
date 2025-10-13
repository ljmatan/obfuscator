import 'package:analyzer/dart/ast/ast.dart' as analyzer_ast;
import 'package:analyzer/dart/ast/visitor.dart' as analyzer_visitor;
import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:obfuscator/src/extensions.dart';
import 'package:obfuscator/src/references.dart';

/// Object declaration definitions.
///
class ObjectDeclaration {
  /// Constructs an instance of an object declaration with parameters required for processing.
  ///
  ObjectDeclaration({
    required this.filePath,
    required this.element,
    required this.parentId,
    required this.lexeme,
    required this.type,
    required this.offset,
  }) : references = [
         ObjectReference(
           filePath: filePath,
           parentElement: element,
           parentId: parentId,
           lexeme: lexeme,
           offset: offset,
         ),
       ];

  /// Path of the file containing the relevant reference.
  ///
  final String filePath;

  /// Declaring object semantic model.
  ///
  final analyzer_element.Element? element;

  /// Identifier for the object holding this property (i.e., class, enum or extension name).
  ///
  final String? parentId;

  /// Unit of lexical meaning that underlies a set of words that are related through inflection.
  ///
  final String? lexeme;

  /// Object runtime type.
  ///
  final Type type;

  /// Offset from the beginning of the file to the first character in the syntactic entity.
  ///
  final int offset;

  /// Collection of object references and their positions within a file.
  ///
  final List<ObjectReference> references;
}

/// An AST visitor that will recursively visit all of the nodes in an AST structure.
///
/// Defined for collecting of the declaration references for obfuscating.
///
class ObjectDeclarationCollector {
  /// Generates a new instance of the object declaration collector.
  ///
  /// Project [configuration] is provided with the constructor
  /// in order to determine `visitor` specifications.
  ///
  ObjectDeclarationCollector({
    required ObjectCollector collector,
    required Configuration configuration,
  }) : _collector = collector,
       _configuration = configuration {
    collectors = [
      _ObjectDeclarationCollectorImports(
        declarationCollector: this,
      ),
      _ObjectDeclarationCollectorTopLevel(
        declarationCollector: this,
      ),
      _ObjectDeclarationCollectorMethodsFunctions(
        declarationCollector: this,
      ),
      _ObjectDeclarationCollectorFields(
        declarationCollector: this,
      ),
    ];
  }

  /// Property holding the value of the main object collector.
  ///
  final ObjectCollector _collector;

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// Collection of declaration collectors with specific object targets.
  ///
  late List<analyzer_visitor.RecursiveAstVisitor> collectors;

  /// Whether an object is marked as not requiring obfuscation.
  ///
  bool _hasPublicApiAnnotationOrExcludedName(
    analyzer_ast.AnnotatedNode node,
  ) {
    for (var meta in node.metadata) {
      if (_configuration.publicApiIdentifiers.any(
        (annotationName) => meta.name.name.contains(annotationName),
      )) {
        return true;
      }
    }
    final declaredName = (node is analyzer_ast.ClassDeclaration)
        ? node.name.lexeme
        : (node is analyzer_ast.MixinDeclaration)
        ? node.name.lexeme
        : (node is analyzer_ast.EnumDeclaration)
        ? node.name.lexeme
        : (node is analyzer_ast.VariableDeclaration)
        ? node.name.lexeme
        : null;
    if (declaredName != null &&
        _configuration.publicApiIdentifiers.any(
          (id) {
            return id == declaredName;
          },
        )) {
      return true;
    }
    return false;
  }

  /// Collection of import directives defined in the specified [Configuration.sourceDirectories].
  ///
  final importSources = <String>{};

  /// Collection of declarations collected by a class instance.
  ///
  final collection = <ObjectDeclaration>{};
}

/// Import statements.
///
class _ObjectDeclarationCollectorImports extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectDeclarationCollectorImports({
    required ObjectDeclarationCollector declarationCollector,
  }) : _declarationCollector = declarationCollector;

  final ObjectDeclarationCollector _declarationCollector;

  @override
  void visitImportDirective(
    analyzer_ast.ImportDirective node,
  ) {
    if (node.libraryImport?.importedLibrary != null) {
      _declarationCollector.importSources.add(
        'import \'${node.libraryImport?.importedLibrary?.uri}\'' +
            (node.prefix?.name.isNotEmpty == true ? ' as ${node.prefix!.name}' : '') +
            ';',
      );
    }
    super.visitImportDirective(node);
  }
}

/// Classes, constructors, enums, mixins, extensions.
///
class _ObjectDeclarationCollectorTopLevel extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectDeclarationCollectorTopLevel({
    required ObjectDeclarationCollector declarationCollector,
  }) : _declarationCollector = declarationCollector;

  final ObjectDeclarationCollector _declarationCollector;

  @override
  void visitClassDeclaration(
    analyzer_ast.ClassDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.element,
          parentId: node.name.lexeme,
          lexeme: node.name.lexeme,
          type: analyzer_ast.ClassDeclaration,
          offset: node.name.offset,
        ),
      );
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(
    analyzer_ast.ConstructorDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node) &&
        node.name?.lexeme.isNotEmpty == true &&
        node.name?.lexeme != '_') {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.enclosingFragment?.element,
          parentId: node.declaredFragment?.name,
          lexeme: node.name!.lexeme,
          type: analyzer_ast.ConstructorDeclaration,
          offset: node.name!.offset,
        ),
      );
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitEnumDeclaration(
    analyzer_ast.EnumDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.element,
          parentId: node.name.lexeme,
          lexeme: node.name.lexeme,
          type: analyzer_ast.EnumDeclaration,
          offset: node.name.offset,
        ),
      );
    }
    super.visitEnumDeclaration(node);
  }

  @override
  void visitMixinDeclaration(
    analyzer_ast.MixinDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.element,
          parentId: node.name.lexeme,
          lexeme: node.name.lexeme,
          type: analyzer_ast.MixinDeclaration,
          offset: node.name.offset,
        ),
      );
    }
    super.visitMixinDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(
    analyzer_ast.ExtensionDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.element,
          parentId: node.name?.lexeme,
          lexeme: node.name?.lexeme,
          type: analyzer_ast.ExtensionDeclaration,
          offset: node.name?.offset ?? -1,
        ),
      );
    }
    super.visitExtensionDeclaration(node);
  }
}

class _ObjectDeclarationCollectorMethodsFunctions extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectDeclarationCollectorMethodsFunctions({
    required ObjectDeclarationCollector declarationCollector,
  }) : _declarationCollector = declarationCollector;

  final ObjectDeclarationCollector _declarationCollector;

  @override
  void visitMethodDeclaration(
    analyzer_ast.MethodDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      final isOverriden = node.declaredFragment?.element.metadata.isOverriden == true;
      final enclosingElement = isOverriden ? node.declaredFragment?.element.enclosingElement : null;
      final parent = enclosingElement is analyzer_element.InterfaceElement
          ? enclosingElement.getSupertypeWithMethod(
              objectCollectorSources: _declarationCollector._collector.objectCollectorSources,
              packageIds: _declarationCollector._configuration.sourcePackages,
              referenceElement: node.declaredFragment?.element,
            )
          : null;
      final parentElement = parent?.getMethodElement(
        referenceElement: node.declaredFragment?.element,
      );
      if (!isOverriden || parent?.name != null) {
        _declarationCollector.collection.add(
          ObjectDeclaration(
            filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
            element: parentElement ?? node.declaredFragment?.element,
            parentId: parent?.name ?? _declarationCollector._collector.getParentId(node),
            lexeme: node.name.lexeme,
            type: analyzer_ast.MethodDeclaration,
            offset: node.name.offset,
          ),
        );
      }
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(
    analyzer_ast.FunctionDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      final parentId = _declarationCollector._collector.getEnclosingFunctionName(node);
      if (parentId != null) {
        _declarationCollector.collection.add(
          ObjectDeclaration(
            filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
            element: node.declaredFragment?.element,
            parentId: parentId,
            lexeme: node.name.lexeme,
            type: analyzer_ast.FunctionDeclaration,
            offset: node.name.offset,
          ),
        );
      }
    }
    super.visitFunctionDeclaration(node);
  }
}

class _ObjectDeclarationCollectorFields extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectDeclarationCollectorFields({
    required ObjectDeclarationCollector declarationCollector,
  }) : _declarationCollector = declarationCollector;

  final ObjectDeclarationCollector _declarationCollector;

  @override
  void visitEnumConstantDeclaration(
    analyzer_ast.EnumConstantDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      _declarationCollector.collection.add(
        ObjectDeclaration(
          filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
          element: node.declaredFragment?.element,
          parentId: node.declaredFragment?.enclosingFragment?.name,
          lexeme: node.name.lexeme,
          type: analyzer_ast.EnumConstantDeclaration,
          offset: node.name.offset,
        ),
      );
    }
    super.visitEnumConstantDeclaration(node);
  }

  @override
  void visitFieldDeclaration(
    analyzer_ast.FieldDeclaration node,
  ) {
    if (!_declarationCollector._hasPublicApiAnnotationOrExcludedName(node)) {
      for (final v in node.fields.variables) {
        final element = v.declaredFragment?.element;
        final isOverriden = element?.metadata.isOverriden == true;
        final parent = isOverriden
            ? (element?.enclosingElement as analyzer_element.InterfaceElement).getSupertypeWithField(
                objectCollectorSources: _declarationCollector._collector.objectCollectorSources,
                packageIds: _declarationCollector._configuration.sourcePackages,
                fieldName: v.name.lexeme,
              )
            : null;
        final parentElement = parent?.getFieldElement(
          fieldName: element?.name,
        );
        if (!isOverriden || parent?.name != null) {
          _declarationCollector.collection.add(
            ObjectDeclaration(
              filePath: _declarationCollector._collector.currentObjectCollectorSource.file.path,
              element: parentElement ?? element,
              parentId: parent?.name ?? _declarationCollector._collector.getParentId(node),
              lexeme: v.name.lexeme,
              type: analyzer_ast.FieldDeclaration,
              offset: v.name.offset,
            ),
          );
        }
      }
    }
    super.visitFieldDeclaration(node);
  }
}

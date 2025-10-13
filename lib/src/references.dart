import 'package:analyzer/dart/ast/ast.dart' as analyzer_ast;
import 'package:analyzer/dart/ast/visitor.dart' as analyzer_visitor;
import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:obfuscator/src/extensions.dart';

/// Object declaration definitions.
///
class ObjectReference {
  /// Constructs an instance of an object declaration with parameters required for processing.
  ///
  ObjectReference({
    required this.filePath,
    required this.parentElement,
    required this.parentId,
    required this.lexeme,
    required this.offset,
  });

  /// Path of the file containing the relevant reference.
  ///
  final String filePath;

  /// Semantic model of the parent element.
  ///
  final analyzer_element.Element? parentElement;

  /// Identifier for the object holding this property (i.e., class, enum or extension name).
  ///
  final String? parentId;

  /// Unit of lexical meaning that underlies a set of words that are related through inflection.
  ///
  final String? lexeme;

  /// Offset from the beginning of the file to the first character in the syntactic entity.
  ///
  final int offset;
}

/// An AST visitor that will recursively visit all of the nodes in an AST structure.
///
/// Defined for collecting of the object references for obfuscating.
///
class ObjectReferenceCollector {
  /// Generates a new instance of the object reference collector.
  ///
  /// Project [configuration] is provided with the constructor
  /// in order to determine `visitor` specifications.
  ///
  ObjectReferenceCollector({
    required ObjectCollector collector,
    required Configuration configuration,
  }) : _collector = collector,
       _configuration = configuration {
    collectors = [
      _ObjectReferenceCollectorTopLevel(
        referenceCollector: this,
      ),
      _ObjectReferenceCollectorMethodsFunctions(
        referenceCollector: this,
      ),
      _ObjectReferenceCollectorFields(
        referenceCollector: this,
      ),
    ];
  }

  /// Property holding the value of the main object collector.
  ///
  final ObjectCollector _collector;

  /// Object defining the basic input options for the obfuscation service.
  ///
  final Configuration _configuration;

  /// Collection of reference collectors with specific object targets.
  ///
  late List<analyzer_visitor.RecursiveAstVisitor> collectors;

  /// Verifies if the object library URI belongs to any of the provided code sources.
  ///
  bool _isInternalImplementation(
    analyzer_element.LibraryElement? library,
  ) {
    if (library == null) return false;
    return <String>{
          for (final package in _configuration.sourcePackages) 'package:$package',
        }.any(
          library.uri.toString().contains,
        ) ||
        _collector.objectCollectorSources.any(
          (source) {
            return library.uri.toString().contains(source.file.path);
          },
        );
  }

  /// Collection of identified object references.
  ///
  final collection = <ObjectReference>[];
}

class _ObjectReferenceCollectorTopLevel extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectReferenceCollectorTopLevel({
    required ObjectReferenceCollector referenceCollector,
  }) : _referenceCollector = referenceCollector;

  final ObjectReferenceCollector _referenceCollector;

  /// Collects the object references for any of the following types:
  ///
  /// - [analyzer_element.ClassElement]
  /// - [analyzer_element.EnumElement]
  /// - [analyzer_element.MixinElement]
  /// - [analyzer_element.ExtensionElement]
  /// - [analyzer_element.ConstructorElement]
  ///
  @override
  void visitSimpleIdentifier(
    analyzer_ast.SimpleIdentifier node,
  ) {
    final library = node.element?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      if (node.element is analyzer_element.ClassElement ||
          node.element is analyzer_element.EnumElement ||
          node.element is analyzer_element.MixinElement ||
          node.element is analyzer_element.ExtensionElement ||
          node.element is analyzer_element.ConstructorElement) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: node.element is analyzer_element.ConstructorElement ? node.element?.enclosingElement : node.element,
            parentId: node.name,
            lexeme: node.name,
            offset: node.offset,
          ),
        );
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Locates type definitions, for example:
  ///
  /// ```dart
  /// class _MyWidgetState extends State<MyWidget> {
  ///
  ///   ...
  ///
  /// }
  /// ```
  ///
  /// where `MyWidget` represents the value retrieved by this callback.
  ///
  @override
  void visitNamedType(
    analyzer_ast.NamedType node,
  ) {
    final library = node.element?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      _referenceCollector.collection.add(
        ObjectReference(
          filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
          parentElement: node.element,
          parentId: node.name.lexeme,
          lexeme: node.name.lexeme,
          offset: node.name.offset,
        ),
      );
    }
    super.visitNamedType(node);
  }
}

class _ObjectReferenceCollectorMethodsFunctions extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectReferenceCollectorMethodsFunctions({
    required ObjectReferenceCollector referenceCollector,
  }) : _referenceCollector = referenceCollector;

  final ObjectReferenceCollector _referenceCollector;

  /// Identifies and records method invocations.
  ///
  @override
  void visitSimpleIdentifier(
    analyzer_ast.SimpleIdentifier node,
  ) {
    final library = node.element?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      final isOverriden = node.element?.metadata.isOverriden == true;
      final enclosingElement = isOverriden
          ? node.element is analyzer_element.MethodElement
                ? (node.element as analyzer_element.MethodElement).enclosingElement
                : node.element is analyzer_element.GetterElement
                ? (node.element as analyzer_element.GetterElement).enclosingElement
                : null
          : null;
      final parent = enclosingElement is analyzer_element.InterfaceElement
          ? enclosingElement.getSupertypeWithMethod(
              objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
              packageIds: _referenceCollector._configuration.sourcePackages,
              referenceElement: node.element,
            )
          : null;
      final parentElement = parent?.getMethodElement(
        referenceElement: node.element,
      );

      /// Collect method invocations.
      ///
      if (node.element is analyzer_element.MethodElement || node.element is analyzer_element.GetterElement) {
        if (!isOverriden || parent?.name != null) {
          _referenceCollector.collection.add(
            ObjectReference(
              filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
              parentElement: parentElement ?? node.element,
              parentId: parent?.name ?? node.element?.enclosingElement?.name,
              lexeme: node.name,
              offset: node.offset,
            ),
          );
        }
      }

      /// Collect local function invocations.
      ///
      if (node.element is analyzer_element.LocalFunctionElement) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: parentElement ?? node.element,
            parentId: _referenceCollector._collector.getEnclosingFunctionName(node),
            lexeme: node.name,
            offset: node.offset,
          ),
        );
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Identifies and records all of the `setter` method invocations.
  ///
  @override
  void visitAssignmentExpression(
    analyzer_ast.AssignmentExpression node,
  ) {
    final library = node.writeElement?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      if (node.writeElement is analyzer_element.SetterElement) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: node.writeElement,
            parentId: node.writeElement?.enclosingElement?.name,
            lexeme: node.writeElement?.name,
            offset: node.leftHandSide.endToken.offset,
          ),
        );
      }
    }
    super.visitAssignmentExpression(node);
  }
}

class _ObjectReferenceCollectorFields extends analyzer_visitor.RecursiveAstVisitor {
  _ObjectReferenceCollectorFields({
    required ObjectReferenceCollector referenceCollector,
  }) : _referenceCollector = referenceCollector;

  final ObjectReferenceCollector _referenceCollector;

  /// Identifies and records all enum field references.
  ///
  @override
  void visitPrefixedIdentifier(
    analyzer_ast.PrefixedIdentifier node,
  ) {
    final library = node.element?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      if (node.prefix.element is analyzer_element.EnumElement) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: node.identifier.element,
            parentId: node.prefix.name,
            lexeme: node.identifier.name,
            offset: node.identifier.offset,
          ),
        );
      }
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitFieldFormalParameter(
    analyzer_ast.FieldFormalParameter node,
  ) {
    final library = node.declaredFragment?.element.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      final enclosingClass = node.declaredFragment?.element.enclosingElement?.enclosingElement as analyzer_element.InterfaceElement;
      final matchingElement =
          enclosingClass.getFieldElement(
            fieldName: node.name.lexeme,
          ) ??
          enclosingClass
              .getSupertypeWithField(
                objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
                packageIds: _referenceCollector._configuration.sourcePackages,
                fieldName: node.name.lexeme,
              )
              ?.getFieldElement(
                fieldName: node.name.lexeme,
              );
      final isOverriden = matchingElement?.metadata.isOverriden == true;
      final parent = isOverriden
          ? enclosingClass.getSupertypeWithField(
              objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
              packageIds: _referenceCollector._configuration.sourcePackages,
              fieldName: node.name.lexeme,
            )
          : null;
      final parentElement = parent?.getFieldElement(
        fieldName: node.name.lexeme,
      );
      if (!isOverriden || parent?.name != null) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement:
                parentElement ??
                enclosingClass.getFieldElement(
                  fieldName: node.name.lexeme,
                ),
            parentId: parent?.name ?? enclosingClass.name,
            lexeme: node.name.lexeme,
            offset: node.endToken.offset,
          ),
        );
      }
    }
    super.visitFieldFormalParameter(node);
  }

  @override
  void visitSuperFormalParameter(
    analyzer_ast.SuperFormalParameter node,
  ) {
    final library = node.declaredFragment?.element.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      final enclosingElement = node.declaredFragment?.element.enclosingElement?.enclosingElement as analyzer_element.InterfaceElement;
      final supertype = enclosingElement.getSupertypeWithField(
        objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
        packageIds: _referenceCollector._configuration.sourcePackages,
        fieldName: node.name.lexeme,
      );
      final relevantConstructor = supertype?.constructors.firstWhere(
        (constructor) {
          return constructor.name == node.declaredFragment?.enclosingFragment?.name &&
              constructor.formalParameters.any(
                (parameter) {
                  return parameter.name == node.name.lexeme;
                },
              );
        },
      );
      final isInitialisingFormal =
          relevantConstructor?.formalParameters.firstWhere(
            (parameter) {
              return parameter.name == node.name.lexeme;
            },
          ).isInitializingFormal ==
          true;
      if (isInitialisingFormal || relevantConstructor != null) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: isInitialisingFormal
                ? supertype?.getFieldElement(
                    fieldName: node.name.lexeme,
                  )
                : enclosingElement.getFieldElement(
                    fieldName: node.name.lexeme,
                  ),
            parentId: isInitialisingFormal ? supertype?.name : '${relevantConstructor?.enclosingElement.name}.${relevantConstructor?.name}',
            lexeme: node.name.lexeme,
            offset: node.endToken.offset,
          ),
        );
      }
    }
    super.visitSuperFormalParameter(node);
  }

  @override
  void visitConstructorFieldInitializer(
    analyzer_ast.ConstructorFieldInitializer node,
  ) {
    final library = node.fieldName.element?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      _referenceCollector.collection.add(
        ObjectReference(
          filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
          parentElement: _referenceCollector._collector
              .getParentElement(node)
              ?.getFieldElement(
                fieldName: node.fieldName.name,
              ),
          parentId: _referenceCollector._collector.getParentId(node),
          lexeme: node.fieldName.name,
          offset: node.fieldName.offset,
        ),
      );
    }
    super.visitConstructorFieldInitializer(node);
  }

  void _collectIdentifiers(
    analyzer_ast.AstNode node,
    analyzer_ast.Expression? expression,
  ) {
    if (expression == null) return;
    final elements = <({analyzer_element.Element element, int offset})>[];
    void collect(analyzer_ast.Expression expr) {
      if (expr is analyzer_ast.SimpleIdentifier) {
        final element = expr.element;
        if (element != null) {
          elements.add((element: element, offset: expr.offset));
        }
      } else if (expr is analyzer_ast.PrefixedIdentifier) {
        if (expr.prefix.element != null) {
          elements.add((element: expr.prefix.element!, offset: expr.prefix.offset));
        }
        if (expr.identifier.element != null) {
          elements.add((element: expr.identifier.element!, offset: expr.identifier.offset));
        }
      } else if (expr is analyzer_ast.PrefixExpression) {
        collect(expr.operand);
      } else if (expr is analyzer_ast.BinaryExpression) {
        collect(expr.leftOperand);
        collect(expr.rightOperand);
      } else if (expr is analyzer_ast.ParenthesizedExpression) {
        collect(expr.expression);
      } else if (expr is analyzer_ast.NamedExpression) {
        collect(expr.expression);
      } else if (expr is analyzer_ast.FunctionExpression) {
        expr.body.accept(this);
      }
    }

    collect(expression);
    for (final elementEntry in elements) {
      final library = elementEntry.element.library;
      if (!_referenceCollector._isInternalImplementation(library)) continue;
      final element = elementEntry.element;
      dynamic enclosing = element.enclosingElement?.enclosingElement;
      if (enclosing is! analyzer_element.InterfaceElement) continue;
      final isOverriden = element.metadata.isOverriden == true;
      final parent = isOverriden
          ? enclosing.getSupertypeWithField(
              objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
              packageIds: _referenceCollector._configuration.sourcePackages,
              fieldName: element.name ?? 'N/A',
            )
          : null;
      if (!isOverriden || parent?.name != null) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: (parent ?? enclosing).getFieldElement(fieldName: element.name),
            parentId: parent?.name ?? _referenceCollector._collector.getParentId(node),
            lexeme: element.name,
            offset: elementEntry.offset,
          ),
        );
      }
    }
  }

  @override
  void visitAssertInitializer(
    analyzer_ast.AssertInitializer node,
  ) {
    _collectIdentifiers(node, node.condition);
    super.visitAssertInitializer(node);
  }

  @override
  void visitSuperConstructorInvocation(
    analyzer_ast.SuperConstructorInvocation node,
  ) {
    for (final arg in node.argumentList.arguments) {
      _collectIdentifiers(node, arg);
    }
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitSimpleIdentifier(analyzer_ast.SimpleIdentifier node) {
    final element = node.element;
    if (element is analyzer_element.FieldFormalParameterElement) {
      final library = element.library;
      if (_referenceCollector._isInternalImplementation(library)) {
        final enclosingClass = element.enclosingElement?.enclosingElement as analyzer_element.InterfaceElement;
        final matchingElement =
            enclosingClass.getFieldElement(
              fieldName: node.name,
            ) ??
            enclosingClass
                .getSupertypeWithField(
                  objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
                  packageIds: _referenceCollector._configuration.sourcePackages,
                  fieldName: node.name,
                )
                ?.getFieldElement(
                  fieldName: node.name,
                );
        final isOverriden = matchingElement?.metadata.isOverriden == true;
        final parent = isOverriden
            ? enclosingClass.getSupertypeWithField(
                objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
                packageIds: _referenceCollector._configuration.sourcePackages,
                fieldName: node.name,
              )
            : null;
        final parentElement = parent?.getFieldElement(
          fieldName: node.name,
        );
        if (!isOverriden || parent?.name != null) {
          _referenceCollector.collection.add(
            ObjectReference(
              filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
              parentElement:
                  parentElement ??
                  enclosingClass.getFieldElement(
                    fieldName: node.name,
                  ),
              parentId: parent?.name ?? enclosingClass.name,
              lexeme: node.name,
              offset: node.offset,
            ),
          );
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Finds references to the field parameter names, e.g.,
  ///
  /// ```dart
  /// final myObject = Object(
  ///   myFieldParameterName: ... // Detected value.
  /// );
  /// ```
  ///
  @override
  void visitNamedExpression(
    analyzer_ast.NamedExpression node,
  ) {
    final element = node.name.label.element;
    final library = element?.library;
    if (_referenceCollector._isInternalImplementation(library) || element is analyzer_element.FormalParameterElement) {
      if (element is analyzer_element.FieldFormalParameterElement || element is analyzer_element.SuperFormalParameterElement) {
        final isSuperFormalParameter = element is analyzer_element.SuperFormalParameterElement;
        final enclosingConstructor = element?.enclosingElement as analyzer_element.ConstructorElement?;
        final enclosingElement = enclosingConstructor?.enclosingElement;
        final supertype = isSuperFormalParameter
            ? enclosingElement?.getSupertypeWithField(
                objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
                packageIds: _referenceCollector._configuration.sourcePackages,
                fieldName: node.name.label.name,
              )
            : null;
        final relevantConstructor = supertype?.constructors.firstWhere(
          (constructor) {
            return constructor.name == enclosingConstructor?.name &&
                constructor.formalParameters.any(
                  (parameter) {
                    return parameter.name == node.name.label.name;
                  },
                );
          },
        );
        final isInitialisingFormal =
            relevantConstructor?.formalParameters.firstWhere(
              (parameter) {
                return parameter.name == node.name.label.name;
              },
            ).isInitializingFormal ==
            true;
        final parent = isInitialisingFormal ? supertype : enclosingElement;
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: parent?.getFieldElement(
              fieldName: node.name.label.name,
            ),
            parentId: parent?.name,
            lexeme: element?.name,
            offset: node.name.offset,
          ),
        );
      } else if (element is analyzer_element.FormalParameterElement) {
        if (element.name == 'labelWidget') {}
      }
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitPropertyAccess(
    analyzer_ast.PropertyAccess node,
  ) {
    final propertyElement = node.propertyName.element;
    final library = propertyElement?.library;
    if (_referenceCollector._isInternalImplementation(library)) {
      if (propertyElement is analyzer_element.GetterElement) {
        final enclosingElement = propertyElement.firstFragment.enclosingFragment?.element;
        if (enclosingElement is analyzer_element.InterfaceElement) {
          final matchingField = enclosingElement.fields.firstWhere(
            (field) {
              return field.name == node.propertyName.name;
            },
          );
          final isOverriden = matchingField.metadata.isOverriden;
          final parent = isOverriden
              ? enclosingElement.getSupertypeWithField(
                  objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
                  packageIds: _referenceCollector._configuration.sourcePackages,
                  fieldName: node.propertyName.name,
                )
              : null;
          if (isOverriden && parent?.name != null) {
            _referenceCollector.collection.add(
              ObjectReference(
                filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
                parentElement: parent?.getFieldElement(
                  fieldName: node.propertyName.name,
                ),
                parentId: parent?.name,
                lexeme: node.propertyName.name,
                offset: node.propertyName.offset,
              ),
            );
          }
        }
      }
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixExpression(
    analyzer_ast.PrefixExpression node,
  ) {
    final operand = node.operand;
    if (operand is analyzer_ast.SimpleIdentifier) {
      final element = node.readElement ?? node.writeElement;
      final library = element?.library;
      final isOverriden = element?.metadata.isOverriden == true;
      final enclosingElement = _referenceCollector._collector.getParentElement(node);
      final parent = isOverriden
          ? enclosingElement?.getSupertypeWithField(
              objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
              packageIds: _referenceCollector._configuration.sourcePackages,
              fieldName: element?.name,
            )
          : enclosingElement;
      if (_referenceCollector._isInternalImplementation(library)) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: parent?.getFieldElement(fieldName: element?.name) ?? element,
            parentId: parent?.name,
            lexeme: element?.name,
            offset: operand.endToken.offset,
          ),
        );
      }
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(
    analyzer_ast.PostfixExpression node,
  ) {
    final operand = node.operand;
    if (operand is analyzer_ast.SimpleIdentifier) {
      final element = node.readElement ?? node.writeElement;
      final library = element?.library;
      final isOverriden = element?.metadata.isOverriden == true;
      final enclosingElement = _referenceCollector._collector.getParentElement(node);
      final parent = isOverriden
          ? enclosingElement?.getSupertypeWithField(
              objectCollectorSources: _referenceCollector._collector.objectCollectorSources,
              packageIds: _referenceCollector._configuration.sourcePackages,
              fieldName: element?.name,
            )
          : enclosingElement;
      if (_referenceCollector._isInternalImplementation(library)) {
        _referenceCollector.collection.add(
          ObjectReference(
            filePath: _referenceCollector._collector.currentObjectCollectorSource.file.path,
            parentElement: parent?.getFieldElement(fieldName: element?.name) ?? element,
            parentId: parent?.name,
            lexeme: element?.name,
            offset: operand.beginToken.offset,
          ),
        );
      }
    }
    super.visitPostfixExpression(node);
  }
}

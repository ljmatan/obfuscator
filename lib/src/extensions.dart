import 'package:analyzer/dart/element/element.dart' as analyzer_element;
import 'package:analyzer/dart/element/type.dart' as analyzer_type;
import 'package:obfuscator/src/collector.dart';

/// Extension methods and properties for the metadata (annotations)
/// associated with an element or fragment.
///
extension MetadataExt on analyzer_element.Metadata {
  /// Whether the AST node is annotated as an [override]n field.
  ///
  bool get isOverriden {
    return annotations.any(
      (annotation) {
        return (annotation.element?.name ?? annotation.element?.displayName) == 'override';
      },
    );
  }
}

extension InterfaceElementExt on analyzer_element.InterfaceElement {
  /// Whether `this` is declared within one of the packages to be obfuscated.
  ///
  bool _isFirstParty({
    required Iterable<ObjectCollectorSource> objectCollectorSources,
    required analyzer_type.InterfaceType supertype,
    required Iterable<String> packageIds,
  }) {
    return packageIds.any(
          supertype.element.library.uri.toString().contains,
        ) ||
        objectCollectorSources.any(
          (source) {
            return supertype.element.library.uri.toString().contains(source.file.path);
          },
        );
  }

  /// Returns the first supertype that declares a method matching the provided [elementId].
  ///
  analyzer_element.InterfaceElement? getSupertypeWithMethod({
    required Iterable<ObjectCollectorSource> objectCollectorSources,
    required Iterable<String> packageIds,
    required analyzer_element.Element? referenceElement,
  }) {
    try {
      return allSupertypes.firstWhere(
        (supertype) {
          return _isFirstParty(
                objectCollectorSources: objectCollectorSources,
                supertype: supertype,
                packageIds: packageIds,
              ) &&
              (referenceElement is analyzer_element.GetterElement &&
                      supertype.getters.any(
                        (getter) {
                          return getter.name == referenceElement.name && !getter.metadata.isOverriden;
                        },
                      ) ||
                  referenceElement is analyzer_element.SetterElement &&
                      supertype.setters.any(
                        (setter) {
                          return setter.name == referenceElement.name && !setter.metadata.isOverriden;
                        },
                      ) ||
                  referenceElement != null &&
                      supertype.methods.any(
                        (method) {
                          return method.name == referenceElement.name && !method.metadata.isOverriden;
                        },
                      ));
        },
      ).element;
    } catch (e) {
      return null;
    }
  }

  /// Returns the first supertype that declares a field matching the provided [fieldName].
  ///
  analyzer_element.InterfaceElement? getSupertypeWithField({
    required Iterable<ObjectCollectorSource> objectCollectorSources,
    required Iterable<String> packageIds,
    required String? fieldName,
  }) {
    if (fieldName == null) return null;
    try {
      return allSupertypes.firstWhere(
        (supertype) {
          return _isFirstParty(
                objectCollectorSources: objectCollectorSources,
                supertype: supertype,
                packageIds: packageIds,
              ) &&
              supertype.element.fields.any(
                (field) {
                  return !field.metadata.isOverriden && field.name == fieldName;
                },
              );
        },
      ).element;
    } catch (e) {
      return null;
    }
  }

  analyzer_element.ExecutableElement? getMethodElement({
    required analyzer_element.Element? referenceElement,
  }) {
    if (referenceElement == null) return null;
    if (referenceElement is analyzer_element.GetterElement) {
      try {
        return getters.firstWhere(
          (getter) {
            return getter.name == referenceElement.name;
          },
        );
      } catch (e) {
        return null;
      }
    }
    if (referenceElement is analyzer_element.SetterElement) {
      try {
        return setters.firstWhere(
          (setter) {
            return setter.name == referenceElement.name;
          },
        );
      } catch (e) {
        return null;
      }
    }
    try {
      return methods.firstWhere(
        (method) {
          return method.name == referenceElement.name;
        },
      );
    } catch (e) {
      return null;
    }
  }

  analyzer_element.FieldElement? getFieldElement({
    required String? fieldName,
  }) {
    try {
      return fields.firstWhere(
        (field) {
          return field.name == fieldName;
        },
      );
    } catch (e) {
      return null;
    }
  }
}

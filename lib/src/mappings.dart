class Mapping {
  Mapping({
    required this.filePath,
    required this.id,
    required this.replacementId,
    required this.parentId,
    required this.offset,
    required this.referenceMappings,
  });

  final String filePath;

  final String? id;

  final String replacementId;

  final String? parentId;

  final int offset;

  final List<Mapping>? referenceMappings;

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'id': id,
      'replacementId': replacementId,
      'parentId': parentId,
      'offset': offset,
      'referenceMappings': referenceMappings?.map(
        (referenceMapping) {
          return referenceMapping.toJson();
        },
      ).toList(),
    };
  }
}

import 'package:obfuscator/src/collector.dart';
import 'package:obfuscator/src/config.dart';
import 'package:obfuscator/src/generator.dart';
import 'package:obfuscator/src/merger.dart';

void main(
  List<String> arguments,
) async {
  // Generate the runtime configuration.
  final configuration = Configuration.fromArguments(
    arguments: arguments,
  );

  // Allocate runtime resources.
  await configuration.init();

  // Instantiate source code object collector.
  final collector = ObjectCollector(
    configuration: configuration,
  );

  // Collect and process top level objects and import statements.
  await collector.processUnits();

  // Instantiate source code object generator.
  final generator = Generator(
    configuration: configuration,
    collector: collector,
  );

  // Replace the copied file contents with new object identifiers.
  await generator.processCopiedSourceDirectories();

  // Merge provided source code to a single file.
  await ProjectMerger(
    configuration: configuration,
    collector: collector,
  ).generateMergedProject();
}

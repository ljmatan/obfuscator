# Dart Obfuscator

A command-line tool that obfuscates Dart (including Flutter) source code by renaming
declarations and their references using the Dart analyzer.

It is intended for preparing code to be shared as **private packages** or distributed
in source form while reducing readability by renaming classes, mixins, methods, functions, and fields.

The tool works on copied project sources (it does not overwrite the original) and produces an obfuscated copy,
a single merged `merged.dart` file for the codebase, and a generated `pubspec.yaml` that reflects
dependencies found in the sources.

---

## Table of contents

- [Features](#features)
- [Quick start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)

  - [Required arguments](#required-arguments)
  - [Optional arguments](#optional-arguments)
  - [Example(s)](#examples)

- [How it works (high level)](#how-it-works-high-level)
- [Generated outputs](#generated-outputs)
- [Exclusion rules](#exclusion-rules)
- [Best practices / recommendations](#best-practices--recommendations)
- [Limitations & caveats](#limitations--caveats)
- [Security & legal considerations](#security--legal-considerations)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- Parse and resolve Dart source code using the Dart analyzer.
- Discover declarations (classes, mixins, enums, typedefs, top-level functions, methods, fields, getters/setters).
- Generate deterministic obfuscated identifiers and replace all references while preserving semantics.
- Work on copies of supplied source folders; originals remain untouched.
- Produce:

  - Obfuscated source tree (mirrors original structure inside output folder).
  - A single `merged.dart` combining code units where applicable.
  - A generated `pubspec.yaml` inferred from source imports/metadata.

- Support exclusion of items from obfuscation via annotation or object identifiers passed on the CLI (`--pub`).
- Intended workflow: obfuscate a codebase and share the obfuscated copy as a “private package”.

---

## Quick start

1. Run the obfuscator:

Providing the comma-separated source directory locations as `src` named argument,
while also including the output directory location with the `out` argument.

```bash
dart run bin/obfuscator.dart --src /path/to/project1,/path/to/project2 --out /path/to/output
```

2. Optionally, provide annotation or object identifiers to exclude certain symbols from obfuscation:

Comma-separated list of identifiers entered with the `pub` argument are excluded from obfuscation.

```bash
dart run bin/obfuscator.dart --src ./my_app --out ./obf_out --pub NoObfuscation,AppLocalizations
```

---

## Installation

This project is a Dart CLI app. To run it, you need a compatible Dart SDK installed (same minimum SDK as defined in this project's `pubspec.yaml`).

---

## Usage

Run the main entrypoint `bin/obfuscator.dart`. The program accepts command-line arguments.

### Required arguments

- `--src` — comma-separated list of source project paths. Each path should be a directory containing Dart/Flutter source code to be processed. Example:

  ```
  --src /home/user/projects/app1,/home/user/projects/libpkg
  ```

- `--out` — output directory where the processed (obfuscated) projects and generated artifacts will be written. The directory will be created if it does not exist. Example:

  ```
  --out /home/user/obf-output
  ```

### Optional arguments

- `--pub` — comma-separated list of annotation or object identifiers (fully-qualified or simple)
  that mark declarations **not** to be obfuscated.
  Default: `NoObfuscation` (lookup in libraries for a top-level `NoObfuscation` object).

  - Example:

    ```
    --pub NoObfuscation,MyCompany.DoNotObfuscate
    ```

Run `dart run bin/obfuscator.dart --help` for the full list and precise flag naming.

### Examples

Obfuscate two projects and write output into `/tmp/obf`:

```bash
dart run bin/obfuscator.dart --src /projects/app1,/projects/shared_package --out /tmp/obf
```

Obfuscate a project while excluding declarations annotated with `NoObfuscation` and `Keep`:

```bash
dart run bin/obfuscator.dart --src ./app --out ./out --pub NoObfuscation,Keep
```

Example obfuscated code for various projects can be found in the `output` directory:
https://github.com/ljmatan/obfuscator/tree/main/output

---

## How it works (high level)

1. **Copy**: The tool copies the source locations provided to the output directory into a working area.
2. **Analysis**: Uses the Dart analyzer (resolved units via an `AnalysisContext`) to parse and fully resolve ASTs of the copied sources.
3. **Discovery**: Walks declarations (classes, mixins, enums, typedefs, top-level functions, constructors, methods, fields, getters/setters) and builds a list of symbols to obfuscate.
4. **Exclusions**: Skips symbols annotated with any supplied identifiers (from `--pub`) or other built-in exclusions (e.g., symbols matching certain whitelists).
5. **Renaming / Mapping**: Generates obfuscated identifiers and computes a mapping from original name → obfuscated name.
6. **Reference resolution**: Using the resolved AST and element model, the tool collects and updates all references to each renamed declaration (constructor calls, method invocations, prefixed identifiers, property accessors, initializers, etc.).
7. **Replace**: Performs source edits (safely, preserving formatting where possible) on the copied files to rename declarations and references.
8. **Generate merged.dart**: Writes a combined `merged.dart` containing the full codebase (useful to distribute a single-file source version).
9. **Generate pubspec.yaml**: Scans `package` references and other metadata to create a `pubspec.yaml` for the obfuscated output (dependencies resolved as best-effort from imports).

---

## Generated outputs

- `<out>/copy/<name>/...` — obfuscated copy of each provided source project.
- `<out>/merged.dart` — single-file merge of the processed codebase.
- `<out>/pubspec.yaml` — generated or inferred `pubspec.yaml`.
- `<out>/mappings.json` — JSON map of original → obfuscated symbol names.

---

## Exclusion rules

- **Default exclusion**: the tool looks for a `NoObfuscation` object (or other identifiers passed via `--pub`)
  and will not obfuscate any matching declarations.

- **How identifiers are matched**:

  - Exact match by identifier name (e.g., `NoObfuscation`).
  - Fully-qualified match if you provide the package path (e.g., `obfuscator.NoObfuscation`).

- **Common use cases**:

  - Keep public stable API names for interop with reflection / platform channels.
  - Exclude classes used by platform integration or code generation that requires stable names.

---

## Best practices / recommendations

- **Test the obfuscated build**: run `dart analyze` and `flutter test` / `dart test` on the obfuscated output before sharing to ensure no runtime breakages.
- **Use deterministic seeds** for reproducible mapping across builds when needed.
- **Annotate stable APIs** that must not be renamed (e.g., platform channel method names, reflection entries).
- **Limit the scope**: for very large projects, consider obfuscating only selected libraries to reduce risk.
- **Inspect mapping files** and retain them securely (they can be used to reverse-mapping in trusted contexts).

---

## Limitations & caveats

- **Not a security barrier**: source obfuscation increases effort to understand the code but is not a substitute for licensing, code access controls, or true binary-level obfuscation.
- **Complex reflection & mirrors**: if code uses `dart:mirrors`, `reflectable`, or string-based reflection, renaming may break runtime behavior unless you annotate/whitelist those symbols.
- **Generated code**: code generators (e.g., `build_runner`) may expect specific identifiers. Avoid renaming generated output unless you control the generator or also regenerate outputs appropriately.
- **Third-party packages**: External packages referenced by name must remain consistent in `pubspec.yaml`; the tool tries to infer package dependencies by import, but manual verification is recommended.
- **Edge cases in resolution**: some dynamic dispatch or runtime symbol lookups may not be detectable via static analysis; test thoroughly.
- **Legal**: ensure you have the right to obfuscate and distribute any source code; follow licenses and agreements.

---

## Security & legal considerations

- Keep obfuscation mappings confidential if they are used to de-obfuscate code within private contexts.
- Obfuscation is not encryption. If you need to protect intellectual property, also employ legal safeguards: licensing, access control, code repositories with restricted access.
- Verify license compatibility of third-party code before obfuscating and redistributing.

---

## Troubleshooting

- Symbols still refer to old names:

  - Ensure you run the tool on a **resolved AST** environment (the tool runs analyzer resolution internally for correctness).
  - Inspect `mappings.json` (if generated) to confirm the mapping.
  - Verify that constructor initializing formals, property accessors, or top-level getters are normalized to the underlying field/variable by the tool (see code comments).

- Build or runtime errors after obfuscation:

  - Check for reflection usage or string-based lookups that reference symbol names.
  - Confirm generated `pubspec.yaml` dependencies are correct. If not, merge dependency entries from the original `pubspec.yaml` manually.

- If the tool fails to recognize a declaration, ensure the file is syntactically valid Dart and that all dependent packages are resolvable by analyzer (you may need to run `dart pub get` in the source directories before running the tool).

---

## Contributions

If you encounter a failure or incorrect obfuscation result,
please file a report on the GitHub issue tracker with:

- The error or stack trace (if any)
- A short code sample reproducing the issue
- The command you used (with arguments)

Your report helps improve the reliability of future releases.

## License

The probject is published with MIT license.

See the `LICENSE` file for details.

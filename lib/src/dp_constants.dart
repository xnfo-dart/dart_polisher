// ignore_for_file: constant_identifier_names
import 'package:dart_polisher/src/dart_formatter/dart_formatter_options.dart'
    show CodeStyle;

class DPConst
{
    // NOTE: The following line of code is modified by tool/grind.dart.
    /// Dart Polisher version number
    static const String VERSION = "0.9.4-dev";
    // NOTE: The following line of code is modified by tool/grind.dart.
    /// This version is used to embed dart_style as a separate command in cli.
    static const String DART_STYLE_DEP_VERSION = "2.2.4";

    /// Version string
    static const String VERSION_STRING = "Formatter version: $VERSION"
        " (based on dart_style: $FORKED_FROM_DART_STYLE_VERSION)";

    /// The last merge from dart_style
    // Note: Change this manually only when merging all changes from upstream up to *this version
    static const String FORKED_FROM_DART_STYLE_VERSION = "2.2.5-dev";
    static const String FORKED_FROM_DART_STYLE_COMMIT =
        "https://github.com/dart-lang/dart_style/commit/56df84744abcb4bd733e4c5de310347949a44c82";
    static const String FORKED_FROM_DART_STYLE_COMMIT_DATE = "Tue Oct 11 2022";
}

class DefaultValue
{
    // Default values
    static const int DEFAULT_BLOCK_INDENT = 4;
    static const int DEFAULT_CASCADE_INDENT = 4;
    static const int DEFAULT_EXPRESSION_INDENT = 4;
    static const int DEFAULT_CONSTRUCTOR_INITIALIZER_INDENT = 4;
    static const int DEFAULT_PAGEWIDTH = 90;
    static const bool DEFAULT_INSERTSPACES = true;
    static const CodeStyle DEFAULT_STYLE = CodeStyle.DartStyle;
}

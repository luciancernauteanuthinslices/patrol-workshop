// import 'dart:io';
// import 'package:path_provider/path_provider.dart';
// import 'package:path/path.dart' as p;
//
// const bool kExportForSchemathesis =
//     bool.fromEnvironment('EXPORT_TOKEN', defaultValue: false);
//
// class TokenExport {
//   static Future<void> save(String token) async {
//     final dir = await getApplicationDocumentsDirectory();
//     final file = File(p.join(dir.path, '.schemathesis_token'));
//     await file.writeAsString(token, flush: true);
//   }
// }

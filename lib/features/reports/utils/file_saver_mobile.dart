import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String?> saveFile(String content, String filename) async {
  Directory? directory;
  try {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      directory = await getDownloadsDirectory();
    }
    directory ??= await getApplicationDocumentsDirectory();
    
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
    print('Report saved successfully to: ${file.path}');
    return file.path;
  } catch (e) {
    print('Failed to save file: $e');
    rethrow;
  }
}

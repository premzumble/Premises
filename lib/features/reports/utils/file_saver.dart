import 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_mobile.dart';

Future<String?> saveReportFile(String content, String filename) async {
  return await saveFile(content, filename);
}

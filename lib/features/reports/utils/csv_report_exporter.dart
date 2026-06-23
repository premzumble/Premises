import '../../../core/api_service.dart';
import 'file_saver.dart';
import 'report_exporter.dart';

class CsvReportExporter implements ReportExporter {
  @override
  Future<String?> exportReport({
    required String reportType,
    required Map<String, dynamic> parameters,
  }) async {
    final queryParams = <String>[];
    queryParams.add('report_type=${Uri.encodeQueryComponent(reportType)}');
    queryParams.add('format=CSV');

    parameters.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        queryParams.add('$key=${Uri.encodeQueryComponent(value.toString())}');
      }
    });

    final path = '/admin/export-report?${queryParams.join('&')}';
    final csvContent = await ApiService.getRaw(path);
    final filename = '${reportType.replaceAll(' ', '_').toLowerCase()}.csv';
    return await saveReportFile(csvContent, filename);
  }
}

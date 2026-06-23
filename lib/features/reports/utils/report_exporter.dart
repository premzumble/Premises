import 'csv_report_exporter.dart';

abstract class ReportExporter {
  Future<String?> exportReport({
    required String reportType,
    required Map<String, dynamic> parameters,
  });
}

class PdfReportExporter implements ReportExporter {
  @override
  Future<String?> exportReport({
    required String reportType,
    required Map<String, dynamic> parameters,
  }) async {
    throw UnsupportedError('PDF export is not implemented yet.');
  }
}

class ExcelReportExporter implements ReportExporter {
  @override
  Future<String?> exportReport({
    required String reportType,
    required Map<String, dynamic> parameters,
  }) async {
    throw UnsupportedError('Excel export is not implemented yet.');
  }
}

class ReportExporterFactory {
  static ReportExporter getExporter(String format) {
    if (format == 'CSV') {
      return CsvReportExporter();
    } else if (format == 'PDF') {
      return PdfReportExporter();
    } else if (format == 'Excel') {
      return ExcelReportExporter();
    }
    throw UnsupportedError('Export format "$format" is not supported.');
  }
}

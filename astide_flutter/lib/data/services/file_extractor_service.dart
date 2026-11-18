import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:xml/xml.dart';

/// Result of extracting readable text and metadata from a local attachment file.
class ExtractedFileInfo {
  const ExtractedFileInfo({
    required this.mimeType,
    required this.fileSize,
    required this.extractedText,
  });

  final String mimeType;
  final int fileSize;
  final String extractedText;
}

/// Extracts readable text from common document/code formats and encodes images for Vision APIs.
class FileExtractorService {
  static const int maxExtractedChars = 24000;

  static const Set<String> _plainTextExtensions = {
    '.txt',
    '.md',
    '.markdown',
    '.json',
    '.csv',
    '.tsv',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.htm',
    '.log',
    '.ini',
    '.conf',
    '.cfg',
    '.env',
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.jsx',
    '.tsx',
    '.java',
    '.kt',
    '.kts',
    '.swift',
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.cs',
    '.go',
    '.rs',
    '.rb',
    '.php',
    '.sql',
    '.sh',
    '.bat',
    '.ps1',
    '.css',
    '.scss',
    '.less',
    '.vue',
    '.toml',
    '.gradle',
  };

  Future<ExtractedFileInfo> extractFromFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final ext = p.extension(filePath).toLowerCase();
    final mime = guessMimeType(filePath);
    final extracted = await extractTextFromBytes(bytes, extension: ext);
    return ExtractedFileInfo(
      mimeType: mime,
      fileSize: bytes.length,
      extractedText: _truncate(extracted),
    );
  }

  Future<String> extractTextFromBytes(
    Uint8List bytes, {
    required String extension,
  }) async {
    final ext = extension.toLowerCase();
    try {
      if (_plainTextExtensions.contains(ext)) {
        return _decodeText(bytes);
      }
      if (ext == '.pdf') {
        return _extractPdfText(bytes);
      }
      if (ext == '.xlsx' || ext == '.xls') {
        return _extractExcelText(bytes);
      }
      if (ext == '.docx') {
        return _extractDocxText(bytes);
      }
      if (ext == '.pptx') {
        return _extractPptxText(bytes);
      }
      // Fallback: treat small readable files as plain text if mostly UTF-8 printable.
      if (bytes.length <= 512 * 1024 && _looksLikeText(bytes)) {
        return _decodeText(bytes);
      }
    } catch (_) {
      return '';
    }
    return '';
  }

  Future<String> encodeImageDataUrl(String filePath, {String? mimeType}) async {
    final bytes = await File(filePath).readAsBytes();
    final mime = mimeType ?? guessMimeType(filePath);
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String guessMimeType(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.md':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      case '.txt':
      case '.log':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  bool _looksLikeText(Uint8List bytes) {
    final sampleLen = bytes.length < 1024 ? bytes.length : 1024;
    if (sampleLen == 0) return false;
    var controlCount = 0;
    for (var i = 0; i < sampleLen; i++) {
      final b = bytes[i];
      if (b == 0) return false;
      if (b < 0x09 || (b > 0x0D && b < 0x20)) {
        controlCount++;
      }
    }
    return controlCount / sampleLen < 0.05;
  }

  String _extractPdfText(Uint8List bytes) {
    final doc = PdfDocument.open(bytes);
    final buffer = StringBuffer();
    final maxPages = doc.pageCount > 40 ? 40 : doc.pageCount;
    for (var i = 0; i < maxPages; i++) {
      final pageText = PdfTextExtractor.extract(doc, i).text.trim();
      if (pageText.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.writeln('\n--- 第 ${i + 1} 页 ---');
        buffer.writeln(pageText);
      }
      if (buffer.length >= maxExtractedChars) break;
    }
    if (doc.pageCount > maxPages) {
      buffer.writeln('\n[注：PDF 共 ${doc.pageCount} 页，仅提取前 $maxPages 页]');
    }
    return buffer.toString().trim();
  }

  String _extractExcelText(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    for (final entry in excel.tables.entries) {
      buffer.writeln('=== 工作表: ${entry.key} ===');
      for (final row in entry.value.rows) {
        final cells = row.map((cell) => cell?.value?.toString() ?? '').toList();
        if (cells.any((c) => c.trim().isNotEmpty)) {
          buffer.writeln(cells.join(' | '));
        }
        if (buffer.length >= maxExtractedChars) break;
      }
      if (buffer.length >= maxExtractedChars) break;
    }
    return buffer.toString().trim();
  }

  String _extractDocxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) return '';
    final xmlStr = utf8.decode(docFile.content as List<int>, allowMalformed: true);
    final document = XmlDocument.parse(xmlStr);
    final buffer = StringBuffer();
    for (final paragraph in document.findAllElements('w:p')) {
      final line = paragraph.findAllElements('w:t').map((e) => e.innerText).join();
      if (line.trim().isNotEmpty) {
        buffer.writeln(line);
      }
      if (buffer.length >= maxExtractedChars) break;
    }
    return buffer.toString().trim();
  }

  String _extractPptxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides = archive.files
        .where((f) => f.isFile && f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final buffer = StringBuffer();
    for (var i = 0; i < slides.length; i++) {
      final xmlStr = utf8.decode(slides[i].content as List<int>, allowMalformed: true);
      final document = XmlDocument.parse(xmlStr);
      final texts = document
          .findAllElements('a:t')
          .map((e) => e.innerText.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (texts.isNotEmpty) {
        buffer.writeln('--- 幻灯片 ${i + 1} ---');
        buffer.writeln(texts.join('\n'));
      }
      if (buffer.length >= maxExtractedChars) break;
    }
    return buffer.toString().trim();
  }

  String _truncate(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= maxExtractedChars) return trimmed;
    return '${trimmed.substring(0, maxExtractedChars)}\n\n[文件内容过长，已截断至 $maxExtractedChars 字符]';
  }
}

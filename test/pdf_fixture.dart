import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import 'dart:convert';
import 'dart:typed_data';

/// Text placed at [x], [y] points from the top-left of an A4 page.
typedef PdfText = ({double x, double y, String text, double size});

PdfText at(double x, double y, String text, {double size = 9}) => (x: x, y: y, text: text, size: size);

/// Right-aligned at [right], the way statements set amounts. Helvetica digits
/// are 0.556 em wide; this only needs to be close.
PdfText right(double right, double y, String text, {double size = 9}) =>
    (x: right - text.length * size * 0.556, y: y, text: text, size: size);

/// A minimal text-only PDF (Helvetica, WinAnsi), enough to stand in for a
/// bank's statement in tests.
Uint8List buildPdf(List<List<PdfText>> pages) {
  const h = 842.0;
  final objects = <String>[];
  final pageIds = [for (var i = 0; i < pages.length; i++) 4 + i * 2];
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add(
    '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] /Count ${pages.length} >>',
  );
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  for (var i = 0; i < pages.length; i++) {
    final content = StringBuffer();
    for (final t in pages[i]) {
      final s = t.text.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
      content.write(
        'BT /F1 ${t.size} Tf 1 0 0 1 ${t.x.toStringAsFixed(2)} ${(h - t.y).toStringAsFixed(2)} Tm ($s) Tj ET\n',
      );
    }
    final body = content.toString();
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 $h] /Resources << /Font << /F1 3 0 R >> >> '
      '/Contents ${pageIds[i] + 1} 0 R >>',
    );
    objects.add('<< /Length ${latin1.encode(body).length} >>\nstream\n${body}endstream');
  }
  final out = BytesBuilder();
  void write(String s) => out.add(latin1.encode(s));
  write('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toBytes();
}

/// Points PDFium at the library the build hook downloaded; `flutter test`
/// does not load native assets by itself.
void usePdfiumForTests() {
  final lib = Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build')
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere((f) => f.path.endsWith(Platform.isWindows ? 'pdfium.dll' : 'libpdfium.so'));
  Pdfrx.pdfiumModulePath = lib.absolute.path;
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.createTempSync('pdfrx').path;
}

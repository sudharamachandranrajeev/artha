/// Positioned text from a PDF, read with PDFium. Statement parsing works on
/// these words and lines so it stays independent of the PDF library.
library;

import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'statement.dart';

/// One word on a page; x grows rightwards, y downwards from the page top.
class PdfWord {
  PdfWord(this.text, this.left, this.right, this.top, this.bottom);
  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;
  double get height => bottom - top;
}

/// Words sharing a baseline, left to right.
class PdfLine {
  PdfLine(this.page, this.words);
  final int page;
  final List<PdfWord> words;
  double get top => words.map((w) => w.top).reduce((a, b) => a < b ? a : b);
  String get text => words.map((w) => w.text).join(' ');
}

/// Larger documents are not a bank statement.
const maxPdfPages = 200;

/// Reads every page's text as lines, top to bottom.
Future<List<PdfLine>> readPdfLines(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(bytes, passwordProvider: () => null);
  } on PdfPasswordException {
    throw StatementFormatException('That PDF is password protected. Save an unprotected copy first.');
  } catch (_) {
    throw StatementFormatException('That file is not a readable PDF');
  }
  try {
    if (doc.pages.length > maxPdfPages) {
      throw StatementFormatException('That PDF has over $maxPdfPages pages; it is not a statement');
    }
    final lines = <PdfLine>[];
    for (final page in doc.pages) {
      final raw = await page.loadText();
      if (raw == null) continue;
      lines.addAll(_lines(page.pageNumber, _words(raw, page.height)));
    }
    if (lines.isEmpty) {
      throw StatementFormatException(
        'That PDF has no text in it (a scan or photo). Download the statement from online banking instead.',
      );
    }
    return lines;
  } finally {
    await doc.dispose();
  }
}

List<PdfWord> _words(PdfPageRawText raw, double pageHeight) {
  final words = <PdfWord>[];
  final text = raw.fullText;
  final buf = StringBuffer();
  double l = 0, r = 0, t = 0, b = 0;
  void flush() {
    if (buf.isNotEmpty) words.add(PdfWord(buf.toString(), l, r, t, b));
    buf.clear();
  }

  for (var i = 0; i < text.length && i < raw.charRects.length; i++) {
    final c = text[i];
    final rect = raw.charRects[i];
    if (c.trim().isEmpty) {
      flush();
      continue;
    }
    final top = pageHeight - rect.top, bottom = pageHeight - rect.bottom;
    // PDFium inserts spaces where text has gaps; only a wide gap without one
    // splits here. Glyph boxes of commas and dots are tiny, so measure against
    // the word's full height so far.
    final h = buf.isEmpty
        ? (bottom - top).abs()
        : [(bottom - top).abs(), b - t].reduce((x, y) => x > y ? x : y);
    // A new word at a jump back, a gap wider than about a space, or a new line.
    if (buf.isNotEmpty && (rect.left < r - h * 0.5 || rect.left - r > h || top > b || bottom < t)) {
      flush();
    }
    if (buf.isEmpty) {
      l = rect.left;
      t = top;
      b = bottom;
    }
    buf.write(c);
    r = rect.right;
    if (top < t) t = top;
    if (bottom > b) b = bottom;
  }
  flush();
  return words;
}

/// Groups words whose vertical centres fall within half a line of each other.
List<PdfLine> _lines(int page, List<PdfWord> words) {
  final sorted = [...words]..sort((a, b) => (a.top + a.bottom).compareTo(b.top + b.bottom));
  final out = <List<PdfWord>>[];
  for (final w in sorted) {
    final mid = (w.top + w.bottom) / 2;
    final last = out.isEmpty ? null : out.last;
    if (last != null) {
      final lmid = (last.first.top + last.first.bottom) / 2;
      if ((mid - lmid).abs() <= w.height * 0.5) {
        last.add(w);
        continue;
      }
    }
    out.add([w]);
  }
  return [for (final ws in out) PdfLine(page, ws..sort((a, b) => a.left.compareTo(b.left)))];
}

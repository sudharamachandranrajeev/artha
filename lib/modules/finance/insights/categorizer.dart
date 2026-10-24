import 'dart:math' as math;

/// Learns categories from the user's own history; nothing leaves the device.
///
/// Order of evidence: explicit rules, then the exact merchant key seen
/// before, then a naive Bayes vote over words. Direction matters: money out
/// only gets spending categories (or own accounts), money in only income.
class Categorizer {
  Categorizer({required this.rules, required Iterable<Example> history, required this.directionOf}) {
    for (final e in history) {
      learn(e.text, e.categoryId);
    }
  }

  final List<CategoryRule> rules;

  /// 'out' for expense categories, 'in' for income, 'any' for own accounts.
  final String Function(String categoryId) directionOf;

  final _byKey = <String, Map<String, int>>{};
  final _tokenCounts = <String, Map<String, int>>{};
  final _catTotals = <String, int>{};
  final _vocab = <String>{};
  var _examples = 0;

  void learn(String text, String categoryId) {
    final tokens = tokenize(text);
    if (tokens.isEmpty) return;
    final key = merchantKey(tokens);
    _byKey.putIfAbsent(key, () => {}).update(categoryId, (v) => v + 1, ifAbsent: () => 1);
    final counts = _tokenCounts.putIfAbsent(categoryId, () => {});
    for (final t in tokens) {
      counts.update(t, (v) => v + 1, ifAbsent: () => 1);
      _vocab.add(t);
    }
    _catTotals.update(categoryId, (v) => v + tokens.length, ifAbsent: () => tokens.length);
    _examples++;
  }

  Suggestion? suggest(String text, int amount) {
    bool fits(String cat) {
      final d = directionOf(cat);
      return d == 'any' || (amount < 0 ? d == 'out' : d == 'in');
    }

    for (final r in rules) {
      if (r.categoryId.isNotEmpty && r.matches(text) && fits(r.categoryId)) {
        return Suggestion(r.categoryId, 1, 'rule');
      }
    }
    final tokens = tokenize(text);
    if (tokens.isEmpty || _examples == 0) return null;

    final exact = _byKey[merchantKey(tokens)];
    if (exact != null) {
      final options = exact.entries.where((e) => fits(e.key)).toList();
      if (options.isNotEmpty) {
        final total = options.fold(0, (s, e) => s + e.value);
        final best = options.reduce((a, b) => a.value >= b.value ? a : b);
        return Suggestion(best.key, best.value / total * math.min(1, 0.6 + total * 0.1), 'history');
      }
    }

    // Naive Bayes with Laplace smoothing, scored in log space.
    String? bestCat;
    var best = double.negativeInfinity;
    final scores = <double>[];
    for (final cat in _catTotals.keys) {
      if (!fits(cat)) continue;
      final counts = _tokenCounts[cat]!;
      final total = _catTotals[cat]!;
      var score = math.log(total / _examples);
      var known = 0;
      for (final t in tokens) {
        final c = counts[t] ?? 0;
        if (c > 0) known++;
        score += math.log((c + 1) / (total + _vocab.length));
      }
      if (known == 0) continue;
      scores.add(score);
      if (score > best) {
        best = score;
        bestCat = cat;
      }
    }
    if (bestCat == null) return null;
    final norm = scores.fold(0.0, (s, v) => s + math.exp(v - best));
    return Suggestion(bestCat, (1 / norm) * 0.8, 'pattern');
  }

  static const _noise = {
    'card',
    'payment',
    'payments',
    'to',
    'from',
    'pos',
    'purchase',
    'debit',
    'credit',
    'visa',
    'mastercard',
    'contactless',
    'ref',
    'reference',
    'gb',
    'gbr',
    'uk',
    'ltd',
    'limited',
    'plc',
    'www',
    'com',
    'co',
    'on',
    'at',
    'the',
    'and',
    'dd',
    'so',
    'fpo',
    'fpi',
    'bgc',
    'deb',
    'cr',
    'dr',
    'bp',
    'tfr',
    'trf',
    'via',
    'apple',
    'pay',
    'google',
    'paypal',
    'inr',
    'gbp',
    'eur',
    'usd',
    'upi',
    'imps',
    'neft',
    'ach',
  };

  /// Lower-case words without numbers, ids and payment-rail noise.
  static List<String> tokenize(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9&]+'))
      .where((t) => t.length > 1 && !RegExp(r'\d').hasMatch(t) && !_noise.contains(t))
      .toList();

  /// The first two meaningful words identify a merchant well in practice
  /// ("tesco stores 3021 london" -> "tesco stores").
  static String merchantKey(List<String> tokens) => tokens.take(2).join(' ');
}

class Example {
  const Example(this.text, this.categoryId);
  final String text;
  final String categoryId;
}

class CategoryRule {
  const CategoryRule(this.pattern, this.categoryId, {this.payee});
  final String pattern;

  /// Empty for a rule that only renames.
  final String categoryId;

  /// Name to show instead of the bank's text, or null.
  final String? payee;

  bool matches(String text) => pattern.isNotEmpty && text.toLowerCase().contains(pattern.toLowerCase());
}

/// The payee the first renaming rule gives [text], or null.
String? renamedPayee(List<CategoryRule> rules, String text) =>
    rules.where((r) => r.payee != null && r.matches(text)).firstOrNull?.payee;

class Suggestion {
  const Suggestion(this.categoryId, this.confidence, this.source);
  final String categoryId;

  /// 0..1
  final double confidence;

  /// rule | history | pattern
  final String source;
}

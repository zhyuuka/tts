import 'dart:math';

import '../core/logger/app_logger.dart';
import 'memu_service.dart';

class MemoryVector {
  final String fragmentId;
  final Map<String, double> tfidfVector;
  final String text;

  MemoryVector({
    required this.fragmentId,
    required this.tfidfVector,
    required this.text,
  });
}

class MemoryVectorSearch {
  static MemoryVectorSearch? _instance;
  static MemoryVectorSearch get instance =>
      _instance ??= MemoryVectorSearch._();

  MemoryVectorSearch._();

  final Map<String, MemoryVector> _vectors = {};
  final Map<String, int> _documentFrequency = {};
  int _totalDocuments = 0;

  bool _dirty = true;

  int get indexedCount => _vectors.length;
  bool get isIndexed => _vectors.isNotEmpty && !_dirty;

  void buildIndex(List<MemoryFragment> fragments) {
    _vectors.clear();
    _documentFrequency.clear();
    _totalDocuments = 0;

    final allTexts = <String, String>{};
    for (final fragment in fragments) {
      if (!fragment.isActive) continue;
      final tokens = _tokenize(
        '${fragment.content} ${fragment.keywords.join(' ')}',
      );
      allTexts[fragment.id] = tokens.join(' ');
    }

    _totalDocuments = allTexts.length;

    for (final entry in allTexts.entries) {
      final tokens = _tokenize(entry.value);
      final uniqueTokens = tokens.toSet();
      for (final token in uniqueTokens) {
        _documentFrequency[token] = (_documentFrequency[token] ?? 0) + 1;
      }
    }

    for (final fragment in fragments) {
      if (!fragment.isActive) continue;
      final text = '${fragment.content} ${fragment.keywords.join(' ')}';
      final vector = _computeTfIdf(fragment.id, text);
      _vectors[fragment.id] = MemoryVector(
        fragmentId: fragment.id,
        tfidfVector: vector,
        text: text,
      );
    }

    _dirty = false;
    AppLogger.d(
      '[VectorSearch] 索引构建完成: ${_vectors.length} 条记忆, ${_documentFrequency.length} 个词项',
    );
  }

  void markDirty() {
    _dirty = true;
  }

  List<(MemoryFragment, double)> search(
    String query,
    List<MemoryFragment> allFragments, {
    int topK = 5,
    double minScore = 0.1,
  }) {
    if (_dirty || _vectors.isEmpty) {
      buildIndex(allFragments.where((f) => f.isActive).toList());
    }

    final queryVector = _computeTfIdf('__query__', query);

    final fragmentMap = <String, MemoryFragment>{};
    for (final f in allFragments) {
      fragmentMap[f.id] = f;
    }

    final scores = <(String, double)>[];
    for (final entry in _vectors.entries) {
      final score = _cosineSimilarity(queryVector, entry.value.tfidfVector);
      if (score >= minScore) {
        scores.add((entry.key, score));
      }
    }

    scores.sort((a, b) => b.$2.compareTo(a.$2));

    return scores
        .take(topK)
        .map((s) {
          final fragment = fragmentMap[s.$1];
          return fragment != null ? (fragment, s.$2) : null;
        })
        .whereType<(MemoryFragment, double)>()
        .toList();
  }

  Map<String, double> _computeTfIdf(String docId, String text) {
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return {};

    final termFreq = <String, int>{};
    for (final token in tokens) {
      termFreq[token] = (termFreq[token] ?? 0) + 1;
    }

    final totalTerms = tokens.length;
    final tfidf = <String, double>{};

    for (final entry in termFreq.entries) {
      final tf = entry.value / totalTerms;
      final df = _documentFrequency[entry.key] ?? 1;
      final idf = log((_totalDocuments + 1) / (df + 1)) + 1;
      tfidf[entry.key] = tf * idf;
    }

    final norm = _vectorNorm(tfidf);
    if (norm > 0) {
      for (final key in tfidf.keys) {
        tfidf[key] = tfidf[key]! / norm;
      }
    }

    return tfidf;
  }

  double _cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    double dotProduct = 0.0;
    for (final key in a.keys) {
      if (b.containsKey(key)) {
        dotProduct += a[key]! * b[key]!;
      }
    }

    final normA = _vectorNorm(a);
    final normB = _vectorNorm(b);

    if (normA == 0 || normB == 0) return 0.0;

    return dotProduct / (normA * normB);
  }

  double _vectorNorm(Map<String, double> v) {
    double sum = 0.0;
    for (final val in v.values) {
      sum += val * val;
    }
    return sqrt(sum);
  }

  List<String> _tokenize(String text) {
    final result = <String>[];

    final chineseChars = RegExp(r'[\u4e00-\u9fff]');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (chineseChars.hasMatch(char)) {
        if (buffer.isNotEmpty) {
          _addWordTokens(buffer.toString().toLowerCase(), result);
          buffer.clear();
        }
        result.add(char);

        if (i + 1 < text.length && chineseChars.hasMatch(text[i + 1])) {
          result.add('$char${text[i + 1]}');
        }
        if (i + 2 < text.length && chineseChars.hasMatch(text[i + 2])) {
          result.add('$char${text[i + 1]}${text[i + 2]}');
        }
      } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        buffer.write(char);
      } else {
        if (buffer.isNotEmpty) {
          _addWordTokens(buffer.toString().toLowerCase(), result);
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty) {
      _addWordTokens(buffer.toString().toLowerCase(), result);
    }

    return result;
  }

  void _addWordTokens(String word, List<String> result) {
    if (word.isEmpty) return;
    result.add(word);
    if (word.length > 3) {
      for (int i = 0; i <= word.length - 3; i++) {
        result.add(word.substring(i, i + 3));
      }
    }
  }

  void clear() {
    _vectors.clear();
    _documentFrequency.clear();
    _totalDocuments = 0;
    _dirty = true;
  }

  void dispose() {
    clear();
    _instance = null;
    AppLogger.i('[VectorSearch] 已关闭');
  }
}

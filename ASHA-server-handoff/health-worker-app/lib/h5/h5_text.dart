/// Text normalisation for the H5 engine: the Dart twin of health-worker-backend/h5/normalize.py. Same steps, same result
/// (test/h5_parity_test.dart checks the two on every dev and test question).
library;

const Map<String, String> _cons = {
  'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n', 'च': 'ch', 'छ': 'ch', 'ज': 'j', 'झ': 'jh', 'ञ': 'n',
  'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n', 'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
  'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'bh', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'ळ': 'l', 'व': 'v',
  'श': 'sh', 'ष': 'sh', 'स': 's', 'ह': 'h', '\u0958': 'k', '\u0959': 'kh', '\u095a': 'g', '\u095b': 'j', '\u095c': 'd', '\u095d': 'dh', '\u095e': 'f',
};
const Map<String, String> _vowels = {
  'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au', 'ऋ': 'ri', 'ऑ': 'o',
};
const Map<String, String> _matras = {
  'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ृ': 'ri', 'ॉ': 'o',
};
const Map<String, String> _nasal = {'ं': 'n', 'ँ': 'n', 'ः': 'h'};
const String _virama = '्';
const String _nukta = '़';
const String _digitsFrom = '०१२३४५६७८९';

bool _isDev(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.codeUnitAt(0);
  return c >= 0x0900 && c <= 0x097F;
}

/// Phonetic Latin for Devanagari; every other character passes through unchanged.
String devanagariToLatin(String input) {
  var text = input;
  for (var i = 0; i < _digitsFrom.length; i++) {
    text = text.replaceAll(_digitsFrom[i], '$i');
  }
  // the nukta dot (ज़ ड़ फ़ ...) only refines a sound: drop it and read the base letter. The one-character forms are listed in _cons.
  text = text.replaceAll(_nukta, '');
  final out = StringBuffer();
  var i = 0;
  final n = text.length;
  while (i < n) {
    final ch = text[i];
    if (_cons.containsKey(ch)) {
      out.write(_cons[ch]);
      final nxt = i + 1 < n ? text[i + 1] : '';
      if (_matras.containsKey(nxt)) {
        out.write(_matras[nxt]);
        i += 2;
        continue;
      }
      if (nxt == _virama) {
        i += 2;
        continue;
      }
      final endOfWord = nxt == '' || !_isDev(nxt) || _nasal.containsKey(nxt);
      if (!endOfWord) out.write('a');
      i += 1;
      continue;
    }
    if (_vowels.containsKey(ch)) {
      out.write(_vowels[ch]);
    } else if (_matras.containsKey(ch)) {
      out.write(_matras[ch]);
    } else if (_nasal.containsKey(ch)) {
      out.write(_nasal[ch]);
    } else if (ch == _virama || ch == _nukta || ch == 'ऽ' || ch == '॥' || ch == '।') {
      out.write((ch == '॥' || ch == '।') ? ' ' : '');
    } else {
      out.write(ch);
    }
    i += 1;
  }
  return out.toString();
}

final RegExp _keep = RegExp(r'[^a-z0-9./:\- ]+');
final RegExp _doubleDigraph = RegExp(r'(ch|sh|kh|gh|th|dh|bh|jh)\1');
final RegExp _doubleLetter = RegExp(r'([a-z])\1+');

/// Phonetic folding so khoon/khun, peela/pila, bachcha/bacha meet. Applied to questions AND to every rule word.
String foldRoman(String input) {
  var s = input.replaceAll('chh', 'ch');
  for (final p in const [['aa', 'a'], ['ee', 'i'], ['ii', 'i'], ['oo', 'u'], ['uu', 'u'], ['ai', 'e'], ['ei', 'e']]) {
    s = s.replaceAll(p[0], p[1]);
  }
  s = s.replaceAll('w', 'v');
  s = s.replaceAllMapped(_doubleDigraph, (m) => m.group(1)!);
  s = s.replaceAllMapped(_doubleLetter, (m) => m.group(1)!);
  return s;
}

final RegExp _escToken = RegExp(r'(\\.|\[[^\]]*\]|\(\?[:=!<]+|[0-9{},*+?|()^$.])');

/// foldRoman for the letters of a regex source, leaving escapes (\b, \d, ...) and character classes alone.
String foldPattern(String p) {
  final out = StringBuffer();
  var i = 0;
  for (final m in _escToken.allMatches(p)) {
    out.write(foldRoman(p.substring(i, m.start)));
    out.write(m.group(0));
    i = m.end;
  }
  out.write(foldRoman(p.substring(i)));
  return out.toString();
}

const Map<String, String> _tokenMap = {'nahin': 'nahi', 'nhi': 'nahi', 'nehi': 'nahi', 'nahe': 'nahi', 'nahn': 'nahi'};
final RegExp _degree = RegExp(r'(\d)\s*°\s*');
final RegExp _stray = RegExp(r'(?<![0-9])[.\-:/]+(?![0-9a-z])');
final RegExp _spaces = RegExp(r'\s+');

String normalizeText(String? text) {
  var t = (text ?? '').toLowerCase();
  t = devanagariToLatin(t);
  t = t.replaceAll('–', '-').replaceAll('—', '-').replaceAll('−', '-');
  t = t.replaceAllMapped(_degree, (m) => '${m.group(1)} ');
  t = t.replaceAll(_keep, ' ');
  t = foldRoman(t);
  t = t.replaceAll(_stray, ' ');
  t = t.replaceAll(_spaces, ' ').trim();
  return t.split(' ').map((w) => _tokenMap[w] ?? w).join(' ');
}

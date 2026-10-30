// PERMANENT RULE (2026-10-30): every user-facing string in the app has an Arabic translation. This test fails when a
// string passed to the translator — context.t('…'), d.t('…'), ctx.t('…'), AppStrings.get/tr('…'), including both
// branches of a ternary inside the call — or an enum label (lib/models/enums.dart, shown through t()) has no entry in
// AppStrings' Arabic dictionary (lib/l10n/l10n.dart). Add the Arabic line there, never skip this test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/l10n.dart';

final _call = RegExp(r"\b(?:t|tr|AppStrings\.get)\(");
final _literal = RegExp(r"""'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"(?!")""");
final _enumLabel = RegExp(r"\w+\(\s*-?\d+\s*,\s*'((?:[^'\\]|\\.)*)'");

/// The argument text of the call starting at [open] (the '(' position), quotes respected.
String _args(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < s.length && s[i] != c) {
        if (s[i] == r'\') i++;
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return s.substring(open, i + 1);
    }
  }
  return s.substring(open);
}

bool _isUiText(String k) =>
    k.isNotEmpty && !k.contains(r'$') && RegExp('[A-Za-z]{2}').hasMatch(k) &&
    !RegExp(r'^(en|ar|m²)$').hasMatch(k) && !RegExp(r'^[a-z][A-Za-z]*$').hasMatch(k); // codes like 'downloadCancelled'

void main() {
  test('every translated UI string and enum label has an Arabic translation', () {
    final arabic = AppStrings.arabicKeys.toSet();
    final missing = <String, Set<String>>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('l10n.dart')) continue;
      final src = f.readAsStringSync();
      final keys = <String>{};
      for (final m in _call.allMatches(src)) {
        final args = _args(src, m.end - 1);
        for (final l in _literal.allMatches(args)) {
          // literals that are arguments of a nested call (DateFormat('MMM'), .split(',')) are not UI text
          final before = args.substring(0, l.start).trimRight();
          if (RegExp(r'(DateFormat|format|split|replaceAll|startsWith|contains|parse)\($').hasMatch(before)) continue;
          keys.add((l.group(1) ?? l.group(2))!.replaceAll(r"\'", "'"));
        }
      }
      if (f.path.endsWith('enums.dart')) {
        for (final m in _enumLabel.allMatches(src)) {
          keys.add(m.group(1)!);
        }
      }
      for (final k in keys.where(_isUiText)) {
        if (!arabic.contains(k)) (missing[k] ??= {}).add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(missing, isEmpty, reason: 'Arabic translation missing (add to AppStrings._ar in lib/l10n/l10n.dart):\n'
        '${missing.entries.map((e) => '  "${e.key}"  ← ${e.value.join(', ')}').join('\n')}');
  });
}

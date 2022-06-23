/// 介面語言選擇器：列出「跟隨系統」與四種語言，選擇後立即生效並寫入本地。
///
/// 選項名稱採「以該語言本身書寫」的慣例，不進本地化資源：
/// 換語言時選項不應跟著翻譯，否則使用者無法認出自己點的是哪一項。
library;

import 'package:flutter/material.dart';

import '../../core/app_locale.dart';
import '../../core/language_settings.dart';
import '../../l10n/app_localizations.dart';
import '../language_scope.dart';

/// 介面語言選擇器。
class LanguageSelector extends StatelessWidget {
  /// 建立選擇器。
  const LanguageSelector({super.key});

  /// 下拉選單的測試識別鍵。
  static const Key dropdownKey = ValueKey<String>('language-selector');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final LanguageSettings settings = LanguageScope.of(context);
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.interfaceLanguageTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: DropdownButton<AppLocale?>(
                key: dropdownKey,
                value: settings.followsSystem ? null : settings.effective,
                items: <DropdownMenuItem<AppLocale?>>[
                  DropdownMenuItem<AppLocale?>(
                    value: null,
                    child: Text(l10n.interfaceLanguageFollowSystem),
                  ),
                  for (final AppLocale locale in AppLocale.values)
                    DropdownMenuItem<AppLocale?>(
                      value: locale,
                      child: Text(locale.endonym),
                    ),
                ],
                onChanged: (AppLocale? selected) async {
                  await settings.select(selected);
                },
              ),
            ),
          ],
        ),
        if (settings.followsSystem)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.labelValuePair(
                l10n.interfaceLanguageFollowSystem,
                settings.effective.endonym,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

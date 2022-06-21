/// 頂層上下文的共用內容視圖：說明該上下文的範圍，並如實標明後端尚未實作。
///
/// 這裡刻意不放任何範例、模擬或佔位的業務資料（清單、餘額、玩家名稱等一律不出現），
/// 讓「尚未開發」在介面上是可讀的事實，而不是看起來像已運作的空壳。
library;

import 'package:flutter/material.dart';

import '../../core/app_copy.dart';
import '../nav_context.dart';

/// 「後端尚未實作」的內容視圖。
class NotWiredView extends StatelessWidget {
  /// 以說明文字與提示建立視圖。
  const NotWiredView({
    super.key,
    required this.detail,
    this.body = AppCopy.notWiredBody,
    this.hint = AppCopy.notWiredHint,
  });

  /// 由頂層上下文建立該上下文的說明。
  factory NotWiredView.forContext(NavContext navContext) {
    return NotWiredView(detail: navContext.summary);
  }

  /// 為未註冊的路由建立說明。
  factory NotWiredView.forUnknownRoute(String routeName) {
    return NotWiredView(
      detail: '要求的路由：$routeName',
      body: AppCopy.unknownRouteBody,
    );
  }

  /// 上下文範圍說明。
  final String detail;

  /// 狀態說明文字。
  final String body;

  /// 補充提示文字。
  final String hint;

  /// 狀態說明的測試識別鍵。
  static const Key bodyKey = ValueKey<String>('not-wired-body');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Text(detail, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        Text(body, key: bodyKey, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

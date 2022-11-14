/// 「我的裝置」面板：讓已登入的主體查看並撤銷自己名下的會話（裝置）。
///
/// 這張卡存在的理由與界線全部落在會話層與後端合同上，這裡只做呈現與確認：
///
/// * 只管理「自己」：清單由 [SessionController.listMyDevices] 取回，範圍由後端按
///   解析出的受信主體決定——面板不傳任何 device_id／account_id 去指定「列誰的裝置」，
///   也看不到任何憑據材料（合同裡就沒有）。撤銷走 [SessionController.revokeMyDevice]。
/// * 當前裝置被明確標記，且撤它時說清楚「這等同在本機登出」：撤銷自己這臺之後，
///   會話層進入退出態，這張面板隨之關閉，後方的會話卡改口呈現登出／失效。
/// * 列表陳舊（2009）、會話已失效（2003／2002）、連不上（查不了）各說各句：
///   把「查不了」講成「已登出」、把「早已失效」講成「我剛撤掉了它」，都是謊報。
///
/// 內容在對話框內自行滾動：對話框是一條覆蓋式路由，不歸應用殼的滾動區管。
library;

import 'package:flutter/material.dart';

import '../../core/api/server_models.dart';
import '../../core/app_locale.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';

/// 從現有上下文開啟「我的裝置」面板。[session] 由已登入的會話卡傳入，
/// 對話框自己的路由可能取不到會話作用域，因此顯式帶進來而不是在裡面向樹要。
Future<void> showMyDevicesDialog(
  BuildContext context,
  SessionController session,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => MyDevicesDialog(session: session),
  );
}

/// 階段：載入中、就緒、載入失敗（查不了）。會話失效與未登出會直接關閉對話框。
enum _Phase { loading, ready, failed }

/// 「我的裝置」對話框。
class MyDevicesDialog extends StatefulWidget {
  /// 以會話控制器建立面板。
  const MyDevicesDialog({super.key, required this.session});

  /// 讀取與撤銷都經這個控制器（狀態收斂全部在它那裡，頁面不各寫一套）。
  final SessionController session;

  /// 載入失敗後的重試按鈕識別鍵。
  static const Key retryKey = ValueKey<String>('devices-retry');

  /// 載入中的中性提示識別鍵。
  static const Key loadingKey = ValueKey<String>('devices-loading');

  /// 空清單提示識別鍵。
  static const Key emptyKey = ValueKey<String>('devices-empty');

  /// 依裝置標識產生該列撤銷按鈕的識別鍵。
  static Key revokeKey(String deviceId) =>
      ValueKey<String>('devices-revoke-$deviceId');

  @override
  State<MyDevicesDialog> createState() => _MyDevicesDialogState();
}

class _MyDevicesDialogState extends State<MyDevicesDialog> {
  _Phase _phase = _Phase.loading;
  List<DeviceReport> _devices = const <DeviceReport>[];

  /// 正在撤銷中的裝置標識：該列按鈕停用，防連點產生第二趟撤銷請求。
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 目前介面語言對應的 Accept-Language 標記。
  String get _acceptLanguage =>
      resolveAppLocale(Localizations.localeOf(context)).tag;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() => _phase = _Phase.loading);
    final SessionDeviceListResult result = await widget.session.listMyDevices(
      acceptLanguage: _acceptLanguage,
    );
    if (!mounted) {
      return;
    }
    switch (result.outcome) {
      case SessionDeviceListOutcome.loaded:
        setState(() {
          _devices = result.devices;
          _phase = _Phase.ready;
        });
      case SessionDeviceListOutcome.unavailable:
        setState(() => _phase = _Phase.failed);
      case SessionDeviceListOutcome.expired:
      case SessionDeviceListOutcome.notSignedIn:
        // 已沒有可管理這份清單的會話上下文：關閉面板，後方卡片會呈現對應狀態。
        Navigator.of(context).pop();
    }
  }

  /// 一次定向撤銷：確認 → 呼叫控制器 → 依結果分岔（關閉／提示＋刷新）。
  Future<void> _revoke(DeviceReport device) async {
    if (_busy.contains(device.deviceId)) {
      return;
    }
    final AppLocalizations l10n = _l10n;
    final bool confirmed = await _confirmRevoke(context, l10n, device);
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy.add(device.deviceId));
    final SessionDeviceRevokeOutcome outcome = await widget.session
        .revokeMyDevice(device.deviceId, acceptLanguage: _acceptLanguage);
    if (!mounted) {
      return;
    }
    setState(() => _busy.remove(device.deviceId));

    switch (outcome) {
      case SessionDeviceRevokeOutcome.revokedCurrent:
        // 撤的是自己這臺：會話層已進入退出態，面板沒有存在意義，關閉並告知。
        _snack(l10n.devicesRevokeCurrentSuccessNotice);
        Navigator.of(context).pop();
      case SessionDeviceRevokeOutcome.revoked:
        _snack(l10n.devicesRevokeSuccessNotice);
        await _load();
      case SessionDeviceRevokeOutcome.alreadyInactive:
        _snack(l10n.devicesRevokeAlreadyInactiveNotice);
        await _load();
      case SessionDeviceRevokeOutcome.staleList:
        _snack(l10n.devicesRevokeStaleNotice);
        await _load();
      case SessionDeviceRevokeOutcome.expired:
      case SessionDeviceRevokeOutcome.notSignedIn:
        Navigator.of(context).pop();
      case SessionDeviceRevokeOutcome.unavailable:
        _snack(l10n.devicesRevokeUnavailableNotice);
    }
  }

  /// 把一句提示經 ScaffoldMessenger 送達（面板即將關閉時，SnackBar 才講得完）。
  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = _l10n;
    return AlertDialog(
      title: Text(l10n.devicesDialogTitle),
      content: SizedBox(width: 420, child: _body(l10n)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.devicesRevokeCancelAction),
        ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    switch (_phase) {
      case _Phase.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.devicesLoadingHint,
                  key: MyDevicesDialog.loadingKey,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      case _Phase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.devicesLoadFailedNotice,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: MyDevicesDialog.retryKey,
              onPressed: _load,
              child: Text(l10n.devicesRetryAction),
            ),
          ],
        );
      case _Phase.ready:
        if (_devices.isEmpty) {
          return Text(
            l10n.devicesEmptyNotice,
            key: MyDevicesDialog.emptyKey,
            style: theme.textTheme.bodyMedium,
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _devices
                .map((DeviceReport d) => _tile(l10n, theme, d))
                .toList(),
          ),
        );
    }
  }

  Widget _tile(AppLocalizations l10n, ThemeData theme, DeviceReport device) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                device.deviceId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (device.current)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _Badge(text: l10n.devicesCurrentBadge),
              ),
          ],
        ),
        Text(
          l10n.labelValuePair(
            l10n.devicesCreatedLabel,
            _formatUtcMinute(device.createdAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.devicesLastActiveLabel,
            _formatUtcMinute(device.lastActiveAt),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.labelValuePair(
            l10n.deviceStatusLabel,
            _statusText(l10n, device.status),
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (device.isActive)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              key: MyDevicesDialog.revokeKey(device.deviceId),
              onPressed: _busy.contains(device.deviceId)
                  ? null
                  : () => _revoke(device),
              child: Text(
                device.current
                    ? l10n.devicesRevokeCurrentAction
                    : l10n.devicesRevokeAction,
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }

  /// 狀態原字串 → 顯示文字；未知值原樣顯示（後端日後多一種狀態不至於顯示空白）。
  String _statusText(AppLocalizations l10n, String status) {
    return switch (status) {
      'active' => l10n.deviceStatusActive,
      'expired' => l10n.deviceStatusExpired,
      'revoked' => l10n.deviceStatusRevoked,
      _ => status,
    };
  }

  /// 以「年-月-日 時:分 UTC」呈現，與會話卡同一寫法：不做本機時區換算。
  static String _formatUtcMinute(DateTime utc) {
    final String iso = utc.toUtc().toIso8601String();
    return '${iso.substring(0, 10)} ${iso.substring(11, 16)} UTC';
  }
}

/// 「當前裝置」徽章：把「這就是你正在用的那一臺」標在視覺上。
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 撤銷確認：點名目標裝置，說明立即失效且不可逆；撤的是當前裝置時多一行警告。
Future<bool> _confirmRevoke(
  BuildContext context,
  AppLocalizations l10n,
  DeviceReport device,
) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(l10n.devicesRevokeConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.devicesRevokeConfirmBody(device.deviceId)),
          if (device.current) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.devicesRevokeCurrentWarning,
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.devicesRevokeCancelAction),
        ),
        FilledButton(
          key: const ValueKey<String>('devices-revoke-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.devicesRevokeConfirmAction),
        ),
      ],
    ),
  );
  return result ?? false;
}

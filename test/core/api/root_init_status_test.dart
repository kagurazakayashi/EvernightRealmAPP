/// 狀態判定的單元測試：每一種查詢結果只能落到一個介面階段。
///
/// 這裡要釘的是「查不到時不許落成一個狀態」：把失敗折成 `uninitialized`，
/// 引導卡就會對一個連不上的部署列出一整套初始化步驟；折成 `initialized`，
/// 則會對一個還沒初始化完的部署說「已經好了」。兩者都是這張卡唯一不能犯的錯。
library;

import 'package:evernightrealm/core/api/api_error.dart';
import 'package:evernightrealm/core/api/root_init_status.dart';
import 'package:evernightrealm/core/api/server_api.dart';
import 'package:evernightrealm/core/api/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 直接構造一份狀態（判定邏輯不涉網路，无需假傳輸）。
InitStatusReport report({
  bool configExists = true,
  bool rootInitialized = false,
  bool envOverride = false,
}) {
  return InitStatusReport(
    configExists: configExists,
    rootInitialized: rootInitialized,
    envOverride: envOverride,
    requestId: 'r-test',
  );
}

void main() {
  group('查詢成功', () {
    test('root_initialized 為真就是已初始化', () {
      expect(
        classifyInitStatus(report(rootInitialized: true)),
        RootInitPhase.initialized,
      );
    });

    test('為假就是未初始化，與組態檔存不存在無關', () {
      // configExists 決定的是那一句話要怎麼講，不是第三種階段。
      expect(
        classifyInitStatus(report(configExists: false)),
        RootInitPhase.uninitialized,
      );
      expect(
        classifyInitStatus(report(configExists: true)),
        RootInitPhase.uninitialized,
      );
    });

    test('環境變數覆蓋不會把未初始化改判成已初始化', () {
      // env_override 是給文字用的，不是一種狀態：它講的是「檔案裡沒有」
      // 這句話的可信度，而不是「其實有」。
      expect(
        classifyInitStatus(report(envOverride: true)),
        RootInitPhase.uninitialized,
      );
    });
  });

  group('查詢失敗', () {
    test('連不上與逾時都算「無從得知」，不是未初始化', () {
      for (final ApiErrorKind kind in <ApiErrorKind>[
        ApiErrorKind.unreachable,
        ApiErrorKind.timeout,
      ]) {
        expect(
          classifyInitStatusFailure(
            ApiError(kind: kind, path: kRootInitStatusPath),
          ),
          RootInitPhase.unreachable,
        );
      }
    });

    test('位址不可用時照實回「無從查起」', () {
      expect(
        classifyInitStatusFailure(
          ApiError(kind: ApiErrorKind.notConfigured, path: kRootInitStatusPath),
        ),
        RootInitPhase.notConfigured,
      );
    });

    test('需要身分或被拒來源算無權限，與其他錯誤分開', () {
      for (final ApiMachineCode code in <ApiMachineCode>[
        ApiMachineCode.notAuthenticated,
        ApiMachineCode.sessionInvalid,
        ApiMachineCode.originForbidden,
      ]) {
        expect(
          classifyInitStatusFailure(
            ApiError(
              kind: ApiErrorKind.httpStatus,
              path: kRootInitStatusPath,
              httpStatus: 403,
              machineCode: code.value,
            ),
          ),
          RootInitPhase.forbidden,
        );
      }
    });

    test('沒有機器碼但回了 401／403 也算無權限', () {
      for (final int status in <int>[401, 403]) {
        expect(
          classifyInitStatusFailure(
            ApiError(
              kind: ApiErrorKind.httpStatus,
              path: kRootInitStatusPath,
              httpStatus: status,
            ),
          ),
          RootInitPhase.forbidden,
        );
      }
    });

    test('內容抵觸合同與其他 HTTP 錯誤一律是「結果不明確」', () {
      expect(
        classifyInitStatusFailure(
          ApiError(
            kind: ApiErrorKind.invalidResponse,
            path: kRootInitStatusPath,
          ),
        ),
        RootInitPhase.unknown,
      );
      for (final ApiMachineCode code in <ApiMachineCode>[
        ApiMachineCode.internalError,
        ApiMachineCode.notFound,
        ApiMachineCode.notReady,
      ]) {
        expect(
          classifyInitStatusFailure(
            ApiError(
              kind: ApiErrorKind.httpStatus,
              path: kRootInitStatusPath,
              httpStatus: 500,
              machineCode: code.value,
            ),
          ),
          RootInitPhase.unknown,
        );
      }
    });
  });
}

import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 指纹能力探测结果 */
export interface FpCapability {
  /** 是否可发起指纹验证（设备已录入指纹且信任等级受支持） */
  available: boolean;
  /** 不可用原因，可直接展示给用户；available 为 true 时为空串 */
  reason: string;
}

/** 认证等级解析结果 */
export interface FpLevel {
  /** 实际可用的认证等级；null 表示不可用 */
  level: userAuth.AuthTrustLevel | null;
  /** 不可用原因 */
  reason: string;
}

/**
 * 家长锁指纹解锁封装（HarmonyOS 7 UserAuthenticationKit）。
 *
 * 本 SDK 的关键形态（与旧版差异大，勿照搬旧写法）：
 *  - 实例用 getUserAuthInstance(authParam, widgetParam) 创建；
 *    getAuthInstance 是已废弃的 API 9 旧接口（3 参数、返回 AuthInstance），勿用
 *  - getAvailableStatus 返回 void，通过抛错判定能力：
 *    12500005 类型不支持 / 12500006 信任等级不支持 / 12500010 未录入凭据
 *  - AuthParam.challenge 为必填
 *  - IAuthCallback 只有 onResult，取消/超时等通过 result.result 错误码区分
 *
 * 注意：ohos.permission.ACCESS_BIOMETRIC 是 system_grant 权限，
 * 只需在 module.json5 声明即可，不需要也不能运行时申请。
 */
export class FingerprintAuth {
  /** 探测本机指纹能力：指纹通常为 ATL2，不足时降级 ATL1 */
  static check(): FpCapability {
    const resolved = FingerprintAuth.resolveLevel();
    return { available: resolved.level !== null, reason: resolved.reason };
  }

  /**
   * 发起一次指纹验证。
   * @param onSuccess 验证通过
   * @param onFail 失败/取消/超时，msg 为可读提示
   */
  static auth(onSuccess: () => void, onFail: (msg: string) => void): void {
    const resolved = FingerprintAuth.resolveLevel();
    if (resolved.level === null) {
      onFail(resolved.reason);
      return;
    }
    const level: userAuth.AuthTrustLevel = resolved.level;

    try {
      const authParam: userAuth.AuthParam = {
        challenge: FingerprintAuth.challenge(),
        authType: [userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: level
      };
      const widgetParam: userAuth.WidgetParam = {
        title: '指纹解锁家长模式'
      };
      // 一个实例只用于一次认证，每次验证都新建
      const instance = userAuth.getUserAuthInstance(authParam, widgetParam);
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult): void => {
          instance.off('result');
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            onSuccess();
          } else {
            onFail(FingerprintAuth.describe(result.result));
          }
        }
      };
      // 必须先订阅再 start，否则会丢结果
      instance.on('result', callback);
      instance.start();
    } catch (err) {
      onFail('无法启动指纹验证，请改用密码解锁');
    }
  }

  /** 解析本机可用认证等级：指纹多为 ATL2，不足时降级 ATL1 */
  private static resolveLevel(): FpLevel {
    const levels: userAuth.AuthTrustLevel[] = [
      userAuth.AuthTrustLevel.ATL2,
      userAuth.AuthTrustLevel.ATL1
    ];
    let lastCode: number = 0;
    for (const lv of levels) {
      try {
        userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, lv);
        return { level: lv, reason: '' };
      } catch (err) {
        const code = (err as BusinessError).code;
        if (code === 12500010) {
          // 设备支持指纹但用户未录入凭据
          return { level: null, reason: '还没有录入指纹，请先在系统设置里录入指纹' };
        }
        lastCode = code;
      }
    }
    if (lastCode === 12500005) {
      return { level: null, reason: '本设备不支持指纹解锁' };
    }
    return { level: null, reason: '本设备指纹安全等级不足，请改用密码解锁' };
  }

  /** 认证结果码转可读提示 */
  private static describe(code: number): string {
    if (code === 12500001) {
      return '指纹不匹配，请再试一次';
    }
    if (code === 12500002) {
      return '验证出错，请改用密码解锁';
    }
    if (code === 12500003) {
      return '已取消指纹验证';
    }
    if (code === 12500004) {
      return '验证超时，请再试一次';
    }
    if (code === 12500005) {
      return '本设备不支持指纹解锁';
    }
    if (code === 12500006) {
      return '设备指纹安全等级不足，请改用密码解锁';
    }
    if (code === 12500007) {
      return '系统繁忙，请稍后再试';
    }
    if (code === 12500009) {
      return '指纹已锁定，请改用密码解锁';
    }
    if (code === 12500010) {
      return '还没有录入指纹，请先在系统设置里录入指纹';
    }
    if (code === 12500011) {
      return '已取消验证';
    }
    if (code === 12500013) {
      return '锁屏密码已过期，请改用密码解锁';
    }
    return '指纹验证未通过，请再试一次';
  }

  /** 生成本次认证挑战值（防重放，用系统 CSPRNG） */
  private static challenge(): Uint8Array {
    try {
      const rand = cryptoFramework.createRandom();
      return rand.generateRandomSync(16).data;
    } catch (err) {
      return new Uint8Array([1, 5, 1, 8, 0, 7]);
    }
  }
}

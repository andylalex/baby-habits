import cryptoFramework from '@ohos.security.cryptoFramework';
import { SettingsDao } from '../db/Dao';

const PIN_KEY: string = 'parent_pin'; // 存储格式: salt:sha256(salt+pin)

/**
 * 家长锁：4 位数字 PIN，加盐 SHA-256 哈希存储，不明文保存（技术方案 §5.1）。
 * 说明：SDK 26 中 @kit.CryptoFrameworkKit / @kit.ArkTSUtils 无 kit 配置，改用底层模块 + 纯 TS 字节转换。
 */
export class PinLock {
  private static toBytes(s: string): Uint8Array {
    const bytes = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) {
      bytes[i] = s.charCodeAt(i) & 0xff; // PIN 仅数字 + ASCII salt，直接按字节取
    }
    return bytes;
  }

  static hash(pin: string, salt: string): string {
    try {
      const md = cryptoFramework.createMd('SHA256');
      md.updateSync({ data: PinLock.toBytes(salt + pin) });
      const digest = md.digestSync();
      let hex = '';
      for (let i = 0; i < digest.data.length; i++) {
        const v = digest.data[i].toString(16);
        hex += v.length === 1 ? `0${v}` : v;
      }
      return hex;
    } catch (err) {
      // 端侧摘要不可用时走兜底，绝不让家长锁页面崩掉
      return PinLock.fallbackHash(salt + pin);
    }
  }

  /** 兜底摘要：4 轮 FNV-1a 拼接（仅本地家长锁使用，摘要不可用时保底） */
  private static fallbackHash(s: string): string {
    let hex = '';
    for (let r = 0; r < 4; r++) {
      let h: number = 0x811c9dc5 + r * 0x01000193;
      for (let i = 0; i < s.length; i++) {
        h = (h ^ (s.charCodeAt(i) + r)) >>> 0;
        h = Math.imul(h, 0x01000193) >>> 0;
      }
      hex += h.toString(16).padStart(8, '0');
    }
    return hex;
  }

  private static newSalt(): string {
    return `${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
  }

  static async hasPin(): Promise<boolean> {
    const stored = await SettingsDao.get(PIN_KEY);
    return stored !== null && stored.includes(':');
  }

  static async verify(pin: string): Promise<boolean> {
    const stored = await SettingsDao.get(PIN_KEY);
    if (!stored) {
      return false;
    }
    const idx = stored.indexOf(':');
    const salt = stored.substring(0, idx);
    const expect = stored.substring(idx + 1);
    return PinLock.hash(pin, salt) === expect;
  }

  static async setPin(pin: string): Promise<void> {
    const salt = PinLock.newSalt();
    await SettingsDao.set(PIN_KEY, `${salt}:${PinLock.hash(pin, salt)}`);
  }
}

/**
 * 生日 → 年龄换算工具（纯逻辑，不碰 UI 与数据库）。
 *
 * 为什么单独一个类：
 * · 「按生日算年龄」的规则只应有一处实现——首次引导按它挑默认模板、
 *   家长模式按它显示年龄、任务管理页按它预选年龄档位，三处都调这里，
 *   避免各写一套算法导致口径不一致（比如差一岁）。
 * · 日期以 `YYYY-MM-DD` 字符串存储（SQLite TEXT，排序友好、可直接比较）。
 */
import { AgeTemplates } from './AgeTemplate';

export class AgeUtil {
  /** 未设置生日时用它兜底（2 岁档是模板包的最低档） */
  static readonly DEFAULT_AGE: number = 4;

  /**
   * 生日 → 周岁。
   * 空串/格式不对返回 -1（表示"未知"）。
   *
   * 算法：先算年份差，若【今年的生日还没到】则减一岁。
   * 例：生日 2020-06-15，今天 2026-10-31 → 6 岁（生日已过）；
   *     生日 2020-12-01，今天 2026-10-31 → 5 岁（生日未到）。
   */
  static ageOf(birthday: string): number {
    if (birthday === '' || birthday.length < 10) {
      return -1;
    }
    const parts = birthday.split('-');
    if (parts.length < 3) {
      return -1;
    }
    const by = Number(parts[0]);
    const bm = Number(parts[1]);
    const bd = Number(parts[2]);
    if (Number.isNaN(by) || Number.isNaN(bm) || Number.isNaN(bd) ||
      by <= 0 || bm < 1 || bm > 12 || bd < 1 || bd > 31) {
      return -1;
    }
    const now = new Date();
    let age = now.getFullYear() - by;
    // 今年生日还没过 → 减一岁
    const curMonth = now.getMonth() + 1;
    const curDay = now.getDate();
    if (curMonth < bm || (curMonth === bm && curDay < bd)) {
      age--;
    }
    return age < 0 ? -1 : age;
  }

  /** 年龄是否已可映射到分龄模板（2-10 岁） */
  static hasTemplate(age: number): boolean {
    return age >= 2 && age <= 10;
  }

  /**
   * 年龄 → 模板档位。
   * · 年龄未知（-1，没填生日）→ 用默认档；
   * · 年龄已知但超出 2-10（太小或太大）→ **夹到最近一档**（1 岁用 2 岁档，12 岁用 10 岁档），
   *   而不是回退到 4 岁 —— 夹取更贴近真实发育阶段。
   */
  static templateAge(age: number): number {
    if (age < 0) {
      return AgeUtil.DEFAULT_AGE;
    }
    const min = AgeTemplates.AGES[0];
    const max = AgeTemplates.AGES[AgeTemplates.AGES.length - 1];
    if (age < min) {
      return min;
    }
    if (age > max) {
      return max;
    }
    return age;
  }

  /** 把 Date 组装成 `YYYY-MM-DD`（月/日补零，排序友好） */
  static formatDate(year: number, month: number, day: number): string {
    const m = `${month}`.padStart(2, '0');
    const d = `${day}`.padStart(2, '0');
    return `${year}-${m}-${d}`;
  }

  /** 把 `YYYY-MM-DD` 解析成「年 / 月 / 日」；格式不对返回 null */
  static parseDate(text: string): Date | null {
    if (text.length < 10) {
      return null;
    }
    const parts = text.split('-');
    const y = Number(parts[0]);
    const m = Number(parts[1]);
    const d = Number(parts[2]);
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) {
      return null;
    }
    return new Date(y, m - 1, d);
  }

  /** 生日的中文展示（`2021年3月5日`）；未设置返回空串 */
  static birthdayLabel(birthday: string): string {
    if (birthday.length < 10) {
      return '';
    }
    const parts = birthday.split('-');
    if (parts.length < 3) {
      return '';
    }
    return `${parts[0]}年${Number(parts[1])}月${Number(parts[2])}日`;
  }
}

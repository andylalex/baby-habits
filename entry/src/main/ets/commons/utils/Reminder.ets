import { common } from '@kit.AbilityKit';
// 经典模块路径：本 SDK 的 Kit 聚合类型与文档不一致，ohos 模块保留原类型
import reminderAgentManager from '@ohos.reminderAgentManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsDao } from '../db/Dao';

const DOMAIN = 0x0001;
const TAG = 'Reminder';

/** 设置键：开关、早晚时间（HH:mm）、系统提醒 ID */
const KEY_ON = 'reminder_on';
const KEY_MORNING = 'reminder_morning';
const KEY_EVENING = 'reminder_evening';
const KEY_ID_M = 'reminder_id_morning';
const KEY_ID_E = 'reminder_id_evening';

const DEFAULT_MORNING = '07:30';
const DEFAULT_EVENING = '20:30';

/**
 * 早晚打卡提醒：ReminderAgent 代理提醒，系统到点弹通知，应用被杀也能触发。
 * 需要 ohos.permission.PUBLISH_AGENT_REMINDER（已在 module.json5 声明）。
 */
export class Reminder {
  static parseTime(hhmm: string): number[] {
    const parts = hhmm.split(':');
    if (parts.length === 2) {
      return [Number(parts[0]), Number(parts[1])];
    }
    return [7, 30];
  }

  static async isOn(): Promise<boolean> {
    return (await SettingsDao.get(KEY_ON)) === '1';
  }

  static async morningTime(): Promise<string> {
    return (await SettingsDao.get(KEY_MORNING)) ?? DEFAULT_MORNING;
  }

  static async eveningTime(): Promise<string> {
    return (await SettingsDao.get(KEY_EVENING)) ?? DEFAULT_EVENING;
  }

  /** 发布一条每日定点提醒，返回系统提醒 ID（闹钟类型：时分 + 每周重复） */
  private static async publishDaily(ctx: common.UIAbilityContext, hhmm: string, title: string,
    content: string, notificationId: number): Promise<number> {
    const hm = Reminder.parseTime(hhmm);
    const request: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: hm[0],
      minute: hm[1],
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: title,
      content: content,
      notificationId: notificationId,
      wantAgent: {
        pkgName: ctx.applicationInfo.name,
        abilityName: 'EntryAbility'
      }
    };
    return reminderAgentManager.publishReminder(request);
  }

  private static async cancelOne(key: string): Promise<void> {
    const raw = await SettingsDao.get(key);
    if (raw !== null && raw !== '') {
      try {
        await reminderAgentManager.cancelReminder(Number(raw));
      } catch (err) {
        hilog.info(DOMAIN, TAG, 'cancel reminder %{public}s: %{public}s', raw, String(err));
      }
      await SettingsDao.set(key, '');
    }
  }

  /** 打开提醒：按设置里的早晚时间重新发布（幂等，先取消旧的） */
  static async enable(ctx: common.UIAbilityContext): Promise<void> {
    await Reminder.cancelOne(KEY_ID_M);
    await Reminder.cancelOne(KEY_ID_E);
    const morning = await Reminder.morningTime();
    const evening = await Reminder.eveningTime();
    const idM = await Reminder.publishDaily(ctx, morning, '☀️ 早安打卡',
      `早上好！该完成今日任务啦（${morning}）`, 1001);
    const idE = await Reminder.publishDaily(ctx, evening, '🌙 晚间打卡',
      `今天任务做完了吗？坚持就是胜利（${evening}）`, 1002);
    await SettingsDao.set(KEY_ID_M, `${idM}`);
    await SettingsDao.set(KEY_ID_E, `${idE}`);
    await SettingsDao.set(KEY_ON, '1');
  }

  /** 关闭提醒：取消两条并清状态 */
  static async disable(): Promise<void> {
    await Reminder.cancelOne(KEY_ID_M);
    await Reminder.cancelOne(KEY_ID_E);
    await SettingsDao.set(KEY_ON, '0');
  }

  /** 修改时间：存设置，开着提醒则重新发布 */
  static async setTime(ctx: common.UIAbilityContext, which: 'morning' | 'evening', hhmm: string): Promise<void> {
    await SettingsDao.set(which === 'morning' ? KEY_MORNING : KEY_EVENING, hhmm);
    if (await Reminder.isOn()) {
      await Reminder.enable(ctx);
    }
  }
}

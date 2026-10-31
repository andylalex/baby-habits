import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'CardStore';
const PREF_NAME = 'today_card_prefs';
const KEY_IDS = 'form_ids';

/**
 * 桌面卡片 ID 存取：FormExtensionAbility 与 UIAbility 分属不同进程，
 * 通过 preferences 共享卡片 ID 列表，打卡后逐张刷新。
 */
export class CardStore {
  private static async pref(ctx: common.Context): Promise<preferences.Preferences> {
    return preferences.getPreferences(ctx, PREF_NAME);
  }

  /** 记录一张新卡片 */
  static async add(ctx: common.Context, formId: string): Promise<void> {
    try {
      const pref = await CardStore.pref(ctx);
      const ids = await pref.get(KEY_IDS, '[]') as string;
      const arr: string[] = JSON.parse(ids) as string[];
      if (arr.indexOf(formId) < 0) {
        arr.push(formId);
        await pref.put(KEY_IDS, JSON.stringify(arr));
        await pref.flush();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'add form id failed: %{public}s', String(err));
    }
  }

  /** 移除卡片 */
  static async remove(ctx: common.Context, formId: string): Promise<void> {
    try {
      const pref = await CardStore.pref(ctx);
      const ids = await pref.get(KEY_IDS, '[]') as string;
      const arr: string[] = (JSON.parse(ids) as string[]).filter((id: string) => id !== formId);
      await pref.put(KEY_IDS, JSON.stringify(arr));
      await pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'remove form id failed: %{public}s', String(err));
    }
  }

  /** 全部卡片 ID */
  static async ids(ctx: common.Context): Promise<string[]> {
    try {
      const pref = await CardStore.pref(ctx);
      const ids = await pref.get(KEY_IDS, '[]') as string;
      return JSON.parse(ids) as string[];
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'read form ids failed: %{public}s', String(err));
      return [];
    }
  }
}

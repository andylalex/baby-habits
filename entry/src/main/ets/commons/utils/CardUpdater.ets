import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardStore } from './CardStore';
import { CheckinDao, StarDao, TaskDao } from '../db/Dao';
import { SeedData } from '../db/SeedData';
import { DatabaseHelper } from '../db/DatabaseHelper';

const DOMAIN = 0x0001;
const TAG = 'CardUpdater';

/** 桌面卡片数据契约（formBindingData 需要显式类型） */
interface CardFormData {
  balance: string;
  remaining: string;
}

/** 桌面卡片刷新：打卡/兑换后调用，把余额与剩余任务数推到所有桌面卡片 */
export class CardUpdater {
  static async refresh(ctx: common.Context): Promise<void> {
    try {
      const kidId = SeedData.DEMO_KID_ID;
      const today = DatabaseHelper.today();
      const tasks = await TaskDao.listActive(kidId);
      const doneIds = await CheckinDao.todayDoneTaskIds(kidId, today);
      const remaining = tasks.filter((t) => !doneIds.has(t.id)).length;
      const balance = await StarDao.balance(kidId);
      const payload: CardFormData = { balance: `${balance}`, remaining: `${remaining}` };
      const data = formBindingData.createFormBindingData(payload);
      const ids = await CardStore.ids(ctx);
      for (const id of ids) {
        await formProvider.updateForm(id, data);
      }
    } catch (err) {
      // 卡片刷新失败不影响主流程
      hilog.error(DOMAIN, TAG, 'refresh cards failed: %{public}s', String(err));
    }
  }
}

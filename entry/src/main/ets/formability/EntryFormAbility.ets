import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility } from '@kit.FormKit';
import { CardStore } from '../commons/utils/CardStore';

/**
 * 桌面卡片能力：添加卡片时记录 ID 并给初始数据；打卡后由 CardUpdater 主动刷新。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = (want.parameters as Record<string, Object>)['ohos.extra.param.key.form_identity'] as string;
    if (formId !== undefined && formId !== '') {
      CardStore.add(this.context, formId);
    }
    return formBindingData.createFormBindingData({ balance: '0', remaining: '0' });
  }

  onRemoveForm(formId: string): void {
    CardStore.remove(this.context, formId);
  }

  onUpdateForm(formId: string): void {
    // 定时更新兜底：数据以 App 内主动刷新为准，这里不重复计算
  }
}

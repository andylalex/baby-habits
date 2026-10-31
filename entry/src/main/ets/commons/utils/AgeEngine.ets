import { TaskItem } from '../models/Models';
import { AgeTemplates, AgeTemplate } from './AgeTemplate';

/**
 * 分龄建议引擎（方案「分龄激励引擎」+「数据驱动养育」的本地规则版）。
 * 后续可平滑替换为 HarmonyOS 7 端侧大模型生成（输入：年龄+打卡数据，输出：建议任务/评估）。
 *
 * 年龄档位与推荐任务统一由 AgeTemplate 提供（2-10 岁），本类只做评估与包装，
 * 避免「任务管理页模板」与「智能建议页推荐」两处规则不一致。
 */

/** 分龄建议（字段与 AgeTemplate 对齐，便于页面直接消费） */
export interface AgeAdvice {
  stageLabel: string;
  tasks: TaskItem[];
  principle: string;
}

export class AgeEngine {
  /**
   * 各年龄段推荐任务（对应 AgeTemplate 年龄模板包，低年龄从最简单的自理开始）。
   * age 超出 2-10 时由 AgeTemplates 夹到最近一档。
   */
  static adviceFor(age: number): AgeAdvice {
    const pack: AgeTemplate = AgeTemplates.packOf(age);
    return {
      stageLabel: pack.stageLabel,
      principle: pack.principle,
      tasks: AgeTemplates.tasksOf(age)
    };
  }

  /**
   * 周完成率评估（方案「数据驱动养育」）。
   * rate = 近7天打卡次数 / (启用任务数 × 7)
   */
  static evaluate(rate: number): string {
    if (rate >= 0.9) {
      return '习惯已经很稳定！可以尝试「奖励脱钩」：该任务不再给星星，改用口头表扬，让行为本身成为动力。';
    }
    if (rate >= 0.6) {
      return '保持得不错。建议把完成率最低的任务往前排（放在宝宝精力好的时段），星星定价不变。';
    }
    if (rate > 0) {
      return '完成率偏低，任务可能偏难或偏多。建议：任务减到 2-3 个，或把单任务星星值提高一点先建立信心。';
    }
    return '最近还没有打卡记录。从明天开始，先只设 1 个最简单的任务，完成后立刻庆祝。';
  }

  static rateLabel(rate: number): string {
    return `${Math.round(rate * 100)}%`;
  }
}

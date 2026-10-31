import { TaskItem } from '../models/Models';

/**
 * 时段推荐引擎（纯逻辑，不碰 UI 与数据库）。
 *
 * 设计：任务带「适合的时段」标签（可多个，逗号分隔存储），宝宝端按当前小时
 * 算出所处时段，从未完成任务里优先挑该时段合适的推荐。
 * 标签为「不限」的任务任何时段都能被推荐，用作兜底。
 */
export class TimeSlot {
  /** 任意时段（不限定） */
  static readonly ANY: string = '不限';

  /** 全部可选时段（家长端选择顺序 = 一天先后） */
  static readonly ALL: string[] = ['早晨', '上午', '中午', '下午', '傍晚', '晚上', '夜间'];

  /** 全部时段 + 「不限」（家长端 chips 用） */
  static allWithAny(): string[] {
    const list: string[] = [];
    for (let i = 0; i < TimeSlot.ALL.length; i++) {
      list.push(TimeSlot.ALL[i]);
    }
    list.push(TimeSlot.ANY);
    return list;
  }

  /** 时段对应的 emoji（宝宝端/家长端通用），格式：[时段, emoji] */
  private static readonly ICON_TABLE: string[][] = [
    ['早晨', '🌅'],
    ['上午', '☀️'],
    ['中午', '🍚'],
    ['下午', '🌈'],
    ['傍晚', '🌆'],
    ['晚上', '🌙'],
    ['夜间', '🌜'],
    ['不限', '⭐']
  ];

  /** 每个时段的推荐语（正向引导，不催促），格式：[时段, 文案] */
  private static readonly TIP_TABLE: string[][] = [
    ['早晨', '开启好习惯，从早上第一件事开始'],
    ['上午', '上午记性好，动动脑筋吧'],
    ['中午', '吃饭好好休息，攒足小能量'],
    ['下午', '下午活动一下，动动小身体'],
    ['傍晚', '收收心，把小物件都归位'],
    ['晚上', '睡前小习惯，明天更轻松'],
    ['夜间', '安静下来，做件温柔的小事'],
    ['不限', '任何时候做都很棒']
  ];

  /** 时段分隔符（存储用） */
  static readonly SEP: string = ',';

  /** 当前小时对应的时段 */
  static slotOfHour(hour: number): string {
    if (hour >= 5 && hour < 9) {
      return '早晨';
    }
    if (hour >= 9 && hour < 11) {
      return '上午';
    }
    if (hour >= 11 && hour < 14) {
      return '中午';
    }
    if (hour >= 14 && hour < 17) {
      return '下午';
    }
    if (hour >= 17 && hour < 19) {
      return '傍晚';
    }
    if (hour >= 19 && hour < 22) {
      return '晚上';
    }
    return '夜间';
  }

  /** 当前时段（按系统时间） */
  static currentSlot(): string {
    return TimeSlot.slotOfHour(new Date().getHours());
  }

  /** 时段 emoji */
  static iconOf(slot: string): string {
    for (let i = 0; i < TimeSlot.ICON_TABLE.length; i++) {
      if (TimeSlot.ICON_TABLE[i][0] === slot) {
        return TimeSlot.ICON_TABLE[i][1];
      }
    }
    return '⭐';
  }

  /** 时段推荐语 */
  static tipOf(slot: string): string {
    for (let i = 0; i < TimeSlot.TIP_TABLE.length; i++) {
      if (TimeSlot.TIP_TABLE[i][0] === slot) {
        return TimeSlot.TIP_TABLE[i][1];
      }
    }
    return '现在做这些刚刚好';
  }

  /** 解析任务的时间段标签数组（含「不限」时归一为单元素，避免推荐时重复计入） */
  static parse(timeSlots: string): string[] {
    if (timeSlots === '' || timeSlots === TimeSlot.ANY) {
      return [TimeSlot.ANY];
    }
    const list: string[] = timeSlots.split(TimeSlot.SEP);
    if (list.indexOf(TimeSlot.ANY) >= 0) {
      return [TimeSlot.ANY];
    }
    return list;
  }

  /** 把时段标签数组拼成存储串 */
  static join(slots: string[]): string {
    if (slots.length === 0) {
      return TimeSlot.ANY;
    }
    return slots.join(TimeSlot.SEP);
  }

  /** 任务是否适合该时段 */
  static fits(task: TaskItem, slot: string): boolean {
    const tags = TimeSlot.parse(task.timeSlots);
    return tags.indexOf(slot) >= 0 || tags.indexOf(TimeSlot.ANY) >= 0;
  }

  /**
   * 推荐任务列表（已排除今日已完成）。
   * 排序优先级：① 时段完全匹配 → ② 「不限」兜底 → ③ 其他未完成（保证有内容可推）。
   * @param tasks 全部任务（已按 sort 排序）
   * @param slot 当前时段
   * @param limit 最多推荐几条
   */
  static recommend(tasks: TaskItem[], slot: string, limit: number = 6): TaskItem[] {
    const pending: TaskItem[] = tasks.filter((t: TaskItem) => !t.doneToday);
    const exact: TaskItem[] = pending.filter((t: TaskItem) => {
      const tags = TimeSlot.parse(t.timeSlots);
      return tags.indexOf(slot) >= 0;
    });
    const anyTime: TaskItem[] = pending.filter((t: TaskItem) => {
      const tags = TimeSlot.parse(t.timeSlots);
      return tags.indexOf(TimeSlot.ANY) >= 0;
    });
    const others: TaskItem[] = pending.filter((t: TaskItem) => {
      const tags = TimeSlot.parse(t.timeSlots);
      return tags.indexOf(slot) < 0 && tags.indexOf(TimeSlot.ANY) < 0;
    });
    const merged: TaskItem[] = [];
    for (const t of exact) {
      merged.push(t);
    }
    for (const t of anyTime) {
      merged.push(t);
    }
    for (const t of others) {
      merged.push(t);
    }
    return merged.slice(0, limit);
  }
}

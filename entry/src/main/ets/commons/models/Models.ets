/**
 * 数据模型：任务 / 心愿 / 打卡 / 星星流水。
 * 与 drafts/harmonyos-arch.md §3.3 表结构一一对应。
 */

export const enum CheckinStatus {
  PENDING_REVIEW = 0, // 待家长确认
  DONE = 1            // 已完成
}

export class TaskItem {
  id: number = 0;
  title: string = '';
  /** 图形占位：'raw:xxx' 走插画，emoji 兜底 */
  icon: string = '';
  /** 卡片底色（HEX），贴纸卡风格 */
  cardColor: string = '#FFE9C7';
  starValue: number = 1;
  /** 是否需要家长审核确认（打卡先记为「待审核」，家长通过后才发星星） */
  needReview: boolean = false;
  /** 习惯分类：生活/自理/学习/礼貌/健康 */
  category: string = '生活';
  /** 适合的时段标签，逗号分隔（如 '早晨,上午'）；'不限' 表示任何时段都合适 */
  timeSlots: string = '不限';
  /** 今日是否已完成（查询时填充，不入库） */
  doneToday: boolean = false;

  constructor(id: number, title: string, icon: string, cardColor: string, starValue: number,
    needReview: boolean = false, category: string = '生活', timeSlots: string = '不限') {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.cardColor = cardColor;
    this.starValue = starValue;
    this.needReview = needReview;
    this.category = category;
    this.timeSlots = timeSlots;
  }
}

/**
 * 宝宝档案（profiles 表一行）。
 * name：宝宝名字（家长可改）；birthday：生日 YYYY-MM-DD，空串表示未设置。
 * age：由生日推导的周岁（生日未设置时为 0），用于挑分龄模板。
 */
export class KidProfile {
  id: number = 0;
  name: string = '';
  birthday: string = '';
  age: number = 0;

  constructor(id: number, name: string, birthday: string, age: number) {
    this.id = id;
    this.name = name;
    this.birthday = birthday;
    this.age = age;
  }
}

export class RewardItem {
  id: number = 0;
  title: string = '';
  icon: string = '';
  starCost: number = 5;
  /** 1=小心愿(5-10星) 2=中愿望(15-30星) 3=大愿望(40星+) */
  tier: number = 1;

  constructor(id: number, title: string, icon: string, starCost: number, tier: number) {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.starCost = starCost;
    this.tier = tier;
  }
}

/** 收集卡册里的一张已兑换卡 */
export class RedemptionCard {
  id: number = 0;
  title: string = '';
  icon: string = '';
  date: string = '';

  constructor(id: number, title: string, icon: string, date: string) {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.date = date;
  }
}

export const enum LedgerReason {
  TASK = 'task',
  BONUS = 'bonus',
  REDEEM = 'redeem'
}

/** 拍照打卡产出的一条相册记录（成长相册/今日照片条） */
export interface PhotoEntry {
  /** checkins 行 ID（删除照片用） */
  id: number;
  taskId: number;
  title: string;
  date: string;
  photoPath: string;
}

/** 星星流水账本条目（星星账本页展示） */
export interface LedgerEntry {
  /** stars_ledger 行 ID */
  id: number;
  /** 正=入账（打卡/奖励），负=支出（兑换） */
  delta: number;
  reason: string;
  /** 关联任务/心愿名（关联不上给默认文案） */
  title: string;
  createdAt: string;
}

/** 待家长审核的打卡记录（needReview=true 的任务打卡后进这里等确认） */
export interface PendingCheckin {
  /** checkins 行 ID */
  id: number;
  /** 任务 ID */
  taskId: number;
  /** 任务名 */
  title: string;
  /** 任务图标（emoji 或 raw: 路径） */
  icon: string;
  /** 该任务值多少星星 */
  starValue: number;
  /** 打卡日期（YYYY-MM-DD） */
  date: string;
  /** 打卡照片（可能为空串） */
  photoPath: string;
}

/** 里程碑（旅行路线站点）：kind = streak 连续天数 / stars 累计星星 / checkins 累计打卡 */
export class MilestoneItem {
  id: number = 0;
  title: string = '';
  icon: string = '🚩';
  kind: string = 'streak';
  target: number = 1;
  /** 家长许诺的实物奖励文案 */
  reward: string = '';
  /** 0 进行中 / 1 已达成待兑现 / 2 已兑现（纪念墙） */
  status: number = 0;
  achievedAt: string = '';
  confirmedAt: string = '';

  constructor(id: number, title: string, icon: string, kind: string, target: number, reward: string,
    status: number = 0, achievedAt: string = '', confirmedAt: string = '') {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.kind = kind;
    this.target = target;
    this.reward = reward;
    this.status = status;
    this.achievedAt = achievedAt;
    this.confirmedAt = confirmedAt;
  }
}

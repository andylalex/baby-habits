/**
 * 勋章定义与判定条件（成就墙）。
 * 每个勋章 = 唯一 ID + 展示信息 + 一个基于本地统计的纯函数判定。
 * 新增勋章只需往 BADGES 数组加一项，成就墙自动展示。
 */

/** 判定所需的本地统计快照（由 BadgeDao 一次性汇总） */
export interface BadgeStats {
  /** 累计完成打卡次数 */
  totalDone: number;
  /** 当前连续天数 */
  streak: number;
  /** 历史最长连续天数 */
  longest: number;
  /** 累计获得星星（只算正流水） */
  totalEarned: number;
  /** 当前余额 */
  balance: number;
  /** 累计打卡照片数 */
  photoCount: number;
  /** 累计心愿兑换次数 */
  redeemCount: number;
  /** 单日最多完成次数 */
  bestDayCount: number;
  /** 启用任务数 */
  activeTasks: number;
}

export interface BadgeDef {
  id: string;
  icon: string;
  title: string;
  /** 解锁条件说明（未解锁时灰态展示） */
  condition: string;
  hit: (s: BadgeStats) => boolean;
}

export const BADGES: BadgeDef[] = [
  {
    id: 'first_step', icon: '🌟', title: '第一次打卡', condition: '完成第一次任务打卡',
    hit: (s: BadgeStats) => s.totalDone >= 1
  },
  {
    id: 'streak3', icon: '🔥', title: '坚持 3 天', condition: '连续打卡 3 天',
    hit: (s: BadgeStats) => s.streak >= 3 || s.longest >= 3
  },
  {
    id: 'streak7', icon: '🏆', title: '坚持 7 天', condition: '连续打卡 7 天',
    hit: (s: BadgeStats) => s.longest >= 7
  },
  {
    id: 'streak30', icon: '💎', title: '坚持 30 天', condition: '连续打卡 30 天',
    hit: (s: BadgeStats) => s.longest >= 30
  },
  {
    id: 'full_day', icon: '🎉', title: '满分一天', condition: '一天完成全部任务',
    hit: (s: BadgeStats) => s.activeTasks > 0 && s.bestDayCount >= s.activeTasks
  },
  {
    id: 'star50', icon: '⭐', title: '集满 50 星', condition: '累计获得 50 颗星星',
    hit: (s: BadgeStats) => s.totalEarned >= 50
  },
  {
    id: 'star100', icon: '🌈', title: '集满 100 星', condition: '累计获得 100 颗星星',
    hit: (s: BadgeStats) => s.totalEarned >= 100
  },
  {
    id: 'photo5', icon: '📷', title: '小小摄影师', condition: '留下 5 张打卡照片',
    hit: (s: BadgeStats) => s.photoCount >= 5
  },
  {
    id: 'redeem1', icon: '🎁', title: '第一个心愿', condition: '兑换第一个心愿',
    hit: (s: BadgeStats) => s.redeemCount >= 1
  }
];

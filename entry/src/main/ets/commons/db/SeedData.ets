import { TaskItem, RewardItem, MilestoneItem } from '../models/Models';

/**
 * 初始数据。
 * TEMPLATES：预置任务模板库（UI 规范 8.7 的首批清单，emoji 为插画占位）。
 * DEMO_*：首次启动写入的演示数据（宝宝"小宝" + 今日任务 + 心愿三档），
 *         正式版家长可自由增删，演示数据仅为体验版闭环验证。
 */
export class SeedData {
  static readonly DEMO_KID_NAME: string = '小宝';
  /** 演示宝宝固定 ID（settings 中 active_kid 记录） */
  static readonly DEMO_KID_ID: number = 1;

  /** 习惯分类展示顺序 */
  static readonly CATEGORIES: string[] = ['生活', '自理', '学习', '礼貌', '健康'];

  static readonly TEMPLATES: TaskItem[] = [
    // 生活
    new TaskItem(0, '刷牙', 'raw:icons/task_brush.png', '#EAF4FF', 2, false, '生活', '早晨,晚上'),
    new TaskItem(0, '洗脸', 'raw:icons/task_face.png', '#EAF4FF', 1, false, '生活', '早晨,晚上'),
    new TaskItem(0, '洗手', 'raw:icons/task_hands.png', '#EAF4FF', 1, false, '生活', '不限'),
    new TaskItem(0, '按时睡觉', 'raw:icons/task_sleep.png', '#E8E6FF', 3, false, '生活', '晚上'),
    new TaskItem(0, '叠被子', 'raw:icons/task_bed.png', '#EAF4FF', 2, false, '生活', '早晨'),
    new TaskItem(0, '穿鞋子', 'raw:icons/task_shoes.png', '#FFE9C7', 1, false, '生活', '上午,下午'),
    new TaskItem(0, '洗澡', '🛁', '#EAF4FF', 2, false, '生活', '晚上'),
    new TaskItem(0, '梳头发', '💇', '#EAF4FF', 1, false, '生活', '早晨'),
    new TaskItem(0, '自己上厕所', '🚽', '#FFE9C7', 2, false, '生活', '不限'),
    new TaskItem(0, '收碗筷', '🍽️', '#EAF4FF', 1, false, '生活', '中午,傍晚'),
    new TaskItem(0, '垃圾分类', '♻️', '#E7F7E7', 1, false, '生活', '下午'),
    new TaskItem(0, '浇花', 'raw:icons/task_flower.png', '#E7F7E7', 1, false, '生活', '下午'),
    // 自理
    new TaskItem(0, '自己吃饭', 'raw:icons/task_eat.png', '#FFE9C7', 1, false, '自理', '中午'),
    new TaskItem(0, '整理玩具', 'raw:icons/task_toys.png', '#FFE3EA', 2, false, '自理', '傍晚'),
    new TaskItem(0, '收拾画笔', 'raw:icons/task_crayon.png', '#FFE9C7', 1, false, '自理', '傍晚'),
    new TaskItem(0, '整理书包', '🎒', '#EAF4FF', 2, false, '自理', '晚上'),
    new TaskItem(0, '自己穿衣', '👕', '#EAF4FF', 2, false, '自理', '早晨'),
    new TaskItem(0, '系鞋带', '👟', '#FFE9C7', 2, false, '自理', '上午'),
    new TaskItem(0, '收衣服', '👚', '#EAF4FF', 1, false, '自理', '傍晚'),
    new TaskItem(0, '摆碗筷', '🥢', '#FFE9C7', 1, false, '自理', '中午'),
    new TaskItem(0, '整理书桌', '🗂️', '#EAF4FF', 2, false, '自理', '傍晚'),
    new TaskItem(0, '收拾房间', '🧹', '#EAF4FF', 2, false, '自理', '傍晚'),
    new TaskItem(0, '自己洗碗', '🥣', '#EAF4FF', 2, false, '自理', '晚上'),
    // 学习
    new TaskItem(0, '阅读绘本', 'raw:icons/task_reading.png', '#FFF2D0', 3, false, '学习', '晚上'),
    new TaskItem(0, '画画', '🎨', '#E8E6FF', 2, false, '学习', '下午'),
    new TaskItem(0, '认字', '🔤', '#FFF2D0', 2, false, '学习', '上午'),
    new TaskItem(0, '背古诗', '🐦', '#FFF2D0', 3, false, '学习', '上午'),
    new TaskItem(0, '数数', '🔢', '#FFF2D0', 2, false, '学习', '上午'),
    new TaskItem(0, '英语儿歌', '🎵', '#FFF2D0', 2, false, '学习', '上午'),
    new TaskItem(0, '拼图', '🧩', '#E8E6FF', 2, false, '学习', '下午'),
    new TaskItem(0, '搭积木', '🧱', '#FFF2D0', 2, false, '学习', '下午'),
    new TaskItem(0, '写作业', '✏️', '#FFF2D0', 3, false, '学习', '下午'),
    new TaskItem(0, '练字', '🖌️', '#FFF2D0', 2, false, '学习', '下午'),
    new TaskItem(0, '记日记', '📓', '#E8E6FF', 3, false, '学习', '晚上'),
    new TaskItem(0, '课外阅读', '📚', '#FFF2D0', 3, false, '学习', '晚上'),
    new TaskItem(0, '背单词', '🔠', '#FFF2D0', 2, false, '学习', '上午'),
    new TaskItem(0, '预习', '🔍', '#E8E6FF', 2, false, '学习', '晚上'),
    // 礼貌
    new TaskItem(0, '说谢谢', 'raw:icons/task_thanks.png', '#FFE3EA', 1, false, '礼貌', '不限'),
    new TaskItem(0, '主动问好', '👋', '#FFE3EA', 1, false, '礼貌', '早晨'),
    new TaskItem(0, '分享玩具', '🤝', '#FFE3EA', 2, false, '礼貌', '下午'),
    new TaskItem(0, '说对不起', '🙇', '#FFE3EA', 1, false, '礼貌', '不限'),
    new TaskItem(0, '帮长辈', '👵', '#FFE3EA', 1, false, '礼貌', '傍晚'),
    new TaskItem(0, '排队等候', '🚶', '#FFE3EA', 1, false, '礼貌', '上午'),
    new TaskItem(0, '不打断别人', '🤫', '#FFE3EA', 1, false, '礼貌', '不限'),
    // 健康
    new TaskItem(0, '运动一下', '⚽', '#E7F7E7', 2, false, '健康', '下午'),
    new TaskItem(0, '多喝水', '💧', '#E7F7E7', 1, false, '健康', '不限'),
    new TaskItem(0, '不挑食', '🥬', '#E7F7E7', 2, false, '健康', '中午'),
    new TaskItem(0, '早睡早起', '🌞', '#E7F7E7', 2, false, '健康', '早晨'),
    new TaskItem(0, '多吃蔬菜', '🥦', '#E7F7E7', 1, false, '健康', '中午'),
    new TaskItem(0, '护眼休息', '👀', '#E7F7E7', 1, false, '健康', '下午'),
    new TaskItem(0, '自己喝水', '🥤', '#E7F7E7', 1, false, '健康', '不限'),
    new TaskItem(0, '运动30分钟', '🏃', '#E7F7E7', 3, false, '健康', '下午'),
    new TaskItem(0, '户外活动', '🌳', '#E7F7E7', 2, false, '健康', '下午'),
    new TaskItem(0, '早睡不熬夜', '🌜', '#E7F7E7', 2, false, '健康', '夜间')
  ];

  /** 演示：小宝的今日任务（按类型覆盖五类，排序即时间轴：早 → 晚） */
  static readonly DEMO_TASKS: TaskItem[] = [
    new TaskItem(0, '自己穿衣', '👕', '#EAF4FF', 2, false, '自理', '早晨'),
    new TaskItem(0, '刷牙', 'raw:icons/task_brush.png', '#EAF4FF', 2, false, '生活', '早晨,晚上'),
    new TaskItem(0, '多喝水', '💧', '#E7F7E7', 1, false, '健康', '不限'),
    new TaskItem(0, '自己吃饭', 'raw:icons/task_eat.png', '#FFE9C7', 1, false, '自理', '中午'),
    new TaskItem(0, '说谢谢', 'raw:icons/task_thanks.png', '#FFE3EA', 1, false, '礼貌', '不限'),
    new TaskItem(0, '阅读绘本', 'raw:icons/task_reading.png', '#FFF2D0', 3, false, '学习', '晚上'),
    new TaskItem(0, '画画', '🎨', '#E8E6FF', 2, false, '学习', '下午'),
    new TaskItem(0, '运动一下', '⚽', '#E7F7E7', 2, false, '健康', '下午'),
    new TaskItem(0, '整理玩具', 'raw:icons/task_toys.png', '#FFE3EA', 2, false, '自理', '傍晚'),
    new TaskItem(0, '按时睡觉', 'raw:icons/task_sleep.png', '#E8E6FF', 3, false, '生活', '晚上')
  ];

  /** 演示：心愿商店三档定价 */
  static readonly DEMO_REWARDS: RewardItem[] = [
    new RewardItem(0, '贴纸一张', 'raw:icons/reward_sticker.png', 5, 1),
    new RewardItem(0, '看一集动画', 'raw:icons/reward_tv.png', 10, 1),
    new RewardItem(0, '周末公园游', 'raw:icons/reward_park.png', 20, 2),
    new RewardItem(0, '乐高一盒', 'raw:icons/reward_lego.png', 60, 3)
  ];

  /** 演示：里程碑旅行路线三站（实物奖励为家长许诺文案） */
  static readonly DEMO_MILESTONES: MilestoneItem[] = [
    new MilestoneItem(0, '坚持打卡 3 天', '🔥', 'streak', 3, '奖励贴纸一套'),
    new MilestoneItem(0, '集满 30 颗星', '⭐', 'stars', 30, '周末去公园玩'),
    new MilestoneItem(0, '坚持打卡 7 天', '🏆', 'streak', 7, '挑选一份神秘礼物')
  ];
}

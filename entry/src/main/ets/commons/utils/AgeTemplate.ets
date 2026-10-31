import { TaskItem } from '../models/Models';
import { SeedData } from '../db/SeedData';

/**
 * 分龄模板包（2-10 岁）。
 *
 * 设计：家长端任务管理页「先选年龄模板 → 再在模板上自定义」。
 * 每个年龄包给出该阶段的养育原则 + 一份推荐任务清单（标题 + 星星定价）。
 * 标题全部来自 SeedData.TEMPLATES（图标/分类/时段复用模板库，避免两处维护）。
 */

/** 模板包中的一条任务：只定义标题与星星定价，其余字段从模板库解析 */
export class AgeTemplateItem {
  title: string = '';
  stars: number = 1;

  constructor(title: string, stars: number) {
    this.title = title;
    this.stars = stars;
  }
}

/** 一个年龄段的完整模板包 */
export class AgeTemplate {
  /** 宝宝年龄（2-10） */
  age: number = 4;
  /** 阶段名，如「4 岁 · 生活习惯成型」 */
  stageLabel: string = '';
  /** 该阶段的养育原则（给家长看的一句话） */
  principle: string = '';
  /** 推荐任务清单（按一天时间轴排序） */
  items: AgeTemplateItem[] = [];

  constructor(age: number, stageLabel: string, principle: string, items: AgeTemplateItem[]) {
    this.age = age;
    this.stageLabel = stageLabel;
    this.principle = principle;
    this.items = items;
  }
}

export class AgeTemplates {
  /** 可选年龄（2-10 岁，共 9 档） */
  static readonly AGES: number[] = [2, 3, 4, 5, 6, 7, 8, 9, 10];

  /** 各年龄段模板包 */
  static readonly PACKS: AgeTemplate[] = [
    new AgeTemplate(2, '2 岁 · 迈出第一步',
      '任务要少而简单，一次只练一件事，做到就立刻夸',
      [
        new AgeTemplateItem('自己吃饭', 1),
        new AgeTemplateItem('洗手', 1),
        new AgeTemplateItem('说谢谢', 1),
        new AgeTemplateItem('穿鞋子', 1),
        new AgeTemplateItem('自己上厕所', 1)
      ]),
    new AgeTemplate(3, '3 岁 · 建立基本自理',
      '加入早晚固定流程（刷牙洗脸），重复比数量更重要',
      [
        new AgeTemplateItem('刷牙', 1),
        new AgeTemplateItem('洗脸', 1),
        new AgeTemplateItem('整理玩具', 1),
        new AgeTemplateItem('自己吃饭', 1),
        new AgeTemplateItem('说谢谢', 1),
        new AgeTemplateItem('早睡早起', 1)
      ]),
    new AgeTemplate(4, '4 岁 · 生活习惯成型',
      '可给到 4-6 个任务，开始练习自己整理和按时作息',
      [
        new AgeTemplateItem('刷牙', 2),
        new AgeTemplateItem('洗脸', 1),
        new AgeTemplateItem('叠被子', 1),
        new AgeTemplateItem('整理玩具', 2),
        new AgeTemplateItem('主动问好', 1),
        new AgeTemplateItem('按时睡觉', 2)
      ]),
    new AgeTemplate(5, '5 岁 · 加入学习准备',
      '加入阅读与识字类任务，星星定价可提高一档',
      [
        new AgeTemplateItem('阅读绘本', 2),
        new AgeTemplateItem('认字', 2),
        new AgeTemplateItem('数数', 1),
        new AgeTemplateItem('背古诗', 2),
        new AgeTemplateItem('叠被子', 2),
        new AgeTemplateItem('整理书包', 1),
        new AgeTemplateItem('按时睡觉', 2)
      ]),
    new AgeTemplate(6, '6 岁 · 幼小衔接',
      '任务数可加到 6-7 个，学习类任务开始固定时段',
      [
        new AgeTemplateItem('阅读绘本', 2),
        new AgeTemplateItem('认字', 2),
        new AgeTemplateItem('背古诗', 2),
        new AgeTemplateItem('练字', 2),
        new AgeTemplateItem('拼图', 2),
        new AgeTemplateItem('整理书包', 2),
        new AgeTemplateItem('运动一下', 2),
        new AgeTemplateItem('按时睡觉', 3)
      ]),
    new AgeTemplate(7, '7 岁 · 入学第一年',
      '学习任务与自理任务并行，作业类任务可开启家长确认',
      [
        new AgeTemplateItem('写作业', 3),
        new AgeTemplateItem('阅读绘本', 3),
        new AgeTemplateItem('练字', 2),
        new AgeTemplateItem('整理书包', 2),
        new AgeTemplateItem('收衣服', 1),
        new AgeTemplateItem('运动一下', 2),
        new AgeTemplateItem('早睡早起', 2)
      ]),
    new AgeTemplate(8, '8 岁 · 自我管理起步',
      '让宝宝自己安排书桌与作息，家长只做检查',
      [
        new AgeTemplateItem('写作业', 3),
        new AgeTemplateItem('课外阅读', 3),
        new AgeTemplateItem('背单词', 2),
        new AgeTemplateItem('记日记', 2),
        new AgeTemplateItem('整理书桌', 2),
        new AgeTemplateItem('运动30分钟', 3),
        new AgeTemplateItem('早睡不熬夜', 2)
      ]),
    new AgeTemplate(9, '9 岁 · 计划与复盘',
      '引入预习与记录，任务完成后聊一句感受比催更有效',
      [
        new AgeTemplateItem('写作业', 3),
        new AgeTemplateItem('预习', 2),
        new AgeTemplateItem('课外阅读', 3),
        new AgeTemplateItem('记日记', 2),
        new AgeTemplateItem('整理书桌', 2),
        new AgeTemplateItem('运动30分钟', 3),
        new AgeTemplateItem('收拾房间', 2),
        new AgeTemplateItem('垃圾分类', 1)
      ]),
    new AgeTemplate(10, '10 岁 · 自主负责',
      '任务基本由宝宝自己认领，家长角色转为陪伴与鼓励',
      [
        new AgeTemplateItem('写作业', 3),
        new AgeTemplateItem('预习', 2),
        new AgeTemplateItem('课外阅读', 3),
        new AgeTemplateItem('记日记', 3),
        new AgeTemplateItem('整理书桌', 2),
        new AgeTemplateItem('收拾房间', 2),
        new AgeTemplateItem('自己洗碗', 2),
        new AgeTemplateItem('运动30分钟', 3),
        new AgeTemplateItem('户外活动', 2)
      ])
  ];

  /** 取某年龄的模板包；越界时夹到最近一档 */
  static packOf(age: number): AgeTemplate {
    let target = age;
    if (target < AgeTemplates.AGES[0]) {
      target = AgeTemplates.AGES[0];
    }
    if (target > AgeTemplates.AGES[AgeTemplates.AGES.length - 1]) {
      target = AgeTemplates.AGES[AgeTemplates.AGES.length - 1];
    }
    for (const p of AgeTemplates.PACKS) {
      if (p.age === target) {
        return p;
      }
    }
    return AgeTemplates.PACKS[0];
  }

  /** 从模板库按标题取原始模板（取不到返回 null） */
  static baseOf(title: string): TaskItem | null {
    for (const t of SeedData.TEMPLATES) {
      if (t.title === title) {
        return t;
      }
    }
    return null;
  }

  /**
   * 把模板包里的一条任务解析成完整的 TaskItem：
   * 图标/分类/时段/配色沿用模板库，星星用模板包定价。
   */
  static resolve(item: AgeTemplateItem): TaskItem | null {
    const base = AgeTemplates.baseOf(item.title);
    if (base === null) {
      return null;
    }
    return new TaskItem(0, base.title, base.icon, base.cardColor, item.stars,
      false, base.category, base.timeSlots);
  }

  /** 某年龄模板包解析后的完整任务清单（跳过模板库中不存在的条目） */
  static tasksOf(age: number): TaskItem[] {
    const pack = AgeTemplates.packOf(age);
    const list: TaskItem[] = [];
    for (const item of pack.items) {
      const t = AgeTemplates.resolve(item);
      if (t !== null) {
        list.push(t);
      }
    }
    return list;
  }
}

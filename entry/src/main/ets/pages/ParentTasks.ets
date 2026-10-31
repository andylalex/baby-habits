import { TaskItem, PendingCheckin } from '../commons/models/Models';
import { UIContext, PromptAction } from '@kit.ArkUI';
import { HabitIcon } from '../commons/components/HabitIcon';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { HabitRow } from '../commons/components/HabitRow';
import { CardSurface, SectionTitle, EmptyHint } from '../commons/components/Primitives';
import { ParentScaffold } from '../commons/components/ParentScaffold';
import { TaskDao, CheckinDao, ResetDao, SettingsDao, ProfileDao } from '../commons/db/Dao';
import { DatabaseHelper } from '../commons/db/DatabaseHelper';
import { SeedData } from '../commons/db/SeedData';
import { TimeSlot } from '../commons/utils/TimeSlot';
import { AgeTemplates, AgeTemplate } from '../commons/utils/AgeTemplate';
import { AgeUtil } from '../commons/utils/AgeUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Radius, Space, Type, MIN_TOUCH } from '../commons/theme/Theme';

/** 任务列表行：分类标题行 / 任务行（同一 List 内拖拽改分类） */
interface TaskRowItem {
  isHeader: boolean;
  category: string;
  task: TaskItem | null;
}

/** 内置插画图标（复用模板，保证与宝宝端视觉一致） */
function buildArtIcons(): string[] {
  const list: string[] = [];
  for (const tpl of SeedData.TEMPLATES) {
    if (list.indexOf(tpl.icon) < 0) {
      list.push(tpl.icon);
    }
  }
  return list;
}

/** 兜底 emoji 图标（自定义任务无插画时使用） */
const EMOJI_ICONS: string[] = [
  '🪥', '🧼', '🛁', '🚿', '🧴', '🍚', '🥛', '🥦', '🍎',
  '📖', '✏️', '🎨', '🖍️', '🧸', '🧹', '🎒',
  '🌙', '⏰', '👟', '👕', '🛏️', '🧦',
  '🌷', '🪴', '🙏', '🤝', '🗣️', '🏃', '💧'
];

/**
 * 图标选择池：插画在前、emoji 在后，横向滑动挑选。
 * 去重是必需的——ForEach 的 key 用图标本身，重复图标会产生重复 key。
 */
function buildPickerIcons(): string[] {
  const merged: string[] = buildArtIcons().concat(EMOJI_ICONS);
  const unique: string[] = [];
  for (const icon of merged) {
    if (unique.indexOf(icon) < 0) {
      unique.push(icon);
    }
  }
  return unique;
}

/** 图标选择池 */
const PICKER_ICONS: string[] = buildPickerIcons();

/** 记住上次选择的年龄模板（settings 键） */
const AGE_SETTING_KEY: string = 'task_template_age';

/**
 * 家长端 · 任务管理：
 * 两步流程 —— ① 选择年龄模板（2-10 岁）② 在模板基础上自定义（改名/改星/改分类/改时段/换图标）。
 * 模板清单可直接「加入」当前任务列表；已存在的任务会标「已添加」。
 * 另有审核开关 + 停用 + 重置今日 + 长按拖拽任务到目标分类标题即可改分类。
 */
@Entry
@Component
struct ParentTasks {
  @State tasks: TaskItem[] = [];
  @State rows: TaskRowItem[] = [];
  @State newTitle: string = '';
  @State newIcon: string = PICKER_ICONS[0];
  @State newStars: number = 1;
  @State newNeedReview: boolean = false;
  @State newCategory: string = SeedData.CATEGORIES[0];
  /** 新建任务选择的适合时段（多选） */
  @State newSlots: string[] = [TimeSlot.ANY];
  /** 正在拖拽的任务 ID（-1 表示无） */
  @State dragTaskId: number = -1;
  /** 拖拽悬停的目标分类 */
  @State dragOverCat: string = '';
  /** 待家长审核的打卡记录（needReview 任务打卡后在这里确认） */
  @State pendingList: PendingCheckin[] = [];
  /** 当前选中的年龄（2-10） */
  @State selectedAge: number = 4;
  /** 当前年龄模板解析后的任务清单（切换年龄时重建，供 ForEach 稳定 diff） */
  @State packList: TaskItem[] = [];
  /** 自定义表单当前基于的模板任务名（空串 = 从零自定义） */
  @State baseTemplateTitle: string = '';
  /** 基于模板时继承的卡片底色 */
  @State baseCardColor: string = '#EAF4FF';
  /**
   * UIContext / PromptAction：在构造阶段取一次并缓存。
   * 原因：getUIContext() 必须在同步上下文调用，而 toast 常在 await 之后触发；
   * 缓存下来的实例在异步回调里依然有效，不会丢 UI 上下文。
   */
  private uiContext: UIContext = this.getUIContext();
  private prompt: PromptAction = this.uiContext.getPromptAction();

  aboutToAppear(): void {
    this.reload();
    this.loadAge();
  }

  async reload(): Promise<void> {
    this.tasks = await TaskDao.listActive(SeedData.DEMO_KID_ID);
    this.rebuildRows();
    this.pendingList = await CheckinDao.pendingReviews(SeedData.DEMO_KID_ID, DatabaseHelper.today());
    // 重建模板清单：让「已添加」标记跟着任务列表变化刷新
    this.refreshPack();
  }

  /**
   * 读取所选年龄模板。
   * 优先级：手动选过的档位（settings）> 生日算出的年龄 > 默认档。
   * 这样家长改过生日后，若没手动选过档位，页面会自动跟到新年龄档。
   */
  async loadAge(): Promise<void> {
    let picked = false;
    try {
      const v = await SettingsDao.get(AGE_SETTING_KEY);
      if (v !== null) {
        const n = Number(v);
        if (n >= 2 && n <= 10) {
          this.selectedAge = n;
          picked = true;
        }
      }
    } catch (err) {
      hilog.info(0x0001, 'ParentTasks', 'load age failed: %{public}s', String(err));
    }
    if (!picked) {
      // 没手动选过 → 用生日算出的年龄档（生日由家长在「宝宝档案」里填）
      const profile = await ProfileDao.get(SeedData.DEMO_KID_ID);
      if (profile !== null) {
        this.selectedAge = AgeUtil.templateAge(profile.age);
      }
    }
    this.refreshPack();
  }

  /** 切换年龄模板并记住 */
  selectAge(age: number): void {
    this.selectedAge = age;
    this.refreshPack();
    this.saveAge(age);
  }

  /** 按当前年龄重建模板任务清单 */
  refreshPack(): void {
    this.packList = AgeTemplates.tasksOf(this.selectedAge);
  }

  /** 持久化所选年龄（失败不阻断交互） */
  async saveAge(age: number): Promise<void> {
    try {
      await SettingsDao.set(AGE_SETTING_KEY, `${age}`);
    } catch (err) {
      hilog.info(0x0001, 'ParentTasks', 'save age failed: %{public}s', String(err));
    }
  }

  /**
   * 轻提示。
   * 用缓存的 PromptAction 而不是全局 promptAction：
   * 全局版在异步回调（await 之后）里会丢 UI 上下文导致 Toast 弹不出来。
   */
  toast(msg: string): void {
    this.prompt.showToast({ message: msg });
  }

  /** 审核通过：状态改为已完成 + 补记星星 */
  async approvePending(item: PendingCheckin): Promise<void> {
    try {
      await CheckinDao.approveReview(item.id, SeedData.DEMO_KID_ID, item.starValue);
      await this.reload();
    } catch (err) {
      hilog.error(0x0001, 'ParentTasks', 'approve failed: %{public}s', String(err));
    }
  }
  /** 审核驳回：删除该条打卡记录 */
  async rejectPending(item: PendingCheckin): Promise<void> {
    try {
      await CheckinDao.rejectReview(item.id);
      await this.reload();
    } catch (err) {
      hilog.error(0x0001, 'ParentTasks', 'reject failed: %{public}s', String(err));
    }
  }

  /** 直接写库（不刷新，供批量套用） */
  async insertTask(t: TaskItem, sort: number): Promise<void> {
    await TaskDao.insert(SeedData.DEMO_KID_ID, t, sort);
  }

  async addTask(title: string, icon: string, stars: number, needReview: boolean,
    category: string, timeSlots: string = TimeSlot.ANY, cardColor: string = '#EAF4FF'): Promise<void> {
    const t = new TaskItem(0, title, icon, cardColor, stars, needReview, category, timeSlots);
    await this.insertTask(t, this.tasks.length);
    await this.reload();
  }

  /** 标题是否已存在于启用中的任务 */
  hasTitle(title: string): boolean {
    return this.findByTitle(title) !== null;
  }

  /** 按标题找启用中的任务（找不到返回 null） */
  findByTitle(title: string): TaskItem | null {
    for (const t of this.tasks) {
      if (t.title === title) {
        return t;
      }
    }
    return null;
  }

  /** 按标题找「除指定任务之外」的其他任务（改名撞名检测用） */
  findOtherByTitle(title: string, exceptId: number): TaskItem | null {
    for (const t of this.tasks) {
      if (t.title === title && t.id !== exceptId) {
        return t;
      }
    }
    return null;
  }

  /** 从模板直接加入任务列表（已存在则跳过） */
  async addFromTemplate(t: TaskItem): Promise<void> {
    if (this.hasTitle(t.title)) {
      this.toast(`「${t.title}」已经在任务列表里了`);
      return;
    }
    await this.addTask(t.title, t.icon, t.starValue, false, t.category, t.timeSlots, t.cardColor);
    this.toast(`已加入「${t.title}」`);
  }

  /** 一键套用当前年龄模板（跳过已存在的任务） */
  async applyPack(): Promise<void> {
    const pack = this.currentPack();
    let added = 0;
    let sort = this.tasks.length;
    for (const item of pack.items) {
      const t = AgeTemplates.resolve(item);
      if (t === null || this.hasTitle(t.title)) {
        continue;
      }
      await this.insertTask(t, sort++);
      added++;
    }
    await this.reload();
    this.toast(added > 0 ? `已套用 ${added} 个任务` : '该年龄模板的任务都已存在');
  }

  /**
   * 把某个模板任务作为自定义的起点（预填表单字段）。
   * 若该任务已存在于列表中，则预填「现有任务」的实际配置（家长改的是现存任务，不是模板）。
   */
  useAsBase(t: TaskItem): void {
    const existing = this.findByTitle(t.title);
    const src = existing !== null ? existing : t;
    this.baseTemplateTitle = t.title;
    this.baseCardColor = src.cardColor;
    this.newTitle = src.title;
    this.newIcon = src.icon;
    this.newStars = src.starValue;
    this.newNeedReview = src.needReview;
    this.newCategory = src.category;
    this.newSlots = TimeSlot.parse(src.timeSlots);
  }

  /** 清除模板起点，回到从零自定义 */
  clearBase(): void {
    this.baseTemplateTitle = '';
    this.baseCardColor = '#EAF4FF';
    this.newTitle = '';
    this.newIcon = PICKER_ICONS[0];
    this.newStars = 1;
    this.newNeedReview = false;
    this.newCategory = SeedData.CATEGORIES[0];
    this.newSlots = [TimeSlot.ANY];
  }

  /** 当前年龄的模板包 */
  currentPack(): AgeTemplate {
    return AgeTemplates.packOf(this.selectedAge);
  }

  /** 当前年龄模板解析后的任务清单 */
  packTasks(): TaskItem[] {
    return this.packList;
  }

  /** 切换新建任务的时段选择（多选） */
  toggleNewSlot(slot: string): void {
    if (slot === TimeSlot.ANY) {
      this.newSlots = [TimeSlot.ANY];
      return;
    }
    // 选了具体时段就取消「不限」
    const next: string[] = this.newSlots.filter((s: string) => s !== TimeSlot.ANY);
    const idx = next.indexOf(slot);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(slot);
    }
    this.newSlots = next.length === 0 ? [TimeSlot.ANY] : next;
  }

  /** 切换已有任务的时段（点选/取消） */
  async toggleTaskSlot(task: TaskItem, slot: string): Promise<void> {
    const next: string[] = TimeSlot.parse(task.timeSlots).filter((s: string) => s !== TimeSlot.ANY);
    const idx = next.indexOf(slot);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(slot);
    }
    const value = next.length === 0 ? TimeSlot.ANY : TimeSlot.join(next);
    await TaskDao.setTimeSlots(task.id, value);
    task.timeSlots = value;
  }

  /** 任务行的时段摘要文案 */
  slotsLabel(timeSlots: string): string {
    const tags = TimeSlot.parse(timeSlots);
    if (tags.length === 1 && tags[0] === TimeSlot.ANY) {
      return '不限时段';
    }
    return tags.map((s: string) => `${TimeSlot.iconOf(s)} ${s}`).join(' ');
  }

  /** 有任务的分类，按全局顺序 */
  usedCategories(): string[] {
    const cats: string[] = [];
    for (const c of SeedData.CATEGORIES) {
      if (this.tasks.some((t: TaskItem) => t.category === c)) {
        cats.push(c);
      }
    }
    for (const t of this.tasks) {
      if (cats.indexOf(t.category) < 0) {
        cats.push(t.category);
      }
    }
    return cats;
  }

  tasksOf(category: string): TaskItem[] {
    return this.tasks.filter((t: TaskItem) => t.category === category);
  }

  /** 把任务按分类展开成「标题行 + 任务行」的扁平序列 */
  rebuildRows(): void {
    const list: TaskRowItem[] = [];
    for (const cat of this.usedCategories()) {
      list.push({ isHeader: true, category: cat, task: null } as TaskRowItem);
      const items = this.tasksOf(cat);
      for (const t of items) {
        list.push({ isHeader: false, category: cat, task: t } as TaskRowItem);
      }
    }
    this.rows = list;
  }

  /**
   * 任务行在 List 中的起始索引（前导固定 ListItem 数量）。
   * List 的拖拽回调给的是整个 List 的下标，而任务行数组 rows 是从第 N 个 ListItem 之后开始，
   * 这里做一次换算，拖拽改分类才不会错位。
   */
  rowStartIndex(): number {
    let n = 3; // ① 年龄模板区 / ② 自定义表单 / ③ 当前任务标题
    if (this.pendingList.length > 0) {
      n++;
    }
    return n;
  }

  /**
   * List 下标 → 任务行。
   * 先按 rowStartIndex 换算；若换算结果不是任务行（说明该 ListItem 不是可拖的任务），
   * 再退回按原始下标取，两种口径都能命中，避免拖拽错位。
   */
  rowAt(listIndex: number): TaskRowItem | null {
    const offset = listIndex - this.rowStartIndex();
    if (offset >= 0 && offset < this.rows.length) {
      const row = this.rows[offset];
      if (row !== undefined && !row.isHeader && row.task !== null) {
        return row;
      }
    }
    if (listIndex >= 0 && listIndex < this.rows.length) {
      const row = this.rows[listIndex];
      if (row !== undefined && !row.isHeader && row.task !== null) {
        return row;
      }
    }
    return null;
  }

  /** 落点索引 → 所属分类（落在首个标题之前返回空串，表示不改分类） */
  categoryAt(listIndex: number): string {
    let idx = listIndex - this.rowStartIndex();
    if (idx < 0 || idx > this.rows.length) {
      idx = listIndex;
    }
    for (let i = idx - 1; i >= 0; i--) {
      if (this.rows[i].isHeader) {
        return this.rows[i].category;
      }
    }
    return '';
  }

  resetDrag(): void {
    this.dragTaskId = -1;
    this.dragOverCat = '';
  }

  async moveTo(taskId: number, category: string): Promise<void> {
    await TaskDao.setCategory(taskId, category);
    await this.reload();
  }

  confirmReset(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '重置今日打卡',
      message: '会清除今天的全部打卡记录和今日获得的星星，宝宝端任务恢复未完成。确定重置？',
      buttons: [
        { text: '取消', color: '#6B4A2F' },
        { text: '重置', color: '#FF5A5A' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        ResetDao.resetToday(SeedData.DEMO_KID_ID, DatabaseHelper.today()).then(() => {
          this.reload();
        });
      }
    });
  }

  @Builder
  IconChip(icon: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (icon.startsWith('raw:')) {
        HabitIcon({ icon: icon, iconSize: 32, radius: 8 })
      } else {
        Text(icon)
          .fontSize(26)
      }
    }
    .width(48)
    .height(48)
    .borderRadius(Radius.MD)
    .backgroundColor(this.newIcon === icon ? $r('app.color.soft_yellow') : Color.White)
    .border({
      width: 2,
      color: this.newIcon === icon ? $r('app.color.brand_orange') : $r('app.color.hairline')
    })
    .onClick(() => {
      this.newIcon = icon;
    })
  }

  /** 图标选择器：横向滑动挑选（插画 + emoji） */
  @Builder
  IconPicker() {
    Scroll() {
      Row({ space: Space.SM }) {
        ForEach(PICKER_ICONS, (icon: string) => {
          this.IconChip(icon);
        }, (icon: string) => icon)
      }
      .padding(Space.XS)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  CategoryChips() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(SeedData.CATEGORIES, (cat: string) => {
        Text(cat)
          .fontSize(Type.CAPTION)
          .fontColor(this.newCategory === cat ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.newCategory === cat ? $r('app.color.brand_orange') : Color.White)
          .borderRadius(Radius.PILL)
          .border({
            width: 2,
            color: this.newCategory === cat ? $r('app.color.brand_orange') : $r('app.color.hairline')
          })
          .margin({ right: Space.SM, bottom: Space.SM })
          .onClick(() => {
            this.newCategory = cat;
          })
      }, (cat: string) => cat)
    }
    .width('100%')
  }

  /** 全部任务库（不分年龄的横向模板条，兜底补齐模板包外的任务） */
  @Builder
  LibraryBar() {
    Scroll() {
      Row({ space: Space.SM }) {
        ForEach(SeedData.TEMPLATES, (tpl: TaskItem) => {
          Row({ space: 6 }) {
            HabitIcon({ icon: tpl.icon, iconSize: 28, radius: 8 })
            Text(tpl.title)
              .fontSize(Type.BODY)
              .fontColor($r('app.color.cocoa_text'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.soft_yellow'))
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.addFromTemplate(tpl);
          })
        }, (tpl: TaskItem) => tpl.title)
      }
      .padding({ left: Space.XS, right: Space.XS })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  /** 年龄选择器：2-10 岁，换行排列全部可见 */
  @Builder
  AgeChips() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(AgeTemplates.AGES, (age: number) => {
        Text(`${age} 岁`)
          .fontSize(Type.CAPTION)
          .fontWeight(this.selectedAge === age ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedAge === age ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.selectedAge === age ? $r('app.color.brand_orange') : Color.White)
          .borderRadius(Radius.PILL)
          .border({
            width: 2,
            color: this.selectedAge === age ? $r('app.color.brand_orange') : $r('app.color.hairline')
          })
          .margin({ right: Space.SM, bottom: Space.SM })
          .onClick(() => {
            this.selectAge(age);
          })
      }, (age: number) => `age${age}`)
    }
    .width('100%')
  }

  /** 模板包里的单个任务行：右侧「改」= 在它基础上自定义，「加入」= 直接加入任务列表 */
  @Builder
  PackTaskRow(t: TaskItem) {
    Row({ space: Space.SM }) {
      HabitIcon({ icon: t.icon, iconSize: 36, radius: 10 })
      Column({ space: 2 }) {
        Text(t.title)
          .fontSize(Type.BODY)
          .fontColor($r('app.color.cocoa_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`⭐${t.starValue} · ${t.category} · ${this.slotsLabel(t.timeSlots)}`)
          .fontSize(Type.MICRO + 1)
          .fontColor($r('app.color.mist_gray'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .alignItems(HorizontalAlign.Start)
      // 右侧竖排小操作：宽度小，窄屏也不会把标题挤没
      Column({ space: 6 }) {
        Text('改')
          .fontSize(Type.MICRO + 1)
          .fontColor($r('app.color.brand_orange'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.soft_yellow'))
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.useAsBase(t);
            this.toast(`已基于「${t.title}」，可在下方修改`);
          })
        if (this.hasTitle(t.title)) {
          Text('已添加')
            .fontSize(Type.MICRO)
            .fontColor($r('app.color.done_green'))
        } else {
          Text('加入')
            .fontSize(Type.MICRO + 1)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.brand_orange'))
            .borderRadius(Radius.PILL)
            .onClick(() => {
              this.addFromTemplate(t);
            })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .borderRadius(Radius.LG)
    .border({ width: 1, color: $r('app.color.hairline') })
  }

  /** 步骤①：选择年龄模板 */
  @Builder
  AgeTemplateSection() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '① 选择年龄模板（2-10 岁）' })
      this.AgeChips()

      CardSurface({ cardPadding: Space.MD }) {
        Text(this.currentPack().stageLabel)
          .fontSize(Type.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
          .alignSelf(ItemAlign.Start)
        Text(this.currentPack().principle)
          .fontSize(Type.CAPTION + 1)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)

        ForEach(this.packTasks(), (t: TaskItem) => {
          this.PackTaskRow(t)
        }, (t: TaskItem) => `pack-${t.title}-${this.hasTitle(t.title) ? 'a' : 'n'}`)

        AppButton({
          label: '一键套用该年龄模板',
          variant: AppButtonVariant.Soft,
          btnHeight: 48,
          fontSize: Type.BODY,
          block: true,
          onTap: () => {
            this.applyPack();
          }
        })
      }

      Text('其他任务库（不分年龄，左右滑动）')
        .fontSize(Type.CAPTION)
        .fontColor($r('app.color.mist_gray'))
        .alignSelf(ItemAlign.Start)
      this.LibraryBar()
    }
    .width('100%')
  }

  /** 时段选择 chips（多选）：时段推荐由它驱动 */
  @Builder
  SlotChips() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(TimeSlot.allWithAny(), (slot: string) => {
        Text(`${TimeSlot.iconOf(slot)} ${slot}`)
          .fontSize(Type.CAPTION)
          .fontColor(this.newSlots.indexOf(slot) >= 0 ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.newSlots.indexOf(slot) >= 0 ? $r('app.color.brand_orange') : Color.White)
          .borderRadius(Radius.PILL)
          .border({
            width: 2,
            color: this.newSlots.indexOf(slot) >= 0 ? $r('app.color.brand_orange') : $r('app.color.hairline')
          })
          .margin({ right: Space.SM, bottom: Space.SM })
          .onClick(() => {
            this.toggleNewSlot(slot);
          })
      }, (slot: string) => slot)
    }
    .width('100%')
  }

  /** 步骤②：在模板基础上自定义 */
  @Builder
  CustomForm() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: '② 在模板上自定义' })
      CardSurface({ cardPadding: Space.MD }) {
        if (this.baseTemplateTitle !== '') {
          Row({ space: Space.SM }) {
            Text(`基于模板：${this.baseTemplateTitle}`)
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.brand_orange'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('✕ 清除')
              .fontSize(Type.CAPTION)
              .fontColor($r('app.color.mist_gray'))
              .padding({ left: 8, right: 4, top: 4, bottom: 4 })
              .onClick(() => {
                this.clearBase();
              })
          }
          .width('100%')
        } else {
          Text('未选模板，可直接新建任务')
            .fontSize(Type.CAPTION)
            .fontColor($r('app.color.mist_gray'))
            .alignSelf(ItemAlign.Start)
        }

        Row({ space: Space.SM }) {
          HabitIcon({ icon: this.newIcon, iconSize: 40, radius: Radius.SM })
          TextInput({ placeholder: '任务名称', text: this.newTitle })
            .layoutWeight(1)
            .constraintSize({ minWidth: 0, minHeight: MIN_TOUCH })
            .fontSize(Type.BODY)
            .backgroundColor($r('app.color.soft_blue'))
            .borderRadius(Radius.MD)
            .onChange((v: string) => {
              this.newTitle = v;
            })
        }
        .width('100%')

        Row({ space: Space.SM }) {
          AppButton({
            label: `⭐${this.newStars}`,
            variant: AppButtonVariant.Soft,
            btnHeight: MIN_TOUCH,
            block: true,
            onTap: () => {
              this.newStars = this.newStars >= 5 ? 1 : this.newStars + 1;
            }
          })
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
          AppButton({
            label: this.newNeedReview ? '需确认 ✓' : '需确认',
            variant: this.newNeedReview ? AppButtonVariant.Primary : AppButtonVariant.Outline,
            btnHeight: MIN_TOUCH,
            fontSize: Type.CAPTION,
            block: true,
            onTap: () => {
              this.newNeedReview = !this.newNeedReview;
            }
          })
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
        }
        .width('100%')

        AppButton({
          label: this.baseTemplateTitle === '' ? '添加任务' : '保存为自定义任务',
          variant: AppButtonVariant.Primary,
          btnHeight: 52,
          isEnabled: this.newTitle.trim().length > 0,
          block: true,
          onTap: () => {
            const title = this.newTitle.trim();
            const slots = TimeSlot.join(this.newSlots);
            // 基于模板选中的是已有任务 → 就地更新；否则按标题查重后新增
            const existing = this.baseTemplateTitle !== ''
              ? this.findByTitle(this.baseTemplateTitle) : this.findByTitle(title);
            if (existing !== null) {
              // 改名后与别的任务重名 → 拦截，避免出现两个同名任务
              if (title !== existing.title && this.findOtherByTitle(title, existing.id) !== null) {
                this.toast(`已经有叫「${title}」的任务了，换个名字吧`);
                return;
              }
              TaskDao.updateTask(existing.id, title, this.newIcon, this.newStars,
                this.newNeedReview, this.newCategory, slots, this.baseCardColor).then(() => {
                this.reload();
                this.toast(`已更新「${title}」`);
              }).catch((err: Object) => {
                hilog.error(0x0001, 'ParentTasks', 'update task failed: %{public}s', String(err));
                this.toast('保存失败，请重试');
              });
              this.clearBase();
              return;
            }
            this.addTask(title, this.newIcon, this.newStars,
              this.newNeedReview, this.newCategory, slots, this.baseCardColor);
            this.clearBase();
          }
        })

        Text('习惯分类')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
        this.CategoryChips()

        Text('适合时段（宝宝端会按时段推荐）')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
        this.SlotChips()

        Text('选择图标（左右滑动）')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
        this.IconPicker()
      }
    }
    .width('100%')
  }

  /** 分类标题行：拖拽时的投放目标 */
  @Builder
  CategoryHeader(cat: string) {
    Row({ space: Space.SM }) {
      Text(`${cat}（${this.tasksOf(cat).length}）`)
        .fontSize(Type.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dragOverCat === cat ? $r('app.color.brand_orange') : $r('app.color.mist_gray'))
        .layoutWeight(1)
      if (this.dragTaskId >= 0) {
        Text(this.dragOverCat === cat ? '松手放到这里' : '可拖到这里')
          .fontSize(Type.MICRO + 1)
          .fontColor(this.dragOverCat === cat ? $r('app.color.brand_orange') : $r('app.color.mist_gray'))
      }
    }
    .width('100%')
    .padding(Space.SM)
    .borderRadius(Radius.MD)
    .backgroundColor(this.dragOverCat === cat ? $r('app.color.soft_yellow') : Color.Transparent)
    .border({
      width: this.dragOverCat === cat ? 2 : 0,
      color: this.dragOverCat === cat ? $r('app.color.brand_orange') : Color.Transparent
    })
  }

  /** 任务行：右侧审核开关 + 停用；拖动中半透明提示 */
  @Builder
  TaskRow(t: TaskItem, category: string) {
    Column({ space: Space.SM }) {
      HabitRow({
        icon: t.icon,
        title: t.title,
        meta: `${category} · ⭐${t.starValue} · ${this.slotsLabel(t.timeSlots)}`
      }) {
        Toggle({ type: ToggleType.Switch, isOn: t.needReview })
          .onChange((on: boolean) => {
            TaskDao.setNeedReview(t.id, on);
            t.needReview = on;
          })
        AppButton({
          label: '停用',
          variant: AppButtonVariant.Danger,
          btnHeight: 36,
          fontSize: Type.CAPTION,
          onTap: () => {
            TaskDao.deactivate(t.id).then(() => {
              this.reload();
            });
          }
        })
      }

      // 时段快捷切换：点一下切换该时段是否适合此任务
      Row({ space: 6 }) {
        Text('适合时段')
          .fontSize(Type.MICRO + 1)
          .fontColor($r('app.color.mist_gray'))
        ForEach(TimeSlot.allWithAny(), (slot: string) => {
          Text(TimeSlot.iconOf(slot))
            .fontSize(15)
            .opacity(this.slotActive(t, slot) ? 1.0 : 0.28)
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .onClick(() => {
              this.toggleTaskSlot(t, slot);
            })
        }, (slot: string) => `s${slot}`)
      }
      .width('100%')
      .padding({ left: Space.SM, right: Space.SM })
    }
    .width('100%')
    .opacity(this.dragTaskId === t.id ? 0.45 : 1.0)
  }

  /** 该任务当前是否勾选了这个时段 */
  slotActive(t: TaskItem, slot: string): boolean {
    const tags = TimeSlot.parse(t.timeSlots);
    if (slot === TimeSlot.ANY) {
      return tags.length === 1 && tags[0] === TimeSlot.ANY;
    }
    return tags.indexOf(slot) >= 0;
  }

  /**
   * 待审核区：needReview 的任务宝宝打卡后不会发星星，
   * 需要家长在这里点「通过」才真正完成并发星（否则那条记录永远是"待审核"）。
   */
  @Builder
  PendingReviewBar() {
    Column({ space: Space.SM }) {
      SectionTitle({ text: `待确认的打卡（${this.pendingList.length}）` })
      if (this.pendingList.length === 0) {
        Text('今天没有需要确认的打卡')
          .fontSize(Type.MICRO + 1)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
      } else {
        ForEach(this.pendingList, (item: PendingCheckin) => {
          Row({ space: Space.SM }) {
            HabitIcon({ icon: item.icon, iconSize: 32, radius: 10 })
            Column({ space: 2 }) {
              Text(item.title)
                .fontSize(Type.BODY)
                .fontColor($r('app.color.cocoa_text'))
              Text(`⭐${item.starValue} · ${item.date}`)
                .fontSize(Type.MICRO)
                .fontColor($r('app.color.mist_gray'))
            }
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .alignItems(HorizontalAlign.Start)
            AppButton({
              label: '✓ 通过',
              variant: AppButtonVariant.Primary,
              btnHeight: 36,
              fontSize: Type.CAPTION,
              onTap: () => {
                this.approvePending(item);
              }
            })
            AppButton({
              label: '✕ 驳回',
              variant: AppButtonVariant.Danger,
              btnHeight: 36,
              fontSize: Type.CAPTION,
              onTap: () => {
                this.rejectPending(item);
              }
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(Color.White)
          .borderRadius(Radius.LG)
          .border({ width: 1, color: $r('app.color.hairline') })
        }, (item: PendingCheckin) => `p${item.id}`)
      }
    }
    .width('100%')
  }

  @Builder
  Body() {
    List({ space: Space.SM }) {
      ListItem() {
        this.AgeTemplateSection()
      }

      ListItem() {
        this.CustomForm()
      }

      ListItem() {
        Column({ space: Space.SM }) {
          SectionTitle({ text: `③ 当前任务（${this.tasks.length}）` })
          if (this.tasks.length > 0) {
            Text('长按任务卡，拖到分类标题上即可换分类')
              .fontSize(Type.MICRO + 1)
              .fontColor($r('app.color.mist_gray'))
              .alignSelf(ItemAlign.Start)
          }
        }
        .width('100%')
      }

      if (this.pendingList.length > 0) {
        ListItem() {
          this.PendingReviewBar()
        }
      }

      if (this.tasks.length === 0) {
        ListItem() {
          EmptyHint({ text: '还没有任务，先在上面选年龄模板，再添加几个吧' })
        }
      } else {
        ForEach(this.rows, (row: TaskRowItem) => {
          ListItem() {
            if (row.isHeader) {
              this.CategoryHeader(row.category)
            } else if (row.task !== null) {
              this.TaskRow(row.task as TaskItem, row.category)
            }
          }
        }, (row: TaskRowItem) => `${row.isHeader ? 'h' : 't'}-${row.category}-${row.task === null ? 0 : row.task.id}`)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .onItemDragStart((_event: ItemDragInfo, itemIndex: number) => {
      const row = this.rowAt(itemIndex);
      if (row !== null) {
        this.dragTaskId = row.task !== null ? row.task.id : -1;
      }
    })
    .onItemDragMove((_event: ItemDragInfo, _itemIndex: number, insertIndex: number) => {
      if (this.dragTaskId >= 0) {
        this.dragOverCat = this.categoryAt(insertIndex);
      }
    })
    .onItemDragLeave((_event: ItemDragInfo, _itemIndex: number) => {
      this.dragOverCat = '';
    })
    .onItemDrop((_event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
      const row = this.rowAt(itemIndex);
      const target = this.categoryAt(insertIndex);
      const taskId = this.dragTaskId;
      this.resetDrag();
      if (!isSuccess || row === null || row.task === null || target === '') {
        return;
      }
      if (row.task.category !== target) {
        this.moveTo(taskId, target);
      }
    })
  }

  build() {
    Column() {
      // content 尾随闭包传入，保持 this 指向本页；右上角操作用回调参数
      ParentScaffold({
        title: '任务管理',
        actionLabel: '重置今日',
        onActionTap: () => {
          this.confirmReset();
        }
      }) {
        this.Body()
      }
    }
    .width('100%')
    .height('100%')
  }
}

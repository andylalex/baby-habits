import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TaskItem, PhotoEntry } from '../commons/models/Models';
import { HabitIcon } from '../commons/components/HabitIcon';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { TaskDao, CheckinDao, StarDao, BadgeDao, MilestoneDao, ProfileDao } from '../commons/db/Dao';
import { PhotoCapture } from '../commons/utils/PhotoCapture';
import { CardUpdater } from '../commons/utils/CardUpdater';
import { DatabaseHelper } from '../commons/db/DatabaseHelper';
import { SeedData } from '../commons/db/SeedData';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { MaterialSupport } from '../commons/utils/MaterialSupport';
import { Sound } from '../commons/utils/Sound';
import { TimeSlot } from '../commons/utils/TimeSlot';
import { SheetFit } from '../commons/utils/SheetFit';
import { Space, Type, Radius } from '../commons/theme/Theme';

/**
 * App 主界面（宝宝模式）：图形化任务贴纸卡宫格。
 * 数据：演示宝宝"小宝"的今日任务（首次启动自动种子）。
 * 交互：点卡 → 打卡 → 盖章 + 星星入账（事务），卡片转完成态。
 * 家长模式入口在页面右上角小按钮（家长端有指纹/PIN 锁保护）。
 * 视觉：贴纸卡风格（附录 B §3），emoji 为插画占位，M3 替换为插画资源。
 */
@Entry
@Component
struct Index {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 顶部系统避让区高度（vp，来自 getWindowAvoidArea；悬浮元素靠它避让状态栏） */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  /** 底部系统避让区高度（vp，导航条/手势条） */
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  /** 窗口宽高（vp）：弹窗按可用空间自适应尺寸 */
  @StorageProp('windowWidth') screenW: number = 360;
  @StorageProp('windowHeight') screenH: number = 640;
  @State tasks: TaskItem[] = [];
  /**
   * 今日已完成的任务 ID 列表（页面级状态）。
   *
   * 为什么不能直接用 task.doneToday：
   * ForEach 按 key（task.id）复用卡片组件，而 @Builder 的参数是【值传递】，
   * 卡片拿到的是旧 TaskItem 对象；reload() 整体替换 this.tasks 后，
   * ArkUI 不会把新对象同步给已复用的子组件 —— 于是打卡写库成功、
   * 但卡片上的完成态永远不刷新（表现为"某些任务一直完不成"）。
   *
   * 改为由 @State 数组承载完成态：数组引用变化 → 依赖它的卡片节点必然重渲染，
   * 不受 ForEach 复用影响。
   */
  @State doneTaskIds: number[] = [];
  /**
   * 今日【待家长审核】的任务 ID 列表。
   * 这些任务宝宝已打卡，但等家长确认（needReview=true），此时既不算完成、
   * 也不会发星星，卡片要显示成「等家长确认」而不是「已完成」。
   */
  @State pendingTaskIds: number[] = [];
  @State todayStars: number = 0;
  @State balance: number = 0;
  /** 连续打卡天数（火焰标记） */
  @State streak: number = 0;
  @State pressedTaskId: number = -1;
  /** 全屏确认页（UI 规范 3.3 五步闭环第 1-2 步） */
  @State confirmTask: TaskItem | null = null;
  @State stamped: boolean = false;
  /** 上次打卡失败（用于弹窗内提示，失败后按钮仍可重试） */
  @State checkinFailed: boolean = false;
  /** 呼吸引导：当前引导卡放大脉冲（UI 规范 1.1，周期 2.4s） */
  @State pulse: boolean = false;
  /** 星星飞入计数器动画 */
  @State flyY: number = 0;
  @State flyOpacity: number = 0;
  /** 今日已打卡任务的照片（taskId -> 沙盒相对路径列表，一个任务可多张） */
  @State todayPhotoMap: Map<number, string[]> = new Map();
  /** 全屏看图：点击打卡照片后传入沙盒路径，bindContentCover 全模态展示 */
  @State previewUri: string = '';
  /** 全屏看图的可切换照片列表（同一任务的多张照片） */
  @State previewList: string[] = [];
  /** 全屏看图当前页索引 */
  @State previewPos: number = 0;
  /** 成长相册：最近带照片的打卡 */
  @State recentPhotos: PhotoEntry[] = [];
  /** 确认页已拍照片列表（沙盒相对路径，同一任务可拍多张） */
  @State confirmPhotos: string[] = [];
  /** 宫格实际内容宽（由 onAreaChange 实测；0 = 尚未测量，此时按断点估算） */
  @State contentW: number = 0;
  /** 当前时段（如「早晨」），用于时段推荐 */
  @State currentSlot: string = '早晨';
  /** 语音播报开关（默认开；持久化在 settings，跨页同步） */
  @State soundOn: boolean = true;
  /** 宝宝名字（家长可改，来自 profiles 表；读不到时回退演示名） */
  @State kidName: string = SeedData.DEMO_KID_NAME;
  /** 是否使用前置摄像头拍照（传给系统相机原生参数 PickerProfile.cameraPosition） */
  @State useFrontCamera: boolean = false;
  /** 长按刚触发：抑制紧随其后的 click（避免长按后松手又打开任务弹窗） */
  @State suppressClick: boolean = false;
  /**
   * 右上角菜单入口的沉浸材质（薄材质 + 按压光感）。
   * 由外层面板承载（Button 自身的 systemMaterial 在页面内不生效）；
   * 设备不支持沉浸材质时材质自动不生效，底色/描边/阴影兜底观感。
   */
  private menuBtnMaterial: uiMaterial.Material = MaterialSupport.thin();
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    this.reload();
    // 恢复播报开关（持久化），再预热 TTS 引擎
    Sound.loadEnabled().then((on: boolean) => {
      this.soundOn = on;
      if (on) {
        Sound.init();
      }
    });
    this.pulseTimer = setInterval(() => {
      this.pulse = !this.pulse;
    }, 1200);
  }

  aboutToDisappear(): void {
    clearInterval(this.pulseTimer);
  }

  /**
   * 拦截返回键与侧滑返回手势：
   * 确认弹窗开着 → 关闭弹窗（不退出 App）；否则放行（首页退到桌面）。
   * 返回 true = 已处理，阻止默认返回行为。
   */
  onBackPress(): boolean {
    if (this.previewUri !== '') {
      this.previewUri = ''; // 先关全屏看图
      this.previewList = [];
      this.previewPos = 0;
      return true;
    }
    if (this.confirmTask !== null) {
      this.closeConfirm();
      return true;
    }
    return false;
  }

  /** 关闭确认弹窗（返回按钮 / 手势返回统一走这里） */
  closeConfirm(): void {
    this.confirmTask = null;
    this.confirmPhotos = [];
    this.stamped = false;
    this.checkinFailed = false;
  }

  /**
   * 打开全屏看图。
   * @param path 当前查看的照片
   * @param list 同一任务的照片列表（可左右滑动切换）；为空则只显示单张
   */
  openPreview(path: string, list: string[] = []): void {
    this.previewList = list;
    this.previewUri = path;
    this.previewPos = 0;
    for (let i = 0; i < list.length; i++) {
      if (list[i] === path) {
        this.previewPos = i;
        break;
      }
    }
  }

  /** 全屏看图当前页索引（供 Swiper 使用） */
  previewIndex(): number {
    return this.previewPos;
  }

  /** 关闭全屏看图 */
  closePreview(): void {
    this.previewUri = '';
    this.previewList = [];
    this.previewPos = 0;
  }

  /**
   * 确认页插画边长（vp）：按屏幕可用宽高自适应，横屏/小屏也不会溢出。
   * 竖屏手机约 240，大屏约 300，横屏按高度收窄。
   */
  confirmImageSize(): number {
    const availW = this.screenW - 2 * Space.XL;
    // 横屏时高度受限，用高度的一半左右作为上限
    const availH = this.screenH * (this.isLandscape() ? 0.52 : 0.42);
    const base = Math.min(availW, availH);
    return Math.max(120, Math.min(Math.round(base), 300));
  }

  /** 是否横屏（宽 > 高） */
  isLandscape(): boolean {
    return this.screenW > this.screenH;
  }

  /** 切换语音播报：关掉后不再有任何语音播报 */
  toggleSound(): void {
    const next = !this.soundOn;
    this.soundOn = next;
    Sound.setEnabled(next);
    if (next) {
      // 打开时给一次即时反馈，家长立刻知道已开启
      Sound.init();
      Sound.speak('语音播报已打开');
    }
  }

  /**
   * 功能菜单内容（官方 Menu 组件）。
   * 用 ArkUI 原生 Menu/MenuItem：菜单背板由系统绘制，沉浸观感通过
   * MenuOptions.systemMaterial（API 26）交给系统材质统一管理（模糊/滤镜/阴影/描边）。
   */
  @Builder
  FunctionMenu() {
    Menu() {
      MenuItem({ startIcon: '🔒', content: '家长模式' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.openParentMode();
          }
        })
      MenuItem({ startIcon: this.soundOn ? '🔊' : '🔇', content: this.soundOn ? '关闭语音播报' : '打开语音播报' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.toggleSound();
          }
        })
      MenuItem({ startIcon: '🫙', content: '我的星星' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/KidWallet' });
          }
        })
      MenuItem({ startIcon: '📖', content: '时光日志' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/KidTimeline' });
          }
        })
    }
    // 菜单项圆角（弧形观感；菜单背板圆角由 MenuOptions.borderRadius 控制）
    .radius(20)
    .fontSize(Type.BODY)
  }

  /**
   * 菜单浮层的沉浸材质（API 26 MenuOptions.systemMaterial）。
   *
   * 关键点：
   * · 材质生效时系统接管背景色/描边/阴影，**但不影响 backgroundBlurStyle**——
   *   官方菜单示例就是「材质 + 默认模糊」并存的，所以普通模糊保留。
   * · 材质用 THICK（官方菜单设计指南：菜单常覆盖图片/列表等复杂背景，THICK 是稳妥起点）。
   * · 设备不支持材质时，材质实例可照常设置（官方明确「不支持的设备上可设置但无效果」），
   *   此时菜单观感完全由普通模糊兜底，不会出现「无背板」的裸奔状态。
   */
  private menuMat: uiMaterial.Material = MaterialSupport.thick();
  /**
   * 底部悬浮栏的沉浸材质（厚材质 + 按压光晕）。
   * 与菜单浮层同源：都由 MaterialSupport 统一构造，避免两处各写一份参数而逐渐走样。
   */
  private barMaterial: uiMaterial.Material = MaterialSupport.thick();

  /** 进入家长模式（指纹/PIN 锁保护在 ParentHome 内部） */
  openParentMode(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ParentHome' });
  }

  /** 长按刚触发：抑制紧随其后的 click（避免长按后松手又打开任务弹窗） */
  markLongPress(): void {
    this.suppressClick = true;
    // 只抑制很短的一段时间，之后恢复正常点击（不影响菜单打开后继续操作）
    setTimeout(() => {
      this.suppressClick = false;
    }, 500);
  }

  /** 调起系统原生相机拍照（前后镜头取 useFrontCamera 状态） */
  takePhoto(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    PhotoCapture.capture(ctx, this.useFrontCamera).then((path: string | null) => {
      if (path !== null) {
        // 追加而不是替换：同一任务可拍多张
        this.confirmPhotos = this.confirmPhotos.concat([path]);
      }
    });
  }

  /**
   * 给【已完成】的任务补拍照片：直接写库（不重复记星星、不改打卡状态），
   * 拍完刷新任务卡与今日照片映射。
   */
  appendPhotoToDoneTask(task: TaskItem): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    PhotoCapture.capture(ctx, this.useFrontCamera).then((path: string | null) => {
      if (path === null) {
        return;
      }
      CheckinDao.appendPhoto(SeedData.DEMO_KID_ID, task.id, DatabaseHelper.today(), path)
        .then((count: number) => {
          if (count < 0) {
            Sound.speak('补拍失败，请稍后再试');
            return;
          }
          // 刷新今日照片映射与任务状态，卡片主视觉同步换成新照片
          this.reload();
          Sound.speak(`补拍成功，现在一共 ${count} 张照片啦`);
        });
    });
  }

  /**
   * 某任务今日是否已完成（家长已确认）。
   * 读 @State 数组 → ArkUI 能追踪到依赖，卡片完成态一定会刷新。
   */
  isDone(taskId: number): boolean {
    return this.doneTaskIds.indexOf(taskId) >= 0;
  }

  /** 某任务今日是否处于「等家长确认」状态（已打卡但待审核） */
  isPendingReview(taskId: number): boolean {
    return this.pendingTaskIds.indexOf(taskId) >= 0;
  }

  /**
   * 第一张【真正还没打卡】的任务是呼吸引导卡。
   * 待家长确认的任务虽然没"完成"，但宝宝已经做过了，不该再被引导去重复做。
   */
  firstPendingId(): number {
    for (const t of this.tasks) {
      if (!this.isDone(t.id) && !this.isPendingReview(t.id)) {
        return t.id;
      }
    }
    return -1;
  }

  allDone(): boolean {
    return this.tasks.length > 0 && this.firstPendingId() === -1;
  }

  doneTasks(): TaskItem[] {
    return this.tasks.filter((t: TaskItem) => this.isDone(t.id));
  }

  /** 还没打卡的任务（待家长确认的单独算，不算未完成） */
  pendingTasks(): TaskItem[] {
    return this.tasks.filter((t: TaskItem) => !this.isDone(t.id) && !this.isPendingReview(t.id));
  }

  /** 某任务今日照片路径列表（无则空数组） */
  photosOf(taskId: number): string[] {
    const p = this.todayPhotoMap.get(taskId);
    return p === undefined ? [] : p;
  }

  /** 某任务今日第一张照片路径（无则空串），用于任务卡缩略角标 */
  photoOf(taskId: number): string {
    const list = this.photosOf(taskId);
    return list.length > 0 ? list[0] : '';
  }

  /** 手机断点判定（sm <600vp） */
  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  /**
   * 任务卡实际宽度（vp）：由【实测的宫格可用宽】按当前列数等分。
   * 列数必须与 GridCol 的 span 一致（见 gridColumns），否则手算宽度与实际渲染宽度不符，
   * 表现为卡片被挤压/留白——这是「画布不适应设备尺寸」的根因。
   * 实测值尚未到达（首帧）时按断点估算，避免卡片尺寸先错后跳。
   */
  cardW(): number {
    const cols = this.gridColumns();
    const gap = this.gridGap();
    let avail = this.contentW;
    if (avail <= 0) {
      // 兜底估算：手机 360vp 屏可用约 312；平板 700；大屏 900
      avail = this.breakpoint === 'lg' ? 900 : (this.breakpoint === 'md' ? 700 : 312);
    }
    return (avail - (cols - 1) * gap) / cols;
  }

  /** 任务卡高度随宽度走（≈宽 ×1.2，限幅 148-236）：任何屏宽下三段式内容都完整 */
  cardHeight(): number {
    const h = Math.round(this.cardW() * 1.2);
    return Math.max(148, Math.min(h, 236));
  }

  /** 任务卡插画边长：同时受卡片宽与卡片高约束，保证三段式内容永远放得下 */
  cardIconSize(): number {
    const byWidth = Math.round(this.cardW() * 0.46);
    const byHeight = Math.round(this.cardHeight() * 0.42);
    return Math.max(40, Math.min(byWidth, byHeight));
  }

  /** 顶部星星直接展示上限 */
  dotLimit(): number {
    return this.isSm() ? 5 : 10;
  }

  /** 星星飞入：从宫格区飞向顶部计数器 */
  flyStarToCounter(): void {
    this.flyY = 0;
    this.flyOpacity = 1;
    setTimeout(() => {
      this.flyY = -460;
      this.flyOpacity = 0.2;
    }, 50);
    setTimeout(() => {
      this.flyOpacity = 0;
    }, 900);
  }

  /** 计数器一颗颗展示：纯星星图案，不用数字 */
  starDots(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < Math.min(this.todayStars, 12); i++) {
      arr.push(i);
    }
    return arr;
  }

  async reload(): Promise<void> {
    const kidId = SeedData.DEMO_KID_ID;
    const today = DatabaseHelper.today();
    // 时段推荐：每次刷新重算（跨时段后回来即变）
    this.currentSlot = TimeSlot.currentSlot();
    // 宝宝名字：家长在「宝宝档案」里可改，这里读档案而不是写死演示名
    const profile = await ProfileDao.get(kidId);
    this.kidName = profile !== null && profile.name !== '' ? profile.name : SeedData.DEMO_KID_NAME;
    const list = await TaskDao.listActive(kidId);
    const doneIds = await CheckinDao.todayDoneTaskIds(kidId, today);
    const confirmedIds = await CheckinDao.todayConfirmedTaskIds(kidId, today);
    const pendingIds = await CheckinDao.todayPendingTaskIds(kidId, today);
    // 完成态存进 @State 数组：ForEach 复用旧卡片时也能正确刷新完成标记
    const doneList: number[] = [];
    const pendingList: number[] = [];
    for (const t of list) {
      t.doneToday = doneIds.has(t.id);
      // 已确认完成：发过星星、状态 DONE
      if (confirmedIds.has(t.id)) {
        doneList.push(t.id);
      } else if (pendingIds.has(t.id)) {
        // 已打卡但等家长确认
        pendingList.push(t.id);
      }
    }
    this.doneTaskIds = doneList;
    this.pendingTaskIds = pendingList;
    this.tasks = list;
    this.todayStars = await StarDao.todayEarned(kidId, today);
    this.balance = await StarDao.balance(kidId);
    this.streak = await CheckinDao.currentStreak(kidId, today);
    this.todayPhotoMap = await CheckinDao.todayPhotos(kidId, today);
    const photos = await CheckinDao.recentPhotos(kidId, 20);
    for (const p of photos) {
      const t = list.find((item: TaskItem) => item.id === p.taskId);
      p.title = t ? t.title : '';
    }
    this.recentPhotos = photos;
    // 勋章评估（幂等）：有新解锁就语音恭喜
    const fresh = await BadgeDao.evaluate(kidId);
    if (fresh.length > 0) {
      Sound.speak('恭喜解锁新勋章！快去看看吧！');
    }
    // 里程碑评估（幂等）：有站点到达就语音庆祝
    const reached = await MilestoneDao.evaluate(kidId);
    if (reached.length > 0) {
      Sound.speak('哇，到达新的一站啦！快去看看旅行路线！');
    }
    // 同步桌面卡片：余额 + 剩余任务数
    CardUpdater.refresh(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  async doCheckin(task: TaskItem, photoPaths: string[] = []): Promise<void> {
    // 打卡必须自己兜住异常：一旦抛出，stamped 不会被复位，
    // 按钮（isEnabled: !stamped）会永久禁用，用户再也点不动"完成"，
    // 且没有任何提示 —— 表现为"这个任务完成不了"。
    let bonus = false;
    try {
      bonus = await CheckinDao.checkin(task, SeedData.DEMO_KID_ID, DatabaseHelper.today(), photoPaths);
    } catch (err) {
      hilog.error(0x0001, 'Index', 'checkin failed: %{public}s', String(err));
      this.stamped = false;
      this.checkinFailed = true;
      Sound.speak('打卡没成功，请再试一次');
      return;
    }
    const bonusLine = bonus ? '连续打卡奖励一颗星！' : '';
    const photoLine = photoPaths.length > 1 ? `还拍了 ${photoPaths.length} 张照片！` : '';
    Sound.speak(`${task.title}，完成啦！宝宝真棒！${bonusLine}${photoLine}`); // 完成音效：语音播报
    // 盖章动效（450ms）后收页
    this.stamped = true;
    this.checkinFailed = false;
    setTimeout(() => {
      this.confirmTask = null;
      this.confirmPhotos = [];
      this.stamped = false;
      this.reload();
      this.flyStarToCounter(); // 收页后星星飞入计数器
    }, 500);
  }

  /**
   * 实际列数：**必须与 GridCol 的 span 一致**，否则手算卡宽与实际渲染宽度不符。
   * GridRow 12 列，span: {xs:6, sm:6, md:4, lg:3} → 列数 = 12 / span。
   * 关键：GridRow 的断点依据是【窗口宽度】（官方 xs<320 / sm<320-600 / md<600-840 / lg>=840 vp），
   * 而本工程 breakpoint 改为按【最短边】判定（横屏手机要算 sm）。
   * 两者在横屏/平板横屏时不一致，所以这里按 screenW 自行判定 GridRow 那一档，
   * 保证手算卡宽与 GridCol 实际渲染宽度严格对齐。
   */
  gridColumns(): number {
    const w = this.screenW;
    if (w >= 840) {
      return 4; // GridRow lg → span 3 → 12/3
    }
    if (w >= 600) {
      return 3; // GridRow md → span 4 → 12/4
    }
    return 2; // GridRow xs/sm → span 6 → 12/6
  }

  /** 宫格间距 */
  gridGap(): number {
    return this.isSm() ? 12 : 16;
  }

  /** 分组后某分类的任务 */
  tasksOf(category: string): TaskItem[] {
    return this.tasks.filter((t: TaskItem) => t.category === category);
  }

  /** 时段推荐任务：按当前时段优先排序，已完成的剔除 */
  recommendedTasks(): TaskItem[] {
    return TimeSlot.recommend(this.tasks, this.currentSlot, this.isSm() ? 4 : 6);
  }

  /** 推荐栏是否值得展示：没有任何未完成任务时不占地方 */
  hasRecommendation(): boolean {
    return this.recommendedTasks().length > 0;
  }

  /** 该分类下实际要展示的分类列表（有任务的才出标题，保持顺序） */
  visibleCategories(): string[] {
    const cats: string[] = [];
    for (const c of SeedData.CATEGORIES) {
      if (this.tasksOf(c).length > 0) {
        cats.push(c);
      }
    }
    // 兼容历史数据里分类不在清单中的任务
    for (const t of this.tasks) {
      if (cats.indexOf(t.category) < 0) {
        cats.push(t.category);
      }
    }
    return cats;
  }

  /** 卡片底部行高（星星价值 + 完成圆圈） */
  footHeight(): number {
    return this.isSm() ? 28 : 40;
  }

  /**
   * 时段推荐栏：按当前时段推荐任务，横向滑动卡片。
   * 用官方横向 Scroll（嵌套在纵向 Scroll 内），配 nestedScroll 避免手势冲突。
   */
  @Builder
  RecommendBar() {
    Column({ space: Space.SM }) {
      Row({ space: 6 }) {
        Text(`${TimeSlot.iconOf(this.currentSlot)} ${this.currentSlot}推荐`)
          .fontSize(this.isSm() ? 18 : 20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
        Text(TimeSlot.tipOf(this.currentSlot))
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .maxLines(2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Row({ space: Space.SM }) {
          ForEach(this.recommendedTasks(), (task: TaskItem) => {
            this.RecommendCard(task)
          }, (task: TaskItem) => `rec${task.id}`)
        }
        // 横向 Scroll 的子 Row 不能设 width('100%')，否则内容被压成屏幕宽不再横滚
        .padding({ left: Space.XS, right: Space.XS, bottom: Space.XS })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
    }
    .width('100%')
    .padding(Space.MD)
    .backgroundColor($r('app.color.soft_yellow'))
    .borderRadius(Radius.XL)
  }

  /** 推荐卡片：插画 + 任务名 + 时段标签，点按直接进入确认页 */
  @Builder
  RecommendCard(task: TaskItem) {
    Column({ space: 6 }) {
      HabitIcon({ icon: task.icon, iconSize: this.isSm() ? 52 : 60, radius: 16 })
      Text(task.title)
        .fontSize(this.isSm() ? 14 : 15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.cocoa_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
      Text(`⭐${task.starValue}`)
        .fontSize(Type.MICRO + 1)
        .fontColor($r('app.color.mist_gray'))
    }
    .width(this.isSm() ? 96 : 110)
    .padding({ top: 10, bottom: 10, left: 6, right: 6 })
    .backgroundColor(Color.White)
    .borderRadius(Radius.LG)
    .border({ width: 2, color: '#D8CBB8' })
    .shadow({ radius: 8, color: '#2E6B4A2F', offsetY: 3 })
    .onClick(() => {
      this.openTaskSheet(task);
    })
  }

  @Builder
  TaskCard(task: TaskItem, index: number) {
    Column({ space: this.isSm() ? 4 : 8 }) {
      // 1) 插画区：占卡片上部，图片居中不与其他元素重叠
      //    已完成且拍了照片 → 主视觉换成【实拍照片】（宝宝看自己的照片更有成就感）；
      //    未拍照 → 仍显示原插画。
      Stack() {
        if (this.isDone(task.id) && this.photosOf(task.id).length > 0) {
          // 实拍照片铺满插画区
          Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext,
            this.photosOf(task.id)[this.photosOf(task.id).length - 1]))
            .width('100%')
            .height('100%')
            .borderRadius(22)
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              this.openPreview(this.photosOf(task.id)[this.photosOf(task.id).length - 1], this.photosOf(task.id));
            })
          // 多张照片时显示张数角标
          if (this.photosOf(task.id).length > 1) {
            Text(`${this.photosOf(task.id).length}`)
              .fontSize(this.isSm() ? 10 : 12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(this.isSm() ? 20 : 24)
              .height(this.isSm() ? 20 : 24)
              .borderRadius(this.isSm() ? 10 : 12)
              .backgroundColor('#CC000000')
              .textAlign(TextAlign.Center)
              .position({ right: 6, top: 6 })
          }
        } else {
          HabitIcon({ icon: task.icon, iconSize: this.cardIconSize(), radius: 22 })
            .scale({ x: this.pressedTaskId === task.id ? 0.94 : 1.0,
              y: this.pressedTaskId === task.id ? 0.94 : 1.0 })
            .animation({ duration: 120 })
        }
      }
      .width('100%')
      .layoutWeight(1)

      // 2) 文字区：任务名（居中，单行不截断）
      Text(task.title)
        .fontSize(this.isSm() ? 15 : 18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.cocoa_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      // 3) 底部行：星星价值在左，完成圆圈按钮在右（不再压在图片上）
      Row({ space: 6 }) {
        Text(`⭐${task.starValue}`)
          .fontSize(this.isSm() ? 12 : 14)
          .fontColor($r('app.color.mist_gray'))
        Blank()
        if (this.isDone(task.id)) {
          Text('✓')
            .fontSize(this.isSm() ? 16 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(this.isSm() ? 26 : 36)
            .height(this.isSm() ? 26 : 36)
            .borderRadius(this.isSm() ? 13 : 18)
            .backgroundColor($r('app.color.done_green'))
            .textAlign(TextAlign.Center)
            .shadow({ radius: 6, color: '#33000000' })
        } else if (this.isPendingReview(task.id)) {
          // 已打卡但等家长确认：问号圈，不用完成色（避免误导为已完成）
          Text('?')
            .fontSize(this.isSm() ? 16 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(this.isSm() ? 26 : 36)
            .height(this.isSm() ? 26 : 36)
            .borderRadius(this.isSm() ? 13 : 18)
            .backgroundColor('#FFE0A3')
            .textAlign(TextAlign.Center)
            .shadow({ radius: 6, color: '#33000000' })
        } else {
          // 未完成：空心圈，暗示"等你点亮"
          Circle({ width: this.isSm() ? 24 : 32, height: this.isSm() ? 24 : 32 })
            .fill(Color.Transparent)
            .stroke('#D8CBB8')
            .strokeWidth(2)
            .strokeDashArray([4, 3])
        }
      }
      .width('100%')
      .height(this.footHeight())
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.cardHeight())
    .margin({ bottom: this.gridGap() })
    .padding(this.isSm() ? 8 : 12)
    .backgroundColor(task.cardColor)
    .borderRadius(this.isSm() ? 24 : 32)
    // 贴纸微倾斜（奇偶卡交替 ±1°）+ 未完成虚线描边（UI 规范 3.2）
    .rotate({ z: 1, angle: index % 2 === 0 ? -1 : 1 })
    .border({
      width: this.isDone(task.id) ? 4 : 2,
      // 已完成=完成绿；等家长确认=暖黄；未完成=虚线灰
      color: this.isDone(task.id) ? $r('app.color.done_green')
        : (this.isPendingReview(task.id) ? '#E8A33D' : '#D8CBB8'),
      style: this.isDone(task.id) || this.isPendingReview(task.id) ? BorderStyle.Solid : BorderStyle.Dashed
    })
    // 呼吸引导：仅第一张未完成任务卡
    .scale(task.id === this.firstPendingId() && !this.isDone(task.id)
      ? { x: this.pulse ? 1.04 : 1.0, y: this.pulse ? 1.04 : 1.0 }
      : { x: 1.0, y: 1.0 })
    .animation({ duration: 1200, curve: Curve.EaseInOut })
    .shadow({ radius: 16, color: '#2E6B4A2F', offsetY: 6 })
    .opacity(this.isDone(task.id) ? 0.85 : 1.0)    .onTouch((event) => {
      if (event.type === TouchType.Down) {
        this.pressedTaskId = task.id;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedTaskId = -1;
      }
    })
    .onClick(() => {
      // 未完成 → 打卡模式；已完成 → 查看模式（弹窗里展示这个任务今天拍的照片）
      this.openTaskSheet(task);
    })
  }

  /**
   * 弹窗里要展示的照片列表。
   * 未完成（打卡模式）→ 本次新拍的照片（confirmPhotos）；
   * 已完成 / 待家长确认（查看模式）→ 该任务今天已拍的所有照片。
   */
  sheetPhotos(task: TaskItem): string[] {
    if (this.isDone(task.id) || this.isPendingReview(task.id)) {
      return this.photosOf(task.id);
    }
    return this.confirmPhotos;
  }

  /**
   * 打开任务弹窗并做语音播报。
   * 未完成：读出任务名（不识字宝宝可独立使用）。
   * 已完成：夸赞 + 报出今天拍的照片张数。
   */
  openTaskSheet(task: TaskItem): void {
    // 长按刚触发时，忽略这一次点击（否则长按松手会顺带打开弹窗）
    if (this.suppressClick) {
      return;
    }
    this.confirmPhotos = [];
    this.confirmTask = task;
    this.checkinFailed = false;
    if (this.isPendingReview(task.id)) {
      // 已打卡、等家长确认
      Sound.speak(`${task.title}已经做完啦，等爸爸妈妈确认`);
    } else if (!this.isDone(task.id)) {
      Sound.speak(task.title);
    } else {
      const n = this.photosOf(task.id).length;
      if (n > 0) {
        Sound.speak(`${task.title}完成啦，还拍了 ${n} 张照片！`);
      } else {
        this.praiseDone(task);
      }
    }
  }

  /** 已完成的任务被点击：播放夸赞语音，强化正向反馈（每条卡固定一句，避免随机感错乱） */
  praiseDone(task: TaskItem): void {
    const lines: string[] = [
      `${task.title}，已经完成啦，宝宝真棒！`,
      `${task.title}做得真好，你是了不起的宝宝！`,
      `哇，${task.title}完成啦，为你骄傲！`,
      `${task.title}打卡成功，继续加油哦！`
    ];
    Sound.speak(lines[task.id % lines.length]);
  }

  /** 全屏确认页：大图 + 大按钮（120vp）+ 盖章动效
   *  · 顶部有「← 返回」按钮，返回键/侧滑手势也可关闭（见 onBackPress）
   *  · 支持给同一任务拍多张照片，横向缩略图条展示，可点开大图/删除
   *  · 多设备适配：整页可滚动（横屏/小屏不裁切）、内容限宽居中、
   *    顶部避让状态栏/挖孔、底部避让导航条、插画按可用空间自适应 */
  @Builder
  ConfirmOverlay(task: TaskItem) {
    Scroll() {
      Column({ space: 16 }) {
      Row() {
        // 返回按钮：关闭弹窗回到任务列表（不退出 App）
        // 注意：stateEffect 是 Button 的属性，Row/Column 等容器没有该属性，写在 Row 上会编译失败
        Button() {
          Row({ space: 4 }) {
            Text('←')
              .fontSize(this.isSm() ? 22 : 26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.cocoa_text'))
            Text('返回')
              .fontSize(this.isSm() ? 14 : 16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.cocoa_text'))
          }
        }
        .height(this.isSm() ? 44 : 50)
        .padding({ left: 14, right: 18, top: 8, bottom: 8 })
        .borderRadius(999)
        .backgroundColor($r('app.color.soft_yellow'))
        .stateEffect(true)
        .onClick(() => {
          this.closeConfirm();
        })

        Blank()

        // 关闭按钮（保留右上角 ✕，与返回等效）
        Button('✕')
          .width(this.isSm() ? 44 : 50)
          .height(this.isSm() ? 44 : 50)
          .fontSize(this.isSm() ? 20 : 24)
          .fontColor($r('app.color.cocoa_text'))
          .backgroundColor($r('app.color.soft_yellow'))
          .borderRadius(this.isSm() ? 22 : 25)
          .stateEffect(true)
          .onClick(() => {
            this.closeConfirm();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack() {
        if (this.sheetPhotos(task).length > 0) {
          Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext,
            this.sheetPhotos(task)[this.sheetPhotos(task).length - 1]))
            .width(this.confirmImageSize())
            .height(this.confirmImageSize())
            .borderRadius(32)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 16, color: '#40000000' })
            .onClick(() => {
              this.openPreview(this.sheetPhotos(task)[this.sheetPhotos(task).length - 1], this.sheetPhotos(task));
            })
        } else {
          HabitIcon({ icon: task.icon, iconSize: this.confirmImageSize(), radius: 40 })
        }
        if (this.stamped) {
          Text('✓')
            .fontSize(56)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(120)
            .height(120)
            .borderRadius(60)
            .backgroundColor($r('app.color.done_green'))
            .textAlign(TextAlign.Center)
            .shadow({ radius: 16, color: '#40000000' })
            .scale({ x: this.stamped ? 1.0 : 1.8, y: this.stamped ? 1.0 : 1.8 })
            .rotate({ angle: this.stamped ? 0 : -12 })
            .animation({ duration: 450, curve: Curve.EaseOut })
        }
      }
      .layoutWeight(1)

      Text(task.title)
        .fontSize(Type.DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))

      // 已完成 / 待家长确认（查看模式）：展示状态与今天拍的照片，并支持【补拍照片】
      if (this.isDone(task.id) || this.isPendingReview(task.id)) {
        Column({ space: Space.SM }) {
          if (this.isPendingReview(task.id)) {
            Text(`⏳ 已做完啦，等爸爸妈妈确认${this.sheetPhotos(task).length > 0 ? `（拍了 ${this.sheetPhotos(task).length} 张照片）` : ''}`)
              .fontSize(Type.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor('#C97A1E')
          } else {
            Text(`✅ 今天完成啦，拍了 ${this.sheetPhotos(task).length} 张照片`)
              .fontSize(Type.TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.done_green'))
          }
          if (this.sheetPhotos(task).length > 0) {
            Scroll() {
              Row({ space: Space.SM }) {
                ForEach(this.sheetPhotos(task), (p: string, idx: number) => {
                  Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext, p))
                    .width(96)
                    .height(96)
                    .borderRadius(14)
                    .objectFit(ImageFit.Cover)
                    .onClick(() => {
                      this.openPreview(p, this.sheetPhotos(task));
                    })
                }, (p: string, idx: number) => `vp${idx}`)
              }
              .padding({ left: Space.XS, right: Space.XS, bottom: Space.XS })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 补拍照片：任务已完成也还能再拍（只追加照片，不重复记星星）
          AppButton({
            label: '📷 补拍一张',
            variant: AppButtonVariant.Outline,
            btnHeight: 56,
            fontSize: Type.BODY,
            block: true,
            onTap: () => {
              this.appendPhotoToDoneTask(task);
            }
          })
            .width('100%')
        }
        .width('100%')
        .padding(Space.MD)
        .backgroundColor(Color.White)
        .borderRadius(Radius.LG)
      } else {
      // 打卡失败提示：让用户知道可以再点一次，而不是以为按钮坏了
      if (this.checkinFailed) {
        Text('😢 刚才没打卡成功，再点一次试试吧')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.danger'))
          .width('90%')
          .textAlign(TextAlign.Center)
      }

      AppButton({
        label: `我完成啦 ⭐${task.starValue}`,
        variant: this.stamped ? AppButtonVariant.Soft : AppButtonVariant.Primary,
        btnHeight: 92,
        fontSize: Type.TITLE + 6,
        block: true,
        isEnabled: !this.stamped,
        onTap: () => {
          this.doCheckin(task, this.confirmPhotos);
        }
      })
        .width('90%')

      // 拍照打卡：走【系统原生相机】(cameraPicker)，可连续拍多张
      AppButton({
        label: this.confirmPhotos.length > 0
          ? `📷 再拍一张（已拍 ${this.confirmPhotos.length} 张）`
          : '📷 拍张照片再打卡',
        variant: AppButtonVariant.Outline,
        btnHeight: 68,
        fontSize: Type.TITLE,
        block: true,
        isEnabled: !this.stamped,
        onTap: () => {
          this.takePhoto();
        }
      })
        .width('90%')

      // 切换前后摄像头：用系统相机组件的原生参数（PickerProfile.cameraPosition）
      AppButton({
        label: this.useFrontCamera ? '🔄 切换到后置摄像头' : '🔄 切换到前置摄像头',
        variant: AppButtonVariant.Soft,
        btnHeight: 48,
        fontSize: Type.BODY,
        block: true,
        isEnabled: !this.stamped,
        onTap: () => {
          this.useFrontCamera = !this.useFrontCamera;
          Sound.speak(this.useFrontCamera ? '切换到前置摄像头' : '切换到后置摄像头');
        }
      })
        .width('90%')

      // 从系统相册选图（PhotoViewPicker，无需存储权限），同样可累加多张
      AppButton({
        label: this.confirmPhotos.length > 0 ? '🖼 再选一张照片' : '🖼 用相册里的照片',
        variant: AppButtonVariant.Outline,
        btnHeight: 56,
        fontSize: Type.BODY,
        block: true,
        isEnabled: !this.stamped,
        onTap: () => {
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          PhotoCapture.pickFromGallery(ctx).then((path: string | null) => {
            if (path !== null) {
              this.confirmPhotos = this.confirmPhotos.concat([path]);
            }
          });
        }
      })
        .width('90%')

      // 已拍照片缩略图条：点开看大图，长按/点 ✕ 移除
      if (this.confirmPhotos.length > 0) {
        Scroll() {
          Row({ space: Space.SM }) {
            ForEach(this.confirmPhotos, (p: string, idx: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext, p))
                  .width(72)
                  .height(72)
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .onClick(() => {
                    this.openPreview(p, this.confirmPhotos);
                  })
                Text('✕')
                  .fontSize(11)
                  .fontColor(Color.White)
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .backgroundColor('#99000000')
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    const next: string[] = [];
                    for (let i = 0; i < this.confirmPhotos.length; i++) {
                      if (i !== idx) {
                        next.push(this.confirmPhotos[i]);
                      }
                    }
                    this.confirmPhotos = next;
                  })
              }
            }, (p: string, idx: number) => `cp${idx}`)
          }
          .padding({ left: Space.XS, right: Space.XS, bottom: Space.XS })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('90%')
      }
      } // 闭合 else（打卡模式）
      } // 闭合 Column
      // 内容列：宽屏限宽居中，手机满宽
      .width('100%')
      .constraintSize({ maxWidth: SheetFit.MAX_W })
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: Space.XL,
        right: Space.XL,
        top: SheetFit.padTop(this.safeAreaTop),
        bottom: SheetFit.padBottom(this.safeAreaBottom)
      })
    }
    // 【铺满全设备】官方方案二：ignoreLayoutSafeArea 配合 LayoutPolicy.matchParent，
    // 两者缺一不可：
    //   · ignoreLayoutSafeArea 扩展【布局位置和大小】到非安全区（状态栏/导航条）
    //   · LayoutPolicy.matchParent 让尺寸跟随父容器扩展后的区域，而不是写死 100%
    // 只写 ignoreLayoutSafeArea 而不写 matchParent：位置变了但大小不变 → 仍然没铺满。
    .width(LayoutPolicy.matchParent)
    .height(LayoutPolicy.matchParent)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    // Scroll 的 align 默认是 Center（内容短于视口时垂直居中），
    // 确认页希望内容从顶部开始，故显式顶对齐
    .align(Alignment.Top)
    .backgroundColor($r('app.color.cream_background'))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  /** 内容宽度：始终铺满父容器（100%），大屏再靠下方 constraintSize 限宽居中。
   *  不能返回固定 760/1000——一旦手机端断点误判为 md/lg，整列会被撑爆、横向溢出手机屏。 */
  contentWidth(): Length {
    return '100%';
  }

  /** 全屏看图覆盖层（bindContentCover 全模态组件驱动）：点击任意打卡照片后展示。
   *  同一任务多张照片时用 Swiper 左右滑动切换。 */
  @Builder
  PhotoFullscreen() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#E6000000')
        .onClick(() => {
          this.closePreview();
        })

      Column({ space: Space.SM }) {
        Row() {
          Text('✕')
            .fontSize(20)
            .fontColor(Color.White)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          this.closePreview();
        })

        if (this.previewUri !== '') {
          // 多张时 Swiper 左右滑动；单张时直接显示
          if (this.previewList.length > 1) {
            Swiper() {
              ForEach(this.previewList, (p: string) => {
                Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext, p))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Contain)
              }, (p: string) => `pv${p}`)
            }
            .index(this.previewIndex())
            .onChange((idx: number) => {
              this.previewPos = idx;
            })
            .width('100%')
            .layoutWeight(1)
            .indicator(false)
            .loop(false)
          } else {
            Image(PhotoCapture.toUri(this.getUIContext().getHostContext() as common.UIAbilityContext, this.previewUri))
              .width('100%')
              .layoutWeight(1)
              .objectFit(ImageFit.Contain)
          }
        }
      }
      // 内容列：宽屏限宽居中（超宽屏不让图无限拉伸），手机满宽
      .width('100%')
      // 关键：必须有确定高度，内部的 layoutWeight(1) 才有参照，
      // 否则图片区高度塌陷、大图撑不满屏幕（这是"弹窗高度没覆盖设备"的根因之一）
      .height('100%')
      .constraintSize({ maxWidth: SheetFit.MAX_W_FULL })
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: Space.MD,
        right: Space.MD,
        top: SheetFit.padTop(this.safeAreaTop),
        bottom: SheetFit.padBottom(this.safeAreaBottom)
      })
    }
    // 【铺满全设备】ignoreLayoutSafeArea + LayoutPolicy.matchParent 两者缺一不可：
    // 前者扩展布局位置与大小到非安全区，后者让尺寸跟随父容器扩展后的区域。
    .width(LayoutPolicy.matchParent)
    .height(LayoutPolicy.matchParent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      Scroll() {
      Row() {
      Column({ space: 16 }) {
      // 顶部：今日星星计数器（一颗颗展示，超过 10 颗折叠为 ×N）+ 钱包余额（UI 规范 3.4）
      Row({ space: 12 }) {
        Row({ space: 4 }) {
          ForEach(this.starDots(), (i: number) => {
            Text('⭐')
              .fontSize(18)
          }, (i: number) => `${i}`)
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.soft_yellow'))
        .borderRadius(999)

        // 连续打卡火焰：streak ≥ 2 才展示，鼓励 continuity 不制造焦虑
        if (this.streak >= 2) {
          Row({ space: 4 }) {
            Text('🔥')
              .fontSize(20)
            Text(`${this.streak}`)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E8641F')
          }
          .padding({ left: 12, right: 14, top: 9, bottom: 9 })
          .backgroundColor('#FFF1E3')
          .borderRadius(999)
          .onClick(() => {
            Sound.speak(`已经连续打卡 ${this.streak} 天啦，真棒！`);
          })
        }
      }
      .width('100%')

      // 成就墙入口
      Row({ space: 8 }) {
        Row({ space: 4 }) {
          Text('🏅')
            .fontSize(18)
          Text('勋章')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.cocoa_text'))
        }
        .padding({ left: 12, right: 14, top: 8, bottom: 8 })
        .backgroundColor(Color.White)
        .borderRadius(999)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/KidBadges' });
        })

        // 成长旅行（里程碑路线图）入口
        Row({ space: 4 }) {
          Text('🗺️')
            .fontSize(18)
          Text('旅行')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.cocoa_text'))
        }
        .padding({ left: 12, right: 14, top: 8, bottom: 8 })
        .backgroundColor(Color.White)
        .borderRadius(999)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/KidMilestones' });
        })
      }
      .width('100%')

      Row({ space: 8 }) {
          Text('🫙')
            .fontSize(24)
          Text(`${this.balance}`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.cocoa_text'))
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.soft_blue'))
        .borderRadius(999)
        .onClick(() => {
          Sound.speak(`你有 ${this.balance} 颗星星`);
        })

      Text(`今日任务 · ${this.kidName}`)
        .fontSize(this.isSm() ? 24 : 32)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))

      // 时段推荐栏：按当前时段推荐合适的任务（已完成全部时自动隐藏）
      if (this.hasRecommendation()) {
        this.RecommendBar()
      }

      // 习惯分类分组展示：全部任务平铺出来，不滚动裁剪
      ForEach(this.visibleCategories(), (cat: string) => {
        Column({ space: 10 }) {
          Text(cat)
            .fontSize(this.isSm() ? 18 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.cocoa_text'))
            .alignSelf(ItemAlign.Start)
            .padding({ left: 4 })
          // 响应式宫格：GridRow/GridCol 按窗口断点自动分列（手机 2 列 / 平板 3 列 / 大屏 4 列），
          // 框架自动等宽、自动换行，无需手算百分比（鸿蒙「一多」宫格卡片官方方案）
          GridRow({ columns: 12, gutter: this.gridGap() }) {
            ForEach(this.tasksOf(cat), (task: TaskItem, idx: number) => {
              GridCol({ span: { xs: 6, sm: 6, md: 4, lg: 3 } }) {
                this.TaskCard(task, idx)
              }
              .constraintSize({ minWidth: 0 })
            }, (task: TaskItem) => `${task.id}`)
          }
          .width('100%')
        }
        .width('100%')
      }, (cat: string) => cat)

      // 今日小结：做得好 / 继续加油（正向语言，方案心理设计原则 5：不批评、不对比）
      if (this.doneTasks().length > 0) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Text('👏 做得真棒')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.done_green'))
              .layoutWeight(1)
            Row({ space: 6 }) {
              ForEach(this.doneTasks().slice(0, 5), (t: TaskItem) => {
                HabitIcon({ icon: t.icon, iconSize: 32, radius: 8 })
              }, (t: TaskItem) => `d${t.id}`)
              if (this.doneTasks().length > 5) {
                Text(`+${this.doneTasks().length - 5}`)
                  .fontSize(14)
                  .fontColor($r('app.color.done_green'))
              }
            }
          }
          if (this.pendingTasks().length > 0) {
            Row({ space: 6 }) {
              Text('💪 继续加油')
                .fontSize(16)
                .fontColor($r('app.color.cocoa_text'))
                .layoutWeight(1)
              Row({ space: 6 }) {
                ForEach(this.pendingTasks().slice(0, 5), (t: TaskItem) => {
                  HabitIcon({ icon: t.icon, iconSize: 30, radius: 8 })
                    .opacity(0.55)
                }, (t: TaskItem) => `p${t.id}`)
                if (this.pendingTasks().length > 5) {
                  Text(`+${this.pendingTasks().length - 5}`)
                    .fontSize(14)
                    .fontColor($r('app.color.mist_gray'))
                }
              }
            }
            Text('做完这些，今天就超级棒啦！')
              .fontSize(13)
              .fontColor($r('app.color.mist_gray'))
              .alignSelf(ItemAlign.Start)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Color.White)
        .borderRadius(20)
      }

      // 全部完成庆祝（UI 规范 3.5）
      if (this.allDone()) {
        Text('🎉 今天的任务全部完成，宝宝好棒！')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.done_green'))
      }
      }
      .width(this.contentWidth())
      .constraintSize({ maxWidth: 1000 })
      // 顶部留白给右上角悬浮控制条（家长入口 + 播报开关）：状态栏高度 + 悬浮条高 + 间距
      .padding({
        left: 24,
        right: 24,
        top: this.safeAreaTop + (this.isSm() ? 56 : 62),
        // 底部留白：底部悬浮栏高度 + 导航条避让（窗口沉浸式下需自行避让）
        bottom: (this.isSm() ? 108 : 96) + this.safeAreaBottom
      })
      // 画布实测宽：扣掉自身左右 padding，得到宫格真正可用宽度
      // （不能写死 48——左右 padding 变了就会算错卡宽，表现为卡片挤压/留白）
      .onAreaChange((_old: Area, area: Area) => {
        const total = Number(area.width);
        this.contentW = Math.max(0, total - 48);
      })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    // 背景铺满整个视口（不挂在限宽的内容列上，否则宽屏两侧留白）
    .backgroundColor($r('app.color.cream_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

    // 功能菜单入口（悬浮，不随内容滚动）：点击弹出官方菜单
    //   沉浸观感：Button 的 systemMaterial 只在 Navigation 标题栏/底部 TabBar 生效，
    //   页面内悬浮按钮必须由**外层面板**承载材质（内层按钮背景透明，让玻璃透出）——
    //   与本页底部悬浮栏同一套路。材质不支持时退回半透白底。
    Column() {
      Button() {
        Text('⋯')
          .fontSize(this.isSm() ? 20 : 22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
      }
      .width(this.isSm() ? 36 : 42)
      .height(this.isSm() ? 36 : 42)
      .borderRadius(this.isSm() ? 18 : 21)
      // 内层按钮透明：玻璃由外层面板的材质提供，按钮自身背景会盖住材质
      .backgroundColor(Color.Transparent)
      .stateEffect(true)
      .accessibilityText('功能菜单')
      // 点击弹出菜单（与长按任意位置弹出的是同一份菜单）
      //   绑定放在真正可点的 Button 上（Button 会消费点击，绑在外层面板上可能不触发）
      //   背板观感交给系统材质（API 26 MenuOptions.systemMaterial）。
      .bindMenu(this.FunctionMenu(), {
        placement: Placement.BottomRight,
        enableArrow: false,
        borderRadius: 20,
        backgroundBlurStyle: BlurStyle.Thick,
        systemMaterial: this.menuMat
      })
    }
    .width(this.isSm() ? 42 : 48)
    .height(this.isSm() ? 42 : 48)
    .borderRadius(this.isSm() ? 21 : 24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    // 兜底样式：材质生效时会被系统接管（背景清空为透明），不支持材质时由它撑起观感
    .backgroundColor('#E6FFFFFF')
    .border({ width: 1, color: '#E8DCC8' })
    .shadow({ radius: 6, color: '#2E6B4A2F', offsetY: 2 })
    // systemMaterial 必须放在 background/border/shadow/radius 之后设置，才由材质统一接管
    .systemMaterial(this.menuBtnMaterial)
    .position({ top: this.safeAreaTop + 8, right: 14 })
    .zIndex(10)

    // 沉浸光感底部操作栏（HarmonyOS 7 / API 26 Immersive Material）
    //   · systemMaterial 加【外层面板】，玻璃质感铺满整条栏（子树只设一次，内部按钮不再各自设材质）
    //   · 按钮半透/幽灵态，让玻璃透出；interactive:true 提供按压光晕
    //   · 手机端铺满（两侧留白），大屏居中限宽，自适应宽度
    // 本页已是 App 首页（宝宝模式），故不再放「返回」——改为「我的星星」单按钮铺满
    Column() {
      Row({ space: Space.SM }) {
        // 主行动：品牌色半透玻璃胶囊，仍清晰可辨
        Button('🫙 我的星星')
          .layoutWeight(1)
          .height(54)
          .borderRadius(Radius.PILL)
          .fontSize(Type.TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor('#CCFF8A3D')
          .stateEffect(true)
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/KidWallet' });
          })
      }
      .width('100%')
      // 底部内边距避让导航条/手势条：窗口沉浸式下栏体贴到窗口底，
      // 不加这段按钮会被系统手势条压住
      .padding({
        left: 14,
        right: 14,
        top: 12,
        bottom: 12 + this.safeAreaBottom
      })
    }
    .width('100%')
    .alignSelf(ItemAlign.Center)
    .constraintSize({ maxWidth: 680 })
    .padding({ left: 10, right: 10 })
    .position({ bottom: 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .borderRadius(22)
    .systemMaterial(this.barMaterial)

    // 全屏确认页覆盖层
    if (this.confirmTask !== null) {
      this.ConfirmOverlay(this.confirmTask);
    }

    // 星星飞入计数器（收页后触发）
    if (this.flyOpacity > 0) {
      Text('⭐')
        .fontSize(44)
        .position({ bottom: 200, left: '46%' })
        .translate({ y: this.flyY })
        .opacity(this.flyOpacity)
        .animation({ duration: 800, curve: Curve.EaseOut })
    }
  }
  .bindContentCover(this.previewUri !== '', this.PhotoFullscreen(), {
    backgroundColor: Color.Black,
    onDisappear: () => {
      this.previewUri = '';
      this.previewList = [];
      this.previewPos = 0;
    }
  })
  // 任意位置长按 → 弹出【官方 Menu 组件】上下文菜单
  //   ResponseType.LongPress = 长按触发；背板沉浸观感由 ContextMenuOptions.systemMaterial 交给系统材质
  .bindContextMenu(this.FunctionMenu(), ResponseType.LongPress, {
    placement: Placement.Bottom,
    enableArrow: false,
    borderRadius: 20,
    backgroundBlurStyle: BlurStyle.Thick,
    systemMaterial: this.menuMat,
    onAppear: () => {
      // 标记长按已触发：紧接着的一次 click 应当被忽略（否则松手会又打开任务弹窗）
      this.markLongPress();
    }
  })
  .width('100%')
  .height('100%')
}
}

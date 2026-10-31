import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { RewardItem, RedemptionCard, TaskItem, PhotoEntry } from '../commons/models/Models';
import { RewardDao, StarDao, RedemptionDao, CheckinDao, TaskDao } from '../commons/db/Dao';
import { PhotoCapture } from '../commons/utils/PhotoCapture';
import { ShareCard, ShareTile } from '../commons/utils/ShareCard';
import { GallerySave } from '../commons/utils/GallerySave';
import { CardUpdater } from '../commons/utils/CardUpdater';
import { SeedData } from '../commons/db/SeedData';
import { HabitIcon } from '../commons/components/HabitIcon';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { SectionTitle } from '../commons/components/Primitives';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { Sound } from '../commons/utils/Sound';
import { SheetFit } from '../commons/utils/SheetFit';
import { Radius, Space, Type, Elevation, Motion } from '../commons/theme/Theme';

/** 星星点阵最多展示颗数，超出折叠为 ×N（UI 规范 4.1） */
const STAR_DOTS: number = 12;

/** 相册按月分组：与时光日志一致的记忆编排 */
interface MonthGroup {
  key: string;
  label: string;
  photos: PhotoEntry[];
}

/**
 * 儿童端 · 星星心愿瓶（附录 B §4）。
 * 彩珠数量=星星余额；水位=距离下一个心愿的进度；兑换走家长长按确认（2s）→ 事务扣星 → 收集卡册。
 * 一多：手机单列；平板/PC 左右分栏（左星星瓶、右心愿卡网格）。
 */
@Entry
@Component
struct KidWallet {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 系统避让区与窗口尺寸（vp）：弹窗按可用空间自适应 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  @StorageProp('windowWidth') screenW: number = 360;
  @StorageProp('windowHeight') screenH: number = 640;
  @State balance: number = 0;
  @State rewards: RewardItem[] = [];
  @State cards: RedemptionCard[] = [];
  @State confirmReward: RewardItem | null = null;
  @State holdProgress: number = 0; // 0-1 长按进度
  @State celebrating: boolean = false;
  /** 可兑换心愿卡的呼吸引导（周期 2.4s） */
  @State pulse: boolean = false;
  /** 成长相册（含任务分类信息） */
  @State photos: PhotoEntry[] = [];
  @State allTasks: TaskItem[] = [];
  /** 相册分类筛选：'全部' 或具体分类 */
  @State photoCat: string = '全部';
  /** 大图浏览（bindContentCover 全模态） */
  @State previewOpen: boolean = false;
  @State previewPos: number = 0;
  @State saving: boolean = false;
  /** 正在生成分享图（合成 + 存相册是异步过程，需要 loading 反馈） */
  @State sharing: boolean = false;
  /** 长按弹出的回忆操作菜单（含删除） */
  @State menuPhoto: PhotoEntry | null = null;
  @State menuShown: boolean = false;
  /** 手机端横向分屏当前页（0=星星瓶 1=成长时光 2=兑换心愿） */
  @State pageIndex: number = 0;
  /** 横向分屏控制器：供顶部标签直接跳页 */
  private swiperController: SwiperController = new SwiperController();
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    Sound.init(); // 预热 TTS 引擎
    this.reload();
    this.pulseTimer = setInterval(() => {
      this.pulse = !this.pulse;
    }, 1200);
  }

  aboutToDisappear(): void {
    clearInterval(this.pulseTimer);
  }

  async reload(): Promise<void> {
    this.balance = await StarDao.balance(SeedData.DEMO_KID_ID);
    this.rewards = await RewardDao.listActive(SeedData.DEMO_KID_ID);
    this.cards = await RedemptionDao.listCards(SeedData.DEMO_KID_ID);
    this.allTasks = await TaskDao.listActive(SeedData.DEMO_KID_ID);
    const photos = await CheckinDao.recentPhotos(SeedData.DEMO_KID_ID, 100);
    for (const p of photos) {
      const t = this.allTasks.find((item: TaskItem) => item.id === p.taskId);
      p.title = t ? t.title : '';
    }
    this.photos = photos;
    // 兑换后同步桌面卡片余额
    CardUpdater.refresh(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  /** 某任务的习惯分类（历史任务可能已停用，查不到归「其他」） */
  categoryOf(taskId: number): string {
    const t = this.allTasks.find((item: TaskItem) => item.id === taskId);
    return t ? t.category : '其他';
  }

  /** 相册可用分类（按全局顺序 + 其他） */
  photoCategories(): string[] {
    const cats: string[] = ['全部'];
    for (const c of SeedData.CATEGORIES) {
      if (this.photos.some((p: PhotoEntry) => this.categoryOf(p.taskId) === c)) {
        cats.push(c);
      }
    }
    if (this.photos.some((p: PhotoEntry) => this.categoryOf(p.taskId) === '其他')) {
      cats.push('其他');
    }
    return cats;
  }

  filteredPhotos(): PhotoEntry[] {
    if (this.photoCat === '全部') {
      return this.photos;
    }
    return this.photos.filter((p: PhotoEntry) => this.categoryOf(p.taskId) === this.photoCat);
  }

  /** 删除一张照片：清库 + 删沙盒文件（打卡记录和星星保留） */
  async deletePhoto(p: PhotoEntry): Promise<void> {
    const rel = await CheckinDao.clearPhoto(p.id);
    if (rel !== '') {
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        fileIo.unlinkSync(`${ctx.filesDir}/${rel}`);
      } catch (err) {
        // 文件可能已不存在，忽略
      }
    }
    this.photos = this.photos.filter((item: PhotoEntry) => item.id !== p.id);
  }

  /** 主打心愿：第一个未攒够的（按定价升序），攒够则取最便宜的可兑换 */
  nextGoal(): RewardItem | null {
    for (const r of this.rewards) {
      if (r.starCost > this.balance) {
        return r;
      }
    }
    return this.rewards.length > 0 ? this.rewards[0] : null;
  }

  /** 水位 0-1 */
  waterLevel(): number {
    const goal = this.nextGoal();
    if (!goal) {
      return 1;
    }
    return Math.min(1, this.balance / goal.starCost);
  }

  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  isLg(): boolean {
    return this.breakpoint === 'lg';
  }

  /** 弹窗卡片最大高度（vp）：可用高度扣掉安全区，横屏/小屏也不超出屏幕 */
  sheetMaxHeight(): number {
    const avail = this.screenH - this.safeAreaTop - this.safeAreaBottom;
    return Math.max(240, avail - 24);
  }

  /** 心愿卡固定高度：容下插画+名称+星点阵+状态 */
  wishCardH(): number {
    return this.isSm() ? 176 : 200;
  }

  /** 相册/卡册卡片宽度：手机 3 列、平板 4 列、大屏 5 列 */
  tileWidth(): string {
    return this.isLg() ? '18%' : (this.isSm() ? '31%' : '23%');
  }

  /** 彩珠数组：每颗星星一颗珠（最多展示 40 颗，UI 规范 4.1） */
  beadCount(): number {
    return Math.min(this.balance, 40);
  }

  /** 倒序索引数组：让珠子从瓶底往上长 */
  beadArray(): number[] {
    const arr: number[] = [];
    for (let i = this.beadCount() - 1; i >= 0; i--) {
      arr.push(i);
    }
    return arr;
  }

  canRedeem(r: RewardItem): boolean {
    return this.balance >= r.starCost;
  }

  /** 已攒到的星（点阵亮星） */
  filledStars(cost: number): number[] {
    const arr: number[] = [];
    const n = Math.min(Math.min(this.balance, cost), STAR_DOTS);
    for (let i = 0; i < n; i++) {
      arr.push(i);
    }
    return arr;
  }

  /** 还差的星（点阵暗星） */
  emptyStars(cost: number): number[] {
    const arr: number[] = [];
    const n = Math.min(cost, STAR_DOTS) - this.filledStars(cost).length;
    for (let i = 0; i < n; i++) {
      arr.push(i);
    }
    return arr;
  }

  /** 点阵折叠：成本超过展示上限时追加 ×N */
  starOverflow(cost: number): string {
    return cost > STAR_DOTS ? `×${cost}` : '';
  }

  tierColor(tier: number): ResourceColor {
    return tier === 1 ? $r('app.color.soft_yellow') : (tier === 2 ? $r('app.color.soft_pink') : $r('app.color.star_yellow'));
  }

  /** 家长长按 2 秒确认兑换 */
  onHoldTick(): void {
    if (this.confirmReward === null || this.celebrating) {
      return;
    }
    this.holdProgress += 0.05;
    if (this.holdProgress >= 1) {
      this.doRedeem(this.confirmReward);
      return;
    }
    setTimeout(() => {
      this.onHoldTick();
    }, 100);
  }

  async doRedeem(reward: RewardItem): Promise<void> {
    await RedemptionDao.redeem(SeedData.DEMO_KID_ID, reward);
    Sound.speak(`${reward.title}，心愿达成啦！`);
    this.celebrating = true;
    setTimeout(() => {
      this.confirmReward = null;
      this.celebrating = false;
      this.holdProgress = 0;
      this.reload();
    }, 1600);
  }

  closeSheet(): void {
    this.confirmReward = null;
    this.holdProgress = 0;
  }

  @Builder
  Header() {
    Row({ space: Space.MD }) {
      Column({ space: 2 }) {
        Text('我的星星')
          .fontSize(this.isSm() ? Type.HEADLINE : Type.DISPLAY)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
          .alignSelf(ItemAlign.Start)
        Text('点点星星，听一听有几颗')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })

      Row({ space: 6 }) {
        Text('🫙')
          .fontSize(this.isSm() ? 22 : 28)
        Text(`${this.balance}`)
          .fontSize(this.isSm() ? 22 : 28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.cocoa_text'))
      }
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.soft_blue'))
      .borderRadius(Radius.PILL)
      .onClick(() => {
        Sound.speak(`你有 ${this.balance} 颗星星`);
      })

      // 星星账本入口：每一颗星星的来龙去脉
      Text('📒 账本')
        .fontSize(this.isSm() ? Type.CAPTION : Type.BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.cocoa_text'))
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.soft_yellow'))
        .borderRadius(Radius.PILL)
        .onClick(() => {
          router.pushUrl({ url: 'pages/KidLedger' });
        })
    }
    .width('100%')
    .padding({ bottom: Space.XS })
  }

  @Builder
  Bottle() {
    Column({ space: 6 }) {
      // 瓶口/瓶颈
      Column()
        .width(this.isSm() ? 96 : 116)
        .height(26)
        .backgroundColor('#EAF6FF')
        .border({ width: 5, color: '#9CCBFF' })
        .borderRadius(13)

      Stack({ alignContent: Alignment.Bottom }) {
        // 水位：渐变蓝，水位=距离下一个心愿的进度
        Column()
          .width('84%')
          .height(`${Math.max(8, this.waterLevel() * 92)}%`)
          .backgroundColor('#5FA8FF')
          .linearGradient({
            angle: 180,
            colors: [['#9CD1FF', 0.0], ['#5FA8FF', 1.0]]
          })
          .opacity(0.55)
          .borderRadius(18)
          .animation({ duration: Motion.SLOW, curve: Curve.EaseInOut })

        // 星星珠 = 余额，一颗一颗从瓶底长出来；点击播报数量
        Column({ space: 2 }) {
          if (this.balance > 40) {
            Text(`✨ +${this.balance - 40}`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#E8A51F')
          }
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Center
          }) {
            ForEach(this.beadArray(), (i: number) => {
              Text('⭐')
                .fontSize(19)
                .rotate({ angle: i % 2 === 0 ? -10 : 10 })
                .margin(1)
            }, (i: number) => `${i}`)
          }
          .width('88%')
          .margin({ bottom: 10 })
        }
        .onClick(() => {
          Sound.speak(`你有 ${this.balance} 颗星星`); // 点星星听数量
        })
      }
      .width(this.isSm() ? 190 : (this.isLg() ? 260 : 220))
      .height(this.isSm() ? 250 : (this.isLg() ? 340 : 300))
      .backgroundColor('#F4FBFF')
      .border({ width: 6, color: '#9CCBFF' })
      .borderRadius({ topLeft: 56, topRight: 56, bottomLeft: 40, bottomRight: 40 })
      .shadow({ radius: 18, color: '#335FA8FF', offsetY: 8 })

      Text('星星瓶')
        .fontSize(this.isSm() ? Type.SUBTITLE : Type.TITLE)
        .fontColor($r('app.color.cocoa_text'))
    }
  }

  /** 心愿卡：大插画 + 名称 + ⭐ 点阵进度（亮=已攒、暗=还差） */
  @Builder
  WishCard(r: RewardItem) {
    Column({ space: this.isSm() ? 4 : 6 }) {
      HabitIcon({ icon: r.icon, iconSize: this.isSm() ? 64 : 84, radius: 20 })
      Text(r.title)
        .fontSize(this.isSm() ? Type.BODY : Type.SUBTITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.cocoa_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      // 星星进度：不识字也能看懂「还差几颗」
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.filledStars(r.starCost), (i: number) => {
          Text('★')
            .fontSize(this.isSm() ? 15 : 18)
            .fontColor($r('app.color.star_yellow'))
            .margin(1)
        }, (i: number) => `f${i}`)
        ForEach(this.emptyStars(r.starCost), (i: number) => {
          Text('★')
            .fontSize(this.isSm() ? 15 : 18)
            .fontColor($r('app.color.hairline'))
            .margin(1)
        }, (i: number) => `e${i}`)
        if (this.starOverflow(r.starCost) !== '') {
          Text(this.starOverflow(r.starCost))
            .fontSize(Type.MICRO)
            .fontColor($r('app.color.mist_gray'))
        }
      }
      .width('100%')
      Text(this.canRedeem(r) ? '可以换啦！' : '再攒几颗就能换')
        .fontSize(Type.CAPTION)
        .fontWeight(this.canRedeem(r) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.canRedeem(r) ? $r('app.color.done_green') : $r('app.color.mist_gray'))
    }
    .width('100%')
    .height(this.wishCardH())
    .justifyContent(FlexAlign.Center)
    .padding(Space.MD)
    .backgroundColor(this.tierColor(r.tier))
    .borderRadius(Radius.XL)
    .border({
      width: this.canRedeem(r) ? 4 : 2,
      color: this.canRedeem(r) ? $r('app.color.brand_orange') : $r('app.color.hairline')
    })
    .shadow(this.canRedeem(r) ? Elevation.FLOAT : Elevation.CARD)
    .opacity(this.canRedeem(r) ? 1.0 : 0.62)
    // 可兑换的心愿轻轻呼吸，吸引宝宝去点
    .scale(this.canRedeem(r) && this.pulse ? { x: 1.03, y: 1.03 } : { x: 1.0, y: 1.0 })
    .animation({ duration: Motion.BASE, curve: Curve.EaseInOut })
    .onClick(() => {
      if (this.canRedeem(r)) {
        Sound.speak(`${r.title}，可以换啦`);
        this.confirmReward = r;
        this.holdProgress = 0;
      }
    })
  }

  @Builder
  WishSection() {
    Column({ space: Space.SM }) {
      SectionTitle({
        text: `想兑换的心愿（${this.rewards.length}）`,
        textSize: this.isSm() ? Type.SUBTITLE : Type.TITLE
      })
      if (this.rewards.length === 0) {
        Text('还没有心愿，让爸爸妈妈在心愿商店里添加吧')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
      } else {
        // 官方一多栅格：手机 1 列、平板 2 列、大屏 2 列（右侧已与星星瓶并排，故大屏仍 2 列），
        // 框架自动等宽折行，不再手算百分比/行，规避 Scroll 内测量坍缩
        GridRow({ columns: 12, gutter: this.isSm() ? Space.MD : Space.LG }) {
          ForEach(this.rewards, (r: RewardItem) => {
            GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 6 } }) {
              this.WishCard(r)
            }
            .constraintSize({ minWidth: 0 })
          }, (r: RewardItem) => `${r.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /** 收集卡册：手机横向滑动，大屏折行铺满 */
  @Builder
  CardAlbum() {
    Column({ space: Space.SM }) {
      SectionTitle({
        text: `收集卡册（${this.cards.length}）`,
        textSize: this.isSm() ? Type.SUBTITLE : Type.TITLE
      })
      if (this.cards.length === 0) {
        Text('兑换的心愿会变成卡片收集在这里')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.mist_gray'))
          .alignSelf(ItemAlign.Start)
      } else {
        Flex({
          direction: FlexDirection.Row,
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start
        }) {
          ForEach(this.cards, (c: RedemptionCard) => {
            Column({ space: 4 }) {
              HabitIcon({ icon: c.icon, iconSize: this.isSm() ? 48 : 56, radius: 12 })
              Text(c.title)
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.cocoa_text'))
                .maxLines(1)
              Text(c.date)
                .fontSize(Type.MICRO)
                .fontColor($r('app.color.mist_gray'))
            }
            .width(this.tileWidth())
            .margin({ right: '2%', bottom: Space.MD })
            .padding(Space.SM + 2)
            .backgroundColor(Color.White)
            .borderRadius(Radius.MD)
            .border({ width: 2, color: $r('app.color.star_yellow') })
            .shadow(Elevation.CARD)
          }, (c: RedemptionCard) => `${c.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /** 相册每行列数：手机 2，平板 3，大屏 4（像日记一样逐张铺开） */
  albumCols(): number {
    if (this.isLg()) {
      return 4;
    }
    return this.isSm() ? 2 : 3;
  }

  /** 主动分行，避免 Flex wrap 在 Scroll 内的测量问题 */
  albumRows(list: PhotoEntry[]): PhotoEntry[][] {
    const cols = this.albumCols();
    const rows: PhotoEntry[][] = [];
    for (let i = 0; i < list.length; i += cols) {
      const slice: PhotoEntry[] = [];
      for (let j = i; j < Math.min(i + cols, list.length); j++) {
        slice.push(list[j]);
      }
      rows.push(slice);
    }
    return rows;
  }

  /** 月份标签：'2026-10' → '2026 年 10 月' */
  monthLabelOf(key: string): string {
    const parts = key.split('-');
    if (parts.length === 2) {
      return `${parts[0]} 年 ${Number(parts[1])} 月`;
    }
    return key;
  }

  /** 按月分章：与时光日志一致的记忆编排（最新月份在前） */
  photoGroups(): MonthGroup[] {
    const list = this.filteredPhotos();
    const map: Map<string, PhotoEntry[]> = new Map();
    for (const p of list) {
      const key = p.date.length >= 7 ? p.date.substring(0, 7) : p.date;
      const arr = map.get(key);
      if (arr === undefined) {
        map.set(key, [p]);
      } else {
        arr.push(p);
      }
    }
    const groups: MonthGroup[] = [];
    for (const key of map.keys()) {
      const arr = map.get(key);
      groups.push({ key: key, label: this.monthLabelOf(key), photos: arr === undefined ? [] : arr } as MonthGroup);
    }
    return groups;
  }

  weekdayOf(date: string): string {
    const d = new Date(`${date}T00:00:00`);
    return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][d.getDay()];
  }

  ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 保存到系统相册（弹窗授权，免相册权限） */
  async saveToGallery(p: PhotoEntry): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    const absPath = `${this.ctx().filesDir}/${p.photoPath}`;
    const result = await GallerySave.save(this.ctx(), absPath, p.title, 'jpg');
    Sound.speak(result.message);
    this.saving = false;
  }

  /** 系统分享面板（ShareKit）：图片用 uri + 精细化 utd */
  share(p: PhotoEntry): void {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.JPEG,
        uri: PhotoCapture.toUri(this.ctx(), p.photoPath)
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      controller.show(this.ctx(), {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      Sound.speak('这台设备暂不支持分享');
    }
  }

  /**
   * 生成分享图并保存到系统相册。
   * 用离屏画布把【这一天】的全部照片合成成拼图式分享卡，
   * 并根据当天完成的任务生成一句评价，再经 PhotoAccessHelper 存进本地相册。
   */
  async makeShareCard(p: PhotoEntry): Promise<void> {
    if (this.sharing) {
      return;
    }
    if (this.photos.length === 0) {
      Sound.speak('还没有照片可以分享哦');
      return;
    }
    this.sharing = true;
    Sound.speak('正在生成成长分享图');
    try {
      // ① 这一天全部照片（拼图模式）
      const tiles: ShareTile[] = [];
      for (const item of this.photos) {
        if (item.date === p.date) {
          // 显式声明类型再 push：ArkTS 不允许无类型对象字面量（arkts-no-untyped-obj-literals）
          const tile: ShareTile = {
            path: `${this.ctx().filesDir}/${item.photoPath}`,
            taskName: item.title
          };
          tiles.push(tile);
        }
      }
      // ② 当天完成的任务 → 评价
      const kidId = SeedData.DEMO_KID_ID;
      const doneIds = await CheckinDao.todayDoneTaskIds(kidId, p.date);
      const doneNames: string[] = [];
      for (const t of this.allTasks) {
        if (doneIds.has(t.id)) {
          doneNames.push(t.title);
        }
      }
      const review = ShareCard.evaluate(doneNames.length, doneNames);
      const title = `成长时光 · ${this.prettyDate(p.date)}`;
      const subtitle = doneNames.length > 0
        ? `今天完成了 ${doneNames.length} 个好习惯`
        : `这一天留下了 ${tiles.length} 张照片`;
      const card = await ShareCard.composeDay(this.ctx(), tiles, title, review, subtitle);
      if (card === null) {
        Sound.speak('生成失败，请稍后再试');
        this.sharing = false;
        return;
      }
      // 存进系统相册（弹窗授权，免相册权限）
      const result = await GallerySave.save(this.ctx(), card.path, title, 'png');
      Sound.speak(result.ok ? '分享图已保存到相册' : result.message);
    } catch (err) {
      Sound.speak('生成失败，请稍后再试');
    }
    this.sharing = false;
  }

  /**
   * 生成【最近一天】的拼图分享图（页面一级入口用）。
   * photos 已按时间倒序，第一条就是最近有照片的那天。
   */
  async makeLatestShareCard(): Promise<void> {
    if (this.sharing) {
      return;
    }
    if (this.photos.length === 0) {
      Sound.speak('还没有照片可以分享哦');
      return;
    }
    await this.makeShareCard(this.photos[0]);
  }

  /** 日期友好文案：2026-10-31 → 10 月 31 日 */
  prettyDate(date: string): string {
    const parts = date.split('-');
    if (parts.length >= 3) {
      return `${Number(parts[1])} 月 ${Number(parts[2])} 日`;
    }
    return date;
  }

  /** 月度分章标题：像翻开的日记本每一章开头的日期 */
  @Builder
  MonthDivider(label: string, count: number) {
    Row({ space: Space.SM }) {
      Column()
        .width(4)
        .height(22)
        .borderRadius(2)
        .backgroundColor($r('app.color.brand_orange'))
      Text(label)
        .fontSize(this.isSm() ? Type.SUBTITLE : Type.TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.cocoa_text'))
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
      Text(`${count} 张`)
        .fontSize(Type.CAPTION)
        .fontColor($r('app.color.mist_gray'))
    }
    .width('100%')
    .padding({ top: Space.SM, bottom: Space.XS })
  }

  /** 单张回忆卡片：照片 + 日记式日期 + 任务名，点按全屏查看，长按弹出菜单 */
  @Builder
  MemoryTile(p: PhotoEntry) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(PhotoCapture.toUri(this.ctx(), p.photoPath))
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
          .borderRadius(14)
          .onClick(() => {
            const flat = this.filteredPhotos();
            const idx = flat.findIndex((item: PhotoEntry) => item.id === p.id);
            if (idx >= 0) {
              this.previewPos = idx;
              this.previewOpen = true;
            }
          })
      }
      .width('100%')

      Row({ space: 4 }) {
        Text('📅')
          .fontSize(Type.MICRO)
        Text(`${p.date.slice(5)} ${this.weekdayOf(p.date)}`)
          .fontSize(Type.MICRO)
          .fontColor($r('app.color.mist_gray'))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .maxLines(1)
      }
      .width('100%')
      Text(p.title === '' ? this.categoryOf(p.taskId) : p.title)
        .fontSize(Type.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.cocoa_text'))
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.hairline') })
    .shadow(Elevation.CARD)
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.menuPhoto = p;
          this.menuShown = true;
        })
    )
    .bindPopup(this.menuShown, {
      builder: this.TileMenu,
      placement: Placement.Bottom,
      mask: true
    })
  }

  /** 长按弹出的回忆操作菜单：保存 / 分享 / 生成分享图 / 删除 */
  @Builder
  TileMenu() {
    Column({ space: 0 }) {
      if (this.menuPhoto !== null) {
        Text('💾 保存到相册')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.cocoa_text'))
          .width('100%')
          .padding({ top: 14, bottom: 14, left: 18, right: 18 })
          .onClick(() => {
            this.saveToGallery(this.menuPhoto as PhotoEntry);
            this.menuPhoto = null;
            this.menuShown = false;
          })
        Divider()
          .color($r('app.color.hairline'))
        Text('📤 分享给家人')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.cocoa_text'))
          .width('100%')
          .padding({ top: 14, bottom: 14, left: 18, right: 18 })
          .onClick(() => {
            this.share(this.menuPhoto as PhotoEntry);
            this.menuPhoto = null;
            this.menuShown = false;
          })
        Divider()
          .color($r('app.color.hairline'))
        Text(this.sharing ? '🎨 正在生成…' : '🎨 生成分享图存相册')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.cocoa_text'))
          .width('100%')
          .padding({ top: 14, bottom: 14, left: 18, right: 18 })
          .onClick(() => {
            this.makeShareCard(this.menuPhoto as PhotoEntry);
            this.menuPhoto = null;
            this.menuShown = false;
          })
        Divider()
          .color($r('app.color.hairline'))
        Text('🗑 删除这张')
          .fontSize(Type.BODY)
          .fontColor($r('app.color.danger'))
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .padding({ top: 14, bottom: 14, left: 18, right: 18 })
          .onClick(() => {
            this.deletePhoto(this.menuPhoto as PhotoEntry);
            this.menuPhoto = null;
            this.menuShown = false;
          })
      }
    }
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow(Elevation.FLOAT)
  }

  /**
   * 手机端：星星瓶 / 成长时光 / 兑换心愿 三分区横向滑动切换。
   *
   * 交互要点：
   *  · Swiper 天然是整页吸附（松手自动对齐到最近一页），满足"吸附效果"
   *  · nextMargin 让下一屏露出一角 → 用户一眼看出"还能往右滑"
   *  · 顶部有分段标签（可点直接跳页），标签高亮跟随当前页
   *  · 底部圆点指示器显示页码，滑动时实时更新
   */
  @Builder
  MobilePages() {
    Column({ space: Space.SM }) {
      // 分段标签：可点直接跳页，也显示当前所在分区
      Row({ space: 6 }) {
        Text('🫙 星星瓶')
          .fontSize(Type.CAPTION)
          .fontWeight(this.pageIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.pageIndex === 0 ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.pageIndex === 0 ? $r('app.color.brand_orange') : '#33FF8A3D')
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.swiperController.changeIndex(0);
          })
        Text('📷 成长时光')
          .fontSize(Type.CAPTION)
          .fontWeight(this.pageIndex === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.pageIndex === 1 ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.pageIndex === 1 ? $r('app.color.brand_orange') : '#33FF8A3D')
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.swiperController.changeIndex(1);
          })
        Text('🎁 兑换心愿')
          .fontSize(Type.CAPTION)
          .fontWeight(this.pageIndex === 2 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.pageIndex === 2 ? Color.White : $r('app.color.cocoa_text'))
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .backgroundColor(this.pageIndex === 2 ? $r('app.color.brand_orange') : '#33FF8A3D')
          .borderRadius(Radius.PILL)
          .onClick(() => {
            this.swiperController.changeIndex(2);
          })
      }
      .width('100%')

      Swiper(this.swiperController) {
        // 第 1 屏：星星瓶 + 奖励卡册
        Column({ space: Space.MD }) {
          this.Bottle()
          this.CardAlbum()
        }
        .width('100%')

        // 第 2 屏：成长时光
        Column() {
          this.PhotoAlbum()
        }
        .width('100%')

        // 第 3 屏：兑换心愿
        Column() {
          this.WishSection()
        }
        .width('100%')
      }
      .index(this.pageIndex)
      .onChange((index: number) => {
        this.pageIndex = index;
      })
      // 不设 nextMargin：那样会把【未展示的下一个 tab 内容】露出来，看着像串页。
      // 「可横滑」的感知改由顶部分段标签高亮 + 底部圆点指示器承担。
      .duration(280)
      .curve(Curve.EaseOut)
      .loop(false)
      .indicator(new DotIndicator()
        .itemWidth(6)
        .itemHeight(6)
        .selectedItemWidth(8)
        .selectedItemHeight(8)
        .color('#33FF8A3D')
        .selectedColor($r('app.color.brand_orange')))
      .width('100%')
    }
    .width('100%')
  }

  /** 成长时光：按月分章，每章照片像日记一样排列，点按进入大图 */
  @Builder
  PhotoAlbum() {
    Column({ space: Space.SM }) {
      Row({ space: Space.SM }) {
        SectionTitle({
          text: `📷 成长时光（${this.photos.length}）`,
          textSize: this.isSm() ? Type.SUBTITLE : Type.TITLE
        })
          .layoutWeight(1)
        // 时光日志入口：更完整的时间轴浏览
        Text('时光日志 ›')
          .fontSize(Type.CAPTION)
          .fontColor($r('app.color.cocoa_text'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.soft_yellow'))
          .borderRadius(Radius.PILL)
          .onClick(() => {
            router.pushUrl({ url: 'pages/KidTimeline' });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 拼图分享一级入口：不用先点开某张照片，直接生成整日拼图存相册
      if (this.photos.length > 0) {
        AppButton({
          label: this.sharing ? '🎨 正在生成拼图…' : '🎨 生成今天的成长拼图',
          variant: AppButtonVariant.Primary,
          btnHeight: 48,
          fontSize: Type.BODY,
          block: true,
          isEnabled: !this.sharing,
          onTap: () => {
            this.makeLatestShareCard();
          }
        })
          .width('100%')
      }

      if (this.photos.length === 0) {
        Column({ space: 8 }) {
          Text('📷')
            .fontSize(48)
          Text('还没有照片')
            .fontSize(Type.TITLE)
            .fontColor($r('app.color.cocoa_text'))
          Text('拍照打卡的照片会像日记一样，按月收藏在这里')
            .fontSize(Type.BODY)
            .fontColor($r('app.color.mist_gray'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 60, bottom: 60 })
      } else {
        // 分类筛选
        Scroll() {
          Row({ space: Space.SM }) {
            ForEach(this.photoCategories(), (cat: string) => {
              Text(cat)
                .fontSize(Type.BODY)
                .fontColor(this.photoCat === cat ? Color.White : $r('app.color.cocoa_text'))
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .backgroundColor(this.photoCat === cat ? $r('app.color.brand_orange') : Color.White)
                .borderRadius(Radius.PILL)
                .border({
                  width: 2,
                  color: this.photoCat === cat ? $r('app.color.brand_orange') : $r('app.color.hairline')
                })
                .onClick(() => {
                  this.photoCat = cat;
                })
            }, (cat: string) => cat)
          }
          .padding({ left: Space.XS, right: Space.XS })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')

        // 时光日志式：按月分章，每章照片像日记一样排列
        Column({ space: Space.LG }) {
          ForEach(this.photoGroups(), (g: MonthGroup) => {
            Column({ space: Space.SM }) {
              this.MonthDivider(g.label, g.photos.length)
              ForEach(this.albumRows(g.photos), (row: PhotoEntry[]) => {
                Row({ space: Space.SM }) {
                  ForEach(row, (p: PhotoEntry) => {
                    Column() {
                      this.MemoryTile(p)
                    }
                    .layoutWeight(1)
                    .constraintSize({ minWidth: 0 })
                  }, (p: PhotoEntry) => `${p.id}`)
                }
                .width('100%')
              }, (row: PhotoEntry[]) => row.map((p: PhotoEntry) => p.id).join('-'))
            }
            .width('100%')
          }, (g: MonthGroup) => g.key)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /** 大图浏览覆盖层（统一底卡样式）：Swiper 左右滑 + 底部信息/操作卡片 */
  @Builder
  PhotoViewer() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩：点空白关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#E6000000')
        .onClick(() => {
          this.previewOpen = false;
        })

      Column({ space: Space.SM }) {
        // 顶部关闭
        Row() {
          Text('✕')
            .fontSize(20)
            .fontColor(Color.White)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.previewOpen = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)

        Swiper() {
          ForEach(this.filteredPhotos(), (p: PhotoEntry) => {
            Image(PhotoCapture.toUri(this.ctx(), p.photoPath))
              // 铺满 Swiper 给出的可用空间（用 Contain 保持比例，不裁切）
              // 不用 aspectRatio(1)：那会把图强制成正方形，无法占满屏幕高度
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          }, (p: PhotoEntry) => `${p.id}`)
        }
        .index(this.previewPos)
        .onChange((index: number) => {
          this.previewPos = index;
        })
        .width('100%')
        .layoutWeight(1)
        .indicator(false)
        .loop(false)

        // 底部信息 + 操作：统一的圆角底卡
        Column({ space: Space.SM }) {
          if (this.previewPos >= 0 && this.previewPos < this.filteredPhotos().length) {
            Column({ space: 4 }) {
              Text(this.filteredPhotos()[this.previewPos].title)
                .fontSize(Type.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(`${this.filteredPhotos()[this.previewPos].date} · ${this.weekdayOf(this.filteredPhotos()[this.previewPos].date)}`)
                .fontSize(Type.BODY)
                .fontColor('#CCFFFFFF')
            }
            .width('100%')
          }

          Row({ space: Space.SM }) {
            AppButton({
              label: this.saving ? '保存中…' : '💾 存到相册',
              variant: AppButtonVariant.Soft,
              btnHeight: 48,
              fontSize: Type.BODY,
              onTap: () => {
                if (this.previewPos >= 0 && this.previewPos < this.filteredPhotos().length) {
                  this.saveToGallery(this.filteredPhotos()[this.previewPos]);
                }
              }
            })
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
            AppButton({
              label: '📤 分享给家人',
              variant: AppButtonVariant.Outline,
              btnHeight: 48,
              fontSize: Type.BODY,
              onTap: () => {
                if (this.previewPos >= 0 && this.previewPos < this.filteredPhotos().length) {
                  this.share(this.filteredPhotos()[this.previewPos]);
                }
              }
            })
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: Space.MD, bottom: this.isSm() ? 28 : Space.LG, left: Space.MD, right: Space.MD })
        .backgroundColor('#99000000')
        .borderRadius({ topLeft: 24, topRight: 24 })
      }
      // 内容列：宽屏限宽居中（超宽屏不无限拉伸），手机满宽
      .width('100%')
      .constraintSize({ maxWidth: SheetFit.MAX_W_FULL })
      .alignItems(HorizontalAlign.Center)
      // 顶部避让状态栏、底部避让导航条
      .padding({
        left: Space.MD,
        right: Space.MD,
        top: SheetFit.padTop(this.safeAreaTop),
        bottom: SheetFit.padBottom(this.safeAreaBottom)
      })
      .height('100%')
    }
    // 【铺满全设备】ignoreLayoutSafeArea + LayoutPolicy.matchParent 两者缺一不可
    .width(LayoutPolicy.matchParent)
    .height(LayoutPolicy.matchParent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  /** 兑换确认：居中卡片 + 半透明遮罩，家长长按 2 秒
   *  · 多设备适配：卡片宽 = 窄屏 92% / 宽屏限宽 520；最大高度不超过可用高度，超出内部滚动
   *  · 顶部避让状态栏、底部避让导航条 */
  @Builder
  RedeemSheet(reward: RewardItem) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          if (!this.celebrating) {
            this.closeSheet();
          }
        })

      Scroll() {
        Column({ space: Space.MD }) {
        if (this.celebrating) {
          Text('🎉')
            .fontSize(72)
          Text('心愿达成！')
            .fontSize(Type.DISPLAY)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.done_green'))
        } else {
          Text('兑换心愿')
            .fontSize(this.isSm() ? Type.TITLE : Type.HEADLINE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.cocoa_text'))

          Row({ space: Space.MD }) {
            HabitIcon({ icon: reward.icon, iconSize: this.isSm() ? 88 : 108, radius: 24 })
            Text(reward.title)
              .fontSize(this.isSm() ? Type.TITLE : Type.HEADLINE)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.cocoa_text'))
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

          // 花掉 / 剩余：点阵展示，不出现数字压力
          Column({ space: 6 }) {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Text('要花掉')
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
              ForEach(this.filledStars(reward.starCost), (i: number) => {
                Text('★')
                  .fontSize(16)
                  .fontColor($r('app.color.star_yellow'))
                  .margin(1)
              }, (i: number) => `c${i}`)
            }
            .width('100%')
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Text('瓶里还剩')
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
              ForEach(this.filledStars(this.balance - reward.starCost >= 0 ? this.balance - reward.starCost : 0),
                (i: number) => {
                  Text('★')
                    .fontSize(16)
                    .fontColor($r('app.color.star_yellow'))
                    .margin(1)
                }, (i: number) => `l${i}`)
            }
            .width('100%')
          }
          .alignSelf(ItemAlign.Start)

          // 家长长按 2 秒确认（UI 规范 4.4 / 9.1：儿童端唯一长按入口）
          Column({ space: Space.SM }) {
            Progress({ value: this.holdProgress * 100, total: 100, type: ProgressType.Capsule })
              .width('100%')
              .color($r('app.color.done_green'))
            Button('👆 家长按住 2 秒')
              .width('100%')
              .height(72)
              .fontSize(Type.SUBTITLE)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.brand_orange'))
              .borderRadius(Radius.PILL)
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.holdProgress = 0;
                  this.onHoldTick();
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.holdProgress = 0;
                }
              })
          }
          .width('100%')

          AppButton({
            label: '先不换',
            variant: AppButtonVariant.Soft,
            btnHeight: 52,
            fontSize: Type.BODY,
            block: true,
            onTap: () => {
              this.closeSheet();
            }
          })
        }
        }
        // 卡片宽度：窄屏 92%，宽屏限宽 520（超宽屏不无限拉伸）
        .width(SheetFit.cardWidth(this.isSm(), this.screenW))
        // 最大高度不超过可用高度，超出由外层 Scroll 滚动
        .constraintSize({ maxHeight: this.sheetMaxHeight() })
        .padding(Space.XL)
        .backgroundColor(Color.White)
        .borderRadius(32)
        .shadow(Elevation.FLOAT)
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .align(Alignment.Center)
      // 上下避让系统栏，保证卡片在刘海屏/手势条屏上完整可见
      .padding({
        top: SheetFit.padTop(this.safeAreaTop),
        bottom: SheetFit.padBottom(this.safeAreaBottom)
      })
    }
    // 【铺满全设备】ignoreLayoutSafeArea + LayoutPolicy.matchParent 两者缺一不可
    .width(LayoutPolicy.matchParent)
    .height(LayoutPolicy.matchParent)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: this.isSm() ? Space.MD : Space.LG }) {
          this.Header()

          if (this.isSm()) {
            // 手机端：三个分区横向滑动切换（Swiper 自带分页吸附）
            //   · itemSpace + nextMargin 让下一屏露出一角 → 用户能感知"可横滑"
            //   · indicator 用 DigitIndicator 显示页码，切换时看得见自己在第几屏
            this.MobilePages()
          } else {
            // 平板/PC：左右分栏（左星星瓶、右心愿卡网格）
            Row({ space: Space.LG }) {
              Column({ space: Space.SM }) {
                this.Bottle()
              }
              .width(this.isLg() ? 320 : 260)

              Column() {
                this.WishSection()
              }
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }

          if (!this.isSm()) {
            // 平板/PC：相册与卡册在分栏下方平铺（手机端已在 Swiper 内）
            this.CardAlbum()
            this.PhotoAlbum()
          }

          AppButton({
            label: '← 返回',
            variant: AppButtonVariant.Soft,
            btnHeight: 52,
            fontSize: Type.BODY,
            onTap: () => {
              router.back();
            }
          })
            .width(this.isSm() ? '50%' : 220)
            .alignSelf(ItemAlign.Center)
        }
        .width('100%')
        .padding({ left: Space.XL, right: Space.XL, top: this.safeAreaTop + 12, bottom: this.safeAreaBottom + Space.XL })
        .backgroundColor($r('app.color.cream_background'))
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.confirmReward !== null) {
        this.RedeemSheet(this.confirmReward as RewardItem);
      }
    }
    .width('100%')
    .height('100%')
    .bindContentCover(this.previewOpen, this.PhotoViewer(), {
      backgroundColor: Color.Black,
      onDisappear: () => { this.previewOpen = false; }
    })
  }
}

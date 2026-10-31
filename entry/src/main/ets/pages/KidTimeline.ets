import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { PhotoEntry, TaskItem } from '../commons/models/Models';
import { CheckinDao, TaskDao } from '../commons/db/Dao';
import { PhotoCapture } from '../commons/utils/PhotoCapture';
import { ShareCard, ShareTile } from '../commons/utils/ShareCard';
import { GallerySave } from '../commons/utils/GallerySave';
import { SeedData } from '../commons/db/SeedData';
import { AppButton, AppButtonVariant } from '../commons/components/AppButton';
import { SectionTitle } from '../commons/components/Primitives';
import { Breakpoint } from '../commons/utils/BreakpointSystem';
import { Sound } from '../commons/utils/Sound';
import { SheetFit } from '../commons/utils/SheetFit';
import { Space, Type } from '../commons/theme/Theme';

/** 一个月的分组：标签 + 照片列表 */
interface MonthGroup {
  key: string;
  label: string;
  photos: PhotoEntry[];
}

/**
 * 儿童端 · 成长时间轴：打卡照片按月分组，点开大图左右滑动浏览。
 * 大图页支持：保存到系统相册（PhotoAccessHelper，无需存储权限）、系统分享面板。
 * 全部本地完成，不涉及服务器。
 */
@Entry
@Component
struct KidTimeline {
  @StorageProp('currentBreakpoint') breakpoint: Breakpoint = 'sm';
  /** 系统避让区高度（vp）：弹窗按可用空间自适应 */
  @StorageProp('safeAreaTop') safeAreaTop: number = 28;
  @StorageProp('safeAreaBottom') safeAreaBottom: number = 0;
  @State groups: MonthGroup[] = [];
  /** 全部照片（大图浏览用，与分组同一份数据） */
  @State photos: PhotoEntry[] = [];
  /** 大图浏览是否打开（由 bindContentCover 全模态组件驱动） */
  @State isViewerOpen: boolean = false;
  /** Swiper 当前页（随滑动更新，信息行跟着切换） */
  @State viewerPos: number = 0;
  @State saving: boolean = false;
  /** 正在生成分享图（合成 + 存相册是异步过程，需要 loading 反馈） */
  @State sharing: boolean = false;
  /** 全部任务（用于按天查「当天完成了哪些任务」生成评价） */
  @State allTasks: TaskItem[] = [];

  aboutToAppear(): void {
    Sound.init();
    this.reload();
  }

  async reload(): Promise<void> {
    const kidId = SeedData.DEMO_KID_ID;
    const allTasks = await TaskDao.listActive(kidId);
    this.allTasks = allTasks;
    const photos = await CheckinDao.recentPhotos(kidId, 500);
    for (const p of photos) {
      const t = allTasks.find((item) => item.id === p.taskId);
      p.title = t ? t.title : '打卡留念';
    }
    this.photos = photos;
    const map: Map<string, PhotoEntry[]> = new Map();
    for (const p of photos) {
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
      const parts = key.split('-');
      const label = parts.length === 2 ? `${parts[0]} 年 ${Number(parts[1])} 月` : key;
      const arr = map.get(key);
      groups.push({ key: key, label: label, photos: arr === undefined ? [] : arr } as MonthGroup);
    }
    this.groups = groups;
  }

  isSm(): boolean {
    return this.breakpoint === 'sm';
  }

  /** 每行 3 张缩略图（主动分行） */
  photoRows(list: PhotoEntry[]): PhotoEntry[][] {
    const rows: PhotoEntry[][] = [];
    for (let i = 0; i < list.length; i += 3) {
      const slice: PhotoEntry[] = [];
      for (let j = i; j < Math.min(i + 3, list.length); j++) {
        slice.push(list[j]);
      }
      rows.push(slice);
    }
    return rows;
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
   * 用离屏画布把照片 + 标题/日期/装饰合成成一张竖版分享卡，
   * 再经 GallerySave（弹窗授权，免相册权限）存进本地相册（全程本地，不上传）。
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
      // ① 取出【这一天】的全部照片（拼图模式，不是单张）
      const dayPhotos: PhotoEntry[] = [];
      for (const item of this.photos) {
        if (item.date === p.date) {
          dayPhotos.push(item);
        }
      }
      const tiles: ShareTile[] = [];
      for (const item of dayPhotos) {
        // 显式声明类型再 push：ArkTS 不允许无类型对象字面量（arkts-no-untyped-obj-literals）
        const tile: ShareTile = {
          path: `${this.ctx().filesDir}/${item.photoPath}`,
          taskName: item.title
        };
        tiles.push(tile);
      }

      // ② 查出这一天【完成的任务】，用于生成评价
      const kidId = SeedData.DEMO_KID_ID;
      const doneIds = await CheckinDao.todayDoneTaskIds(kidId, p.date);
      const doneNames: string[] = [];
      for (const t of this.allTasks) {
        if (doneIds.has(t.id)) {
          doneNames.push(t.title);
        }
      }
      const review = ShareCard.evaluate(doneNames.length, doneNames);

      // ③ 合成拼图分享卡
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
   * 生成【最近一天】的拼图分享图（页面顶部一级入口用）。
   * 取有照片的最新一天，合成后保存到相册。
   */
  async makeLatestShareCard(): Promise<void> {
    if (this.sharing || this.photos.length === 0) {
      if (this.photos.length === 0) {
        Sound.speak('还没有照片可以分享哦');
      }
      return;
    }
    // photos 已按时间倒序（recentPhotos orderByDesc），第一条就是最近一天
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
          this.isViewerOpen = false;
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
              this.isViewerOpen = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)

        Swiper() {
          ForEach(this.photos, (p: PhotoEntry) => {
            Image(PhotoCapture.toUri(this.ctx(), p.photoPath))
              // 铺满 Swiper 给出的可用空间（用 Contain 保持比例，不裁切）
              // 不用 aspectRatio(1)：那会把图强制成正方形，无法占满屏幕高度
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          }, (p: PhotoEntry) => `${p.id}`)
        }
        .index(this.viewerPos)
        .onChange((index: number) => {
          this.viewerPos = index;
        })
        .width('100%')
        .layoutWeight(1)
        .indicator(false)
        .loop(false)

        // 底部信息 + 操作：统一的圆角底卡
        Column({ space: Space.SM }) {
          if (this.viewerPos >= 0 && this.viewerPos < this.photos.length) {
            Column({ space: 4 }) {
              Text(this.photos[this.viewerPos].title)
                .fontSize(Type.TITLE)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text(`${this.photos[this.viewerPos].date} · ${this.weekdayOf(this.photos[this.viewerPos].date)}`)
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
                if (this.viewerPos >= 0 && this.viewerPos < this.photos.length) {
                  this.saveToGallery(this.photos[this.viewerPos]);
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
                if (this.viewerPos >= 0 && this.viewerPos < this.photos.length) {
                  this.share(this.photos[this.viewerPos]);
                }
              }
            })
              .layoutWeight(1)
              .constraintSize({ minWidth: 0 })
          }
          .width('100%')

          // 生成分享图（离屏画布合成 → 存本地相册），独占一行避免挤压上方按钮
          AppButton({
            label: this.sharing ? '🎨 正在生成…' : '🎨 生成分享图存相册',
            variant: AppButtonVariant.Soft,
            btnHeight: 48,
            fontSize: Type.BODY,
            block: true,
            isEnabled: !this.sharing,
            onTap: () => {
              if (this.viewerPos >= 0 && this.viewerPos < this.photos.length) {
                this.makeShareCard(this.photos[this.viewerPos]);
              }
            }
          })
            .width('100%')
        }
        .width('100%')
        .padding({ top: Space.MD, bottom: this.isSm() ? 28 : Space.LG, left: Space.MD, right: Space.MD })
        .backgroundColor('#99000000')
        .borderRadius({ topLeft: 24, topRight: 24 })
      }
      // 内容列：宽屏限宽居中（超宽屏不无限拉伸），手机满宽
      .width('100%')
      // 关键：必须有确定高度，内部的 layoutWeight(1) 才有参照，
      // 否则图片区高度塌陷、大图撑不满屏幕
      .height('100%')
      .constraintSize({ maxWidth: SheetFit.MAX_W_FULL })
      .alignItems(HorizontalAlign.Center)
      // 顶部避让状态栏、底部避让导航条
      .padding({
        left: Space.MD,
        right: Space.MD,
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
      Column() {
        Scroll() {
          Column({ space: Space.SM }) {
            Column({ space: 2 }) {
              Text('成长时间轴')
                .fontSize(this.isSm() ? Type.HEADLINE : Type.DISPLAY)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.cocoa_text'))
                .alignSelf(ItemAlign.Start)
              Text(`${this.photos.length} 张照片，记录着每一次坚持`)
                .fontSize(Type.CAPTION)
                .fontColor($r('app.color.mist_gray'))
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')

            // 拼图分享一级入口：不必先点开某张照片就能生成整日拼图并存相册
            if (this.photos.length > 0) {
              AppButton({
                label: this.sharing ? '🎨 正在生成拼图…' : '🎨 生成今天的成长拼图',
                variant: AppButtonVariant.Primary,
                btnHeight: 52,
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
                Text('打卡时拍张照片，就会出现在这里')
                  .fontSize(Type.BODY)
                  .fontColor($r('app.color.mist_gray'))
              }
              .width('100%')
              .padding({ top: 80, bottom: 80 })
            } else {
              ForEach(this.groups, (g: MonthGroup) => {
                Column({ space: Space.SM }) {
                  SectionTitle({ text: g.label, textSize: Type.BODY })
                  ForEach(this.photoRows(g.photos), (row: PhotoEntry[]) => {
                    Row({ space: Space.SM }) {
                      ForEach(row, (p: PhotoEntry) => {
                        Column() {
                          Image(PhotoCapture.toUri(this.ctx(), p.photoPath))
                            .width('100%')
                            .aspectRatio(1)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(12)
                        }
                        .layoutWeight(1)
                        .constraintSize({ minWidth: 0 })
                        .onClick(() => {
                          const idx = this.photos.findIndex((item: PhotoEntry) => item.id === p.id);
                          if (idx >= 0) {
                            this.viewerPos = idx;
                            this.isViewerOpen = true;
                          }
                        })
                      }, (p: PhotoEntry) => `${p.id}`)
                    }
                    .width('100%')
                  }, (row: PhotoEntry[]) => row.map((p: PhotoEntry) => p.id).join('-'))
                }
                .width('100%')
              }, (g: MonthGroup) => g.key)
            }

            AppButton({
              label: '← 返回',
              variant: AppButtonVariant.Soft,
              btnHeight: 48,
              onTap: () => {
                this.getUIContext().getRouter().back();
              }
            })
              .width(this.isSm() ? '100%' : 320)
              .margin({ top: Space.SM })
          }
          .width('100%')
          .constraintSize({ maxWidth: 640 })
          .padding({ left: 24, right: 24, top: this.safeAreaTop + 12, bottom: this.safeAreaBottom + 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.cream_background'))
    }
    .bindContentCover(this.isViewerOpen, this.PhotoViewer(), {
      backgroundColor: Color.Black,
      onDisappear: () => { this.isViewerOpen = false; }
    })
    .width('100%')
    .height('100%')
  }
}

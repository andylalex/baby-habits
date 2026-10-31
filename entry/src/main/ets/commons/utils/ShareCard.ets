import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'ShareCard';

/** 分享图合成结果 */
export interface ShareCardResult {
  /** 沙盒绝对路径（.png） */
  path: string;
  /** 图片宽度（vp） */
  width: number;
  /** 图片高度（vp） */
  height: number;
}

/** 参与拼图的一张照片 */
export interface ShareTile {
  /** 照片沙盒绝对路径 */
  path: string;
  /** 该照片对应的任务名（用于拼图角标） */
  taskName: string;
}

/** 拼图槽位（矩形位置与尺寸） */
export interface Pos {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 分享卡配色（与 App 主题一致：奶油底 + 品牌橙） */
const BG_COLOR: string = '#FFF8EE';
const BRAND: string = '#FF8A3D';
const TEXT_MAIN: string = '#4A3524';
const TEXT_SUB: string = '#8B7B6B';
const TILE_BG: string = '#FFE8CE';

/**
 * 成长时光分享图生成器：用【离屏画布 OffscreenCanvas】把【一整天的照片】合成成
 * 一张拼图式分享卡，再用 ImagePacker 编码成 PNG 存到沙盒。
 *
 * 设计要点：
 *  · 拼图模式：一天的照片按 1/2/4/9 宫格排布（类似相册九宫格），而不是只放一张
 *  · 任务评价：根据当天完成的任务数量与类型生成一句正向评价 + 鼓励语
 *  · 全部本地合成，不上传（与 App 隐私约束一致）
 *  · 用 OffscreenCanvas 而非页面截图：导出尺寸固定（不受设备屏宽影响），不依赖界面渲染时机
 */
export class ShareCard {
  /** 分享卡尺寸（vp，3:4 竖版，适配社交平台） */
  static readonly WIDTH: number = 900;
  static readonly HEIGHT: number = 1200;

  /** 拼图区几何 */
  private static readonly GRID_X: number = 50;
  private static readonly GRID_Y: number = 210;
  private static readonly GRID_W: number = 800;
  private static readonly GRID_H: number = 700;

  /**
   * 合成「一整天的照片集」拼图分享图。
   * @param context 上下文
   * @param tiles 当天的照片列表（可多张，按 1/2/4/9 宫格排布）
   * @param title 主标题（如「10 月 31 日 · 成长时光」）
   * @param review 任务评价文案（由 evaluate 生成）
   * @param subtitle 副标题（如「今天完成 3 个习惯」）
   */
  static async composeDay(context: common.UIAbilityContext, tiles: ShareTile[], title: string,
    review: string, subtitle: string): Promise<ShareCardResult | null> {
    try {
      const canvas = new OffscreenCanvas(ShareCard.WIDTH, ShareCard.HEIGHT);
      const ctx = canvas.getContext('2d');
      if (ctx === undefined) {
        hilog.error(DOMAIN, TAG, 'getContext(2d) failed');
        return null;
      }

      // 1) 背景：奶油底 + 顶部品牌色条 + 右上角装饰圆
      ctx.fillStyle = BG_COLOR;
      ctx.fillRect(0, 0, ShareCard.WIDTH, ShareCard.HEIGHT);
      ctx.fillStyle = BRAND;
      ctx.fillRect(0, 0, ShareCard.WIDTH, 28);
      ctx.fillStyle = '#FFE3C7';
      ctx.beginPath();
      ctx.arc(ShareCard.WIDTH - 60, 90, 70, 0, Math.PI * 2);
      ctx.fill();

      // 2) 标题 + 副标题
      ctx.fillStyle = TEXT_MAIN;
      ctx.font = 'bold 54px sans-serif';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(title, ShareCard.GRID_X, 70);
      ctx.fillStyle = TEXT_SUB;
      ctx.font = '32px sans-serif';
      ctx.fillText(subtitle, ShareCard.GRID_X, 145);

      // 3) 拼图区：按数量选宫格布局
      const positions = ShareCard.layoutOf(tiles.length);
      for (let i = 0; i < tiles.length && i < positions.length; i++) {
        await ShareCard.drawTile(ctx, tiles[i], positions[i]);
      }

      // 4) 任务评价区（浅色卡片 + 引号装饰）
      const ry = ShareCard.GRID_Y + ShareCard.GRID_H + 26;
      ctx.fillStyle = TILE_BG;
      ShareCard.roundRect(ctx, ShareCard.GRID_X, ry, ShareCard.GRID_W, 130, 28);
      ctx.fill();
      // 左侧竖条（品牌色）
      ctx.fillStyle = BRAND;
      ShareCard.roundRect(ctx, ShareCard.GRID_X + 22, ry + 26, 8, 78, 4);
      ctx.fill();
      // 评价文案（过长自动换行）
      ctx.fillStyle = TEXT_MAIN;
      ctx.font = 'bold 34px sans-serif';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      const reviewLines = ShareCard.wrapText(ctx, review, ShareCard.GRID_W - 90);
      for (let i = 0; i < reviewLines.length && i < 2; i++) {
        ctx.fillText(reviewLines[i], ShareCard.GRID_X + 48, ry + 24 + i * 44);
      }
      // 底部品牌行
      ctx.fillStyle = BRAND;
      ctx.font = 'bold 30px sans-serif';
      ctx.fillText('宝宝好习惯 · 成长时光', ShareCard.GRID_X, ShareCard.HEIGHT - 62);
      ctx.fillStyle = TEXT_SUB;
      ctx.font = '26px sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(`${tiles.length} 张照片`, ShareCard.WIDTH - ShareCard.GRID_X, ShareCard.HEIGHT - 58);

      // 5) 导出 PixelMap → PNG → 沙盒文件
      const out = ctx.getPixelMap(0, 0, ShareCard.WIDTH, ShareCard.HEIGHT);
      const packer = image.createImagePacker();
      // PackingOption：format 必须是 MIME 标准（image/png），quality 默认 0 需 ≥80
      const packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
      const data = await packer.packToData(out, packOpts);
      const dir = `${context.filesDir}/shares`;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const fileName = `share_${Date.now()}.png`;
      const filePath = `${dir}/${fileName}`;
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      // packToData 返回的就是 ArrayBuffer，直接写入（不能再取 .buffer，那是 TypedArray 的属性）
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);
      await packer.release();
      await out.release();

      // 校验文件确实落盘且非空：否则后续保存相册会失败但看不出原因
      const written = fileIo.statSync(filePath).size;
      if (written <= 0) {
        hilog.error(DOMAIN, TAG, 'share png is empty: %{public}s', filePath);
        return null;
      }

      hilog.info(DOMAIN, TAG, 'share card composed: %{public}s size=%{public}d', filePath, written);
      return { path: filePath, width: ShareCard.WIDTH, height: ShareCard.HEIGHT };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'compose failed: %{public}s', String(err));
      return null;
    }
  }

  /**
   * 宫格布局：1 张整块 / 2 张左右 / 3 张一大二小 / 4 张田字 / 5-9 网格。
   * 直接返回槽位数组（ArkTS 不允许用内联对象字面量当类型，
   * 也不允许返回无对应声明的对象字面量）。
   */
  private static layoutOf(count: number): Pos[] {
    const gx = ShareCard.GRID_X;
    const gy = ShareCard.GRID_Y;
    const gw = ShareCard.GRID_W;
    const gh = ShareCard.GRID_H;
    const gap = 12;
    const positions: Pos[] = [];
    // 槽位一律显式声明类型后再 push（ArkTS 不接受无类型对象字面量）
    if (count <= 0) {
      return positions;
    }
    if (count === 1) {
      const p0: Pos = { x: gx, y: gy, w: gw, h: gh };
      positions.push(p0);
      return positions;
    }
    if (count === 2) {
      const w = (gw - gap) / 2;
      const p0: Pos = { x: gx, y: gy, w: w, h: gh };
      const p1: Pos = { x: gx + w + gap, y: gy, w: w, h: gh };
      positions.push(p0);
      positions.push(p1);
      return positions;
    }
    if (count === 3) {
      // 左边一张大图占满高，右边上下两张
      const bigW = (gw - gap) * 0.6;
      const smallW = gw - gap - bigW;
      const smallH = (gh - gap) / 2;
      const p0: Pos = { x: gx, y: gy, w: bigW, h: gh };
      const p1: Pos = { x: gx + bigW + gap, y: gy, w: smallW, h: smallH };
      const p2: Pos = { x: gx + bigW + gap, y: gy + smallH + gap, w: smallW, h: smallH };
      positions.push(p0);
      positions.push(p1);
      positions.push(p2);
      return positions;
    }
    if (count === 4) {
      const w = (gw - gap) / 2;
      const h = (gh - gap) / 2;
      for (let i = 0; i < 4; i++) {
        const cx = gx + (i % 2) * (w + gap);
        const cy = gy + Math.floor(i / 2) * (h + gap);
        const p: Pos = { x: cx, y: cy, w: w, h: h };
        positions.push(p);
      }
      return positions;
    }
    // 5-9 张：三行三列网格，居中
    const cols = 3;
    const rows = 3;
    const w = (gw - gap * (cols - 1)) / cols;
    const h = (gh - gap * (rows - 1)) / rows;
    for (let i = 0; i < cols * rows; i++) {
      const cx = gx + (i % cols) * (w + gap);
      const cy = gy + Math.floor(i / cols) * (h + gap);
      const p: Pos = { x: cx, y: cy, w: w, h: h };
      positions.push(p);
    }
    return positions;
  }

  /** 画一张拼图小图（圆角 + cover 裁剪 + 底部任务名角标） */
  private static async drawTile(ctx: OffscreenCanvasRenderingContext2D, tile: ShareTile,
    pos: Pos): Promise<void> {
    const r = 22;
    ctx.save();
    ShareCard.roundRect(ctx, pos.x, pos.y, pos.w, pos.h, r);
    ctx.clip();
    // 底色（图片加载失败时至少不是黑洞）
    ctx.fillStyle = TILE_BG;
    ctx.fillRect(pos.x, pos.y, pos.w, pos.h);
    try {
      const srcOptions: image.SourceOptions = { sourceDensity: 120 };
      const src = image.createImageSource(tile.path, srcOptions);
      if (src !== undefined) {
        const pixelMap = await src.createPixelMap();
        const info = await src.getImageInfo();
        // ImageInfo 的宽高在【嵌套的 size 字段】里
        const scale = Math.max(pos.w / info.size.width, pos.h / info.size.height);
        const dw = info.size.width * scale;
        const dh = info.size.height * scale;
        ctx.drawImage(pixelMap, pos.x + (pos.w - dw) / 2, pos.y + (pos.h - dh) / 2, dw, dh);
        await pixelMap.release();
        await src.release();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'draw tile failed: %{public}s', String(err));
    }
    // 底部任务名角标
    if (tile.taskName !== '' && pos.h > 120) {
      ctx.fillStyle = '#99000000';
      ctx.fillRect(pos.x, pos.y + pos.h - 46, pos.w, 46);
      ctx.fillStyle = '#FFFFFF';
      ctx.font = '24px sans-serif';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText(ShareCard.ellipsis(ctx, tile.taskName, pos.w - 24), pos.x + 12, pos.y + pos.h - 23);
    }
    ctx.restore();
  }

  /** 画圆角矩形路径 */
  private static roundRect(ctx: OffscreenCanvasRenderingContext2D, x: number, y: number,
    w: number, h: number, r: number): void {
    const radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + w - radius, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + radius);
    ctx.lineTo(x + w, y + h - radius);
    ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h);
    ctx.lineTo(x + radius, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.closePath();
  }

  /** 文本按宽度折行 */
  private static wrapText(ctx: OffscreenCanvasRenderingContext2D, text: string, maxW: number): string[] {
    const lines: string[] = [];
    let cur = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      const test = cur + ch;
      if (ctx.measureText(test).width > maxW && cur.length > 0) {
        lines.push(cur);
        cur = ch;
        if (lines.length >= 2) {
          return lines;
        }
      } else {
        cur = test;
      }
    }
    if (cur.length > 0) {
      lines.push(cur);
    }
    return lines;
  }

  /** 文本超长加省略号 */
  private static ellipsis(ctx: OffscreenCanvasRenderingContext2D, text: string, maxW: number): string {
    if (ctx.measureText(text).width <= maxW) {
      return text;
    }
    let s = text;
    while (s.length > 1 && ctx.measureText(s + '…').width > maxW) {
      s = s.substring(0, s.length - 1);
    }
    return s + '…';
  }

  /**
   * 根据当天完成的任务生成评价文案。
   * @param count 完成的任务数
   * @param taskNames 当天完成的任务名列表
   */
  static evaluate(count: number, taskNames: string[]): string {
    if (count <= 0) {
      return '今天还没有完成记录，明天继续加油呀！';
    }
    // 按完成数量分档给出不同的肯定语气
    let scene: string;
    if (count >= 4) {
      scene = '一口气完成这么多，宝宝真是太自律啦！';
    } else if (count === 3) {
      scene = '完成得稳稳当当，节奏刚刚好。';
    } else if (count === 2) {
      scene = '坚持了自己的小计划，很棒。';
    } else {
      scene = '迈出了小小的一步，值得表扬。';
    }
    // 任务名只取前两个（避免评价行过长），其余用数量概括
    let detail = '';
    if (taskNames.length === 1) {
      detail = `「${taskNames[0]}」`;
    } else if (taskNames.length === 2) {
      detail = `「${taskNames[0]}」「${taskNames[1]}」`;
    } else {
      detail = `「${taskNames[0]}」等 ${taskNames.length} 个习惯`;
    }
    return `今天${scene}${detail}都完成啦，真棒！`;
  }
}

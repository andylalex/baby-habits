import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'GallerySave';

/** 保存结果 */
export interface GallerySaveResult {
  /** 是否成功（用户取消弹窗也算未成功） */
  ok: boolean;
  /** 失败/取消的原因（可直接展示给用户） */
  message: string;
}

/**
 * 保存图片到系统相册（【免权限】方案）。
 *
 * 为什么不用 MediaAssetChangeRequest.createImageAssetRequest + applyChanges：
 * 那条路需要 ohos.permission.WRITE_IMAGEVIDEO 权限（user_grant，要运行时申请，
 * 且上架 ACL 审核严格）。而官方推荐的免权限方式是：
 *   ① 传入沙盒里的源文件 uri
 *   ② showAssetsCreationDialog 弹系统授权窗（用户点"保存"即授权写入）
 *   ③ 把沙盒文件内容写入返回的目标 uri
 * 这样无需申请任何相册权限，用户也有明确的确认动作。
 *
 * ⚠️ 两个必须遵守的要点（华为官方 QA 明确指出，踩过就是"保存无效且无报错"）：
 *   1. **源文件必须用 fileUri.getUriFromPath(path) 转成规范的文件 URI**
 *      （形如 file://com.bundleName/data/storage/.../x.png）。
 *      直接把沙盒路径 / 手动拼 `file://${path}` 给系统，系统预览组件读不到，
 *      弹窗预览空白、保存无效。
 *   2. **写入目标要用 readSync + writeSync 逐块拷贝**，
 *      不能用 copyFile —— 沙箱 → 媒体库属跨域场景，copyFile 对它无效。
 */
export class GallerySave {
  /**
   * 把沙盒里的图片文件保存到系统相册（弹窗授权，免权限）。
   * @param context 上下文
   * @param sandboxPath 沙盒内图片的绝对路径（如 `${context.filesDir}/shares/x.png`）
   * @param title 相册里显示的标题（可空）
   * @param ext 文件扩展名（不含点，如 'png' / 'jpg'）
   */
  static async save(context: common.UIAbilityContext, sandboxPath: string,
    title: string, ext: string): Promise<GallerySaveResult> {
    let srcFile: fileIo.File | null = null;
    let desFile: fileIo.File | null = null;
    try {
      // 源文件必须已存在于沙盒
      if (!fileIo.accessSync(sandboxPath)) {
        return { ok: false, message: '图片文件不存在' };
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      // 关键：路径 → 规范文件 URI（含 bundleName），系统预览组件才能读
      const srcUri = fileUri.getUriFromPath(sandboxPath);
      hilog.info(DOMAIN, TAG, 'src uri: %{public}s', srcUri);
      const srcUris: string[] = [srcUri];
      // 目标资源的创建参数：后缀 + 类型必填，标题与子类型可选
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: title,
          fileNameExtension: ext,
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT
        }
      ];
      // 弹系统授权窗：用户确认后返回相册内的目标 uri
      const desUris: string[] = await helper.showAssetsCreationDialog(srcUris, configs);
      if (desUris === undefined || desUris.length === 0) {
        return { ok: false, message: '已取消保存' };
      }
      // 目标 uri 用 READ_WRITE | CREATE 打开（媒体库目标可能尚不存在）
      desFile = await fileIo.open(desUris[0],
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      srcFile = await fileIo.open(sandboxPath, fileIo.OpenMode.READ_ONLY);
      // 关键：读出字节再写入（不能用 copyFile，跨域到媒体库无效）
      // 一次性读入：分享图 PNG 只有几百 KB，内存完全够用
      const size = fileIo.statSync(sandboxPath).size;
      if (size <= 0) {
        return { ok: false, message: '图片内容为空，保存失败' };
      }
      const buf = new ArrayBuffer(size);
      // 分块「读一块、写一块」。
      // fs.readSync 的 offset 表示【文件内的读取位置】，读到的数据从缓冲区起始处写入，
      // 所以必须边读边写 —— 读完再一次性写会只拿到最后一块（数据错位）。
      let offset = 0;
      let written = 0;
      while (offset < size) {
        const readLen = fileIo.readSync(srcFile.fd, buf, {
          offset: offset,
          length: size - offset
        });
        if (readLen <= 0) {
          break;
        }
        // 每次只写本次读到的这一段
        const chunk = fileIo.writeSync(desFile.fd, buf.slice(0, readLen));
        if (chunk <= 0) {
          break;
        }
        written += chunk;
        offset += readLen;
      }
      hilog.info(DOMAIN, TAG, 'saved to gallery, bytes=%{public}d uri=%{public}s',
        written, desUris[0]);
      if (written <= 0) {
        return { ok: false, message: '图片内容为空，保存失败' };
      }
      return { ok: true, message: '已保存到相册' };
    } catch (err) {
      // 记录错误码，便于真机定位（hilog 抓取：hdc shell hilog -x | grep GallerySave）
      const bizErr = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'save failed: code=%{public}d msg=%{public}s',
        bizErr.code, bizErr.message);
      return { ok: false, message: '保存失败，请稍后再试' };
    } finally {
      if (srcFile !== null) {
        fileIo.closeSync(srcFile);
      }
      if (desFile !== null) {
        fileIo.closeSync(desFile);
      }
    }
  }
}

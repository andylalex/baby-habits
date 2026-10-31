import { common, Want } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'PhotoCapture';

/** 相机选择器可用能力（避免重复探测） */
let cameraUsable: boolean = true;

/**
 * 拍照打卡：调起**系统原生相机**（cameraPicker），把照片落到应用沙盒 files/images/checkins/。
 *
 * 为什么用 cameraPicker 而不是 imageCapture 意图：
 *  · cameraPicker 是官方相机选择器组件，相机 UI 由系统提供，**无需申请相机权限**
 *    （用户主动拍摄并确认，App 只拿结果）
 *  · 可通过 PickerProfile 传原生参数：前后摄像头（cameraPosition）、保存位置（saveUri）
 *  · 拍照 UI 与系统主题一致，升级跟随系统
 *
 * 隐私：照片只存本地沙盒，不上传。
 */
export class PhotoCapture {
  /**
   * 调起系统相机拍照。
   * @param context 上下文
   * @param front true=前置摄像头 false=后置（默认）
   * @returns 沙盒相对路径（如 images/checkins/c123.jpg）；取消或失败返回 null
   */
  static async capture(context: common.UIAbilityContext, front: boolean = false): Promise<string | null> {
    if (!cameraUsable) {
      return null;
    }
    try {
      const dir = `${context.filesDir}/images/checkins`;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const fileName = `c${Date.now()}.jpg`;
      const targetPath = `${dir}/${fileName}`;

      // PickerProfile：指定镜头方向 + 保存到沙盒（沙盒文件需已存在且可写）
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: front ? camera.CameraPosition.CAMERA_POSITION_FRONT
          : camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: fileUri.getUriFromPath(targetPath)
      };
      // 先建好空文件（picker 要求 saveUri 对应文件存在且可写）
      const fd = fileIo.openSync(targetPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.closeSync(fd);

      const result: cameraPicker.PickerResult = await cameraPicker.pick(context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode !== 0 || !result.resultUri) {
        hilog.info(DOMAIN, TAG, 'camera picker cancelled or failed: %{public}d', result.resultCode);
        return null;
      }
      hilog.info(DOMAIN, TAG, 'photo saved: %{public}s', targetPath);
      return `images/checkins/${fileName}`;
    } catch (err) {
      // 设备无相机能力等异常：降级为旧意图方式，仍失败则返回 null
      hilog.error(DOMAIN, TAG, 'cameraPicker failed: %{public}s', String(err));
      cameraUsable = false;
      return PhotoCapture.captureByIntent(context);
    }
  }

  /**
   * 降级方案：用 imageCapture 意图调起系统相机应用。
   * cameraPicker 不可用时（例如部分设备无相机服务）走这条路径。
   */
  private static async captureByIntent(context: common.UIAbilityContext): Promise<string | null> {
    const want: Want = {
      action: 'ohos.want.action.imageCapture'
    };
    try {
      const result = await context.startAbilityForResult(want);
      const params = result.want?.parameters as Record<string, Object> | undefined;
      const uri = (params?.['resourceUri'] ?? params?.['uri']) as string | undefined;
      if (!uri) {
        return null; // 用户取消
      }
      const dir = `${context.filesDir}/images/checkins`;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const fileName = `c${Date.now()}.jpg`;
      const srcPath = `${dir}/${fileName}`;
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(srcPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      hilog.info(DOMAIN, TAG, 'photo saved by intent: %{public}s', srcPath);
      return `images/checkins/${fileName}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'capture failed: %{public}s', String(err));
      return null;
    }
  }

  /** 沙盒相对路径 → file:// URI（Image 组件可直接加载） */
  static toUri(context: common.UIAbilityContext, relPath: string): string {
    return `file://${context.filesDir}/${relPath}`;
  }

  /** 复制一个已选图片 URI 进沙盒，返回相对路径（与拍照产物同规则） */
  private static async copyIntoSandbox(context: common.UIAbilityContext, uri: string): Promise<string | null> {
    try {
      const dir = `${context.filesDir}/images/checkins`;
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const fileName = `p${Date.now()}.jpg`;
      const srcPath = `${dir}/${fileName}`;
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(srcPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      return `images/checkins/${fileName}`;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'copy photo failed: %{public}s', String(err));
      return null;
    }
  }

  /** 从系统相册选一张图（PhotoViewPicker，无需存储权限），复制进沙盒后返回相对路径；取消返回 null */
  static async pickFromGallery(context: common.UIAbilityContext): Promise<string | null> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris.length === 0) {
        return null;
      }
      return PhotoCapture.copyIntoSandbox(context, result.photoUris[0]);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pick failed: %{public}s', String(err));
      return null;
    }
  }
}

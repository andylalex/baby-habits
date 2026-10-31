# 宝宝好习惯（baby-habits）

鸿蒙 HarmonyOS 应用的**习惯养成**工具：宝宝端打卡攒星星，家长端用分龄模板配置任务。

- 技术栈：ArkTS + ArkUI（声明式），HarmonyOS SDK 26.0.0 / API 26
- 目标设备：手机 / 平板 / 折叠屏 / PC，多端自适应
- 包名：`com.yuebao.babyhabits`

## 目录结构

```
entry/src/main/ets/
├── commons/
│   ├── components/     通用 UI 组件（按钮、卡片、图标、家长页骨架）
│   ├── db/             关系型数据库（Dao / DatabaseHelper / SeedData）
│   ├── models/         数据模型
│   ├── theme/          设计令牌（间距、字号、圆角、颜色）
│   └── utils/          工具类（年龄换算、时段、指纹、相册保存、分享图、沉浸材质…）
├── entryability/       UIAbility（启动流程、首次引导判定）
├── formability/        服务卡片
└── pages/              页面
    ├── Index.ets           宝宝主界面（任务宫格 + 推荐任务 + 打卡）
    ├── KidProfile.ets      宝宝档案（名字 + 生日，首次引导与家长修改共用）
    ├── KidWallet.ets       我的星星（余额 / 心愿兑换 / 相册）
    ├── KidTimeline.ets     成长时光（按月分章 + 整日拼图分享）
    ├── KidLedger.ets       星星流水
    ├── KidBadges.ets       徽章
    ├── KidMilestones.ets   里程碑
    └── Parent*.ets         家长模式（指纹解锁进入）
```

## 在 PC 上用 DevEco Studio 打开

1. **获取代码**

   ```bash
   git clone https://github.com/andylalex/baby-habits.git
   ```

2. **环境要求**
   - DevEco Studio **26.0.0 Release**（Windows / macOS），或鸿蒙电脑版 **26.0.0 Beta1**
     —— 两者都内置 HarmonyOS SDK 26.0.0，与工程的 `targetSdkVersion` 一致
   - 鸿蒙电脑版需在「应用市场 → 我的 → 应用尝鲜」获取；Windows/macOS 版从
     [devecostudio.huawei.com](https://devecostudio.huawei.com/) 下载

3. **签名**
   `build-profile.json5` 里的 `signingConfigs.material` 指向的是**生成该文件那台机器**的
   调试证书路径（`~/.ohos/config/*.p12` 等）。这些证书文件本身不入库
   （`.gitignore` 已排除 `*.p12` / `*.cer` / `*.p7b`）。

   在新机器上首次构建时，DevEco Studio 会提示**自动签名**并重新生成调试证书，
   届时该文件里的证书路径与密码会被 IDE 自动更新为新机器的值。

4. **构建**
   打开工程 → `Build > Build Hap(s)/APP(s) > Build Hap(s)`。

## 数据与资源

- 数据库用 `@kit.ArkData` 的 `relationalStore`（SQLite），首次启动自动建表并灌入种子数据。
- 插画资源在 `entry/src/main/resources/rawfile/icons/`，入库以便统一视觉。

## 版本控制约定

- `main` 分支为主开发分支。
- `.gitignore` 排除了构建产物（`.hvigor/`、`entry/build/`）、依赖（`node_modules/`、
  `oh_modules/`）、IDE 缓存（`.idea/`、`.bitfun/`、`.cxx/`）与签名材料。
- 设备端（无 git 二进制）通过 `tools/sync.mjs` 走 GitHub Git Data API 同步，
  效果等同 `git push`；PC 端正常用 git 即可。

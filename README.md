# LingAI Korea Harmony App

> LingAI 韩语学习 App - 鸿蒙原生客户端
> 基于 HarmonyOS NEXT（API 21+），使用 ArkTS / ArkUI 开发

---

## 目录

- [项目概述](#项目概述)
- [系统架构](#系统架构)
- [开发环境搭建](#开发环境搭建)
- [项目结构](#项目结构)
- [页面与功能模块](#页面与功能模块)
- [服务层说明](#服务层说明)
- [数据模型](#数据模型)
- [后端 API 接口列表](#后端-api-接口列表)
- [主题系统](#主题系统)
- [本地数据库](#本地数据库)
- [构建与运行](#构建与运行)
- [开发规范与注意事项](#开发规范与注意事项)
- [关联工程](#关联工程)

---

## 项目概述

LingAI Korea Harmony App 是 LingAI 语言学习平台的韩语学习客户端，运行在 HarmonyOS 设备上。App 提供以下核心功能：

- **关卡式学习**：按 TOPIK 等级（I / II / 常考单词）分关卡，每关 20 词
- **智能词典**：韩中双向查询，AI 深度解析（含义详解、搭配、近反义词等）
- **TTS 发音**：韩语 / 中文语音合成播放
- **生词本**：间隔复习算法（D0 / D1 / D3 / D7 / D14 / D30）
- **学习统计**：每日打卡、学习时长、关卡进度等可视化
- **AI 精灵**：悬浮按钮呼出对话面板，提供学习辅助
- **深色模式**：支持浅色 / 深色主题切换

### 技术栈

| 技术        | 版本 / 规格                          |
| ----------- | ------------------------------------ |
| OS          | HarmonyOS NEXT                       |
| SDK         | 6.0.1(21)，API 21+                  |
| 语言        | ArkTS（严格模式）                    |
| UI 框架     | ArkUI（声明式）                      |
| 构建工具    | hvigor                               |
| 本地存储    | RDB（关系型数据库）+ Preferences     |
| 网络请求    | `@ohos.net.http`                     |
| 音频播放    | `@ohos.multimedia.media`（AVPlayer） |
| 测试框架    | `@ohos/hypium` 1.0.24                |
| Mock 框架   | `@ohos/hamock` 1.0.0                 |

---

## 系统架构

本 App 在 LingAI 平台中的定位（1.0 架构）：

```text
┌─────────────────────────────────────────────────────────────┐
│                      客户端与运营层                           │
├────────────────────────────┬────────────────────────────────┤
│  Harmony App（本工程）      │  Admin Web（运营后台）          │
└─────────────┬──────────────┴──────────────┬─────────────────┘
              │ HTTPS + RSA签名 + JWT       │ HTTPS + JWT
              ▼                             ▼
      ┌──────────────────────────────────────────────┐
      │           LingAI Unified Service             │
      │  auth / user / device / version / gateway    │
      └────────────┬──────────────────────┬──────────┘
                   │ 内网HTTP              │
                   ▼                       ▼
      ┌─────────────────────┐    ┌──────────────────┐
      │  FastAPI Service    │    │  MySQL + Redis   │
      │ dict/content/tts    │    │  (Unified 数据)  │
      └─────────┬───────────┘    └──────────────────┘
                │
                ▼
         第三方能力（LLM/TTS等）
```

**调用链路说明**（1.0 发布版）：

- App **全量走 Unified Service**，不直连 FastAPI
- 业务请求路径：`/api/app/biz/{fastapiPath}` → Unified 网关 → FastAPI
- 登录链路：App → `/api/app/auth/*` → Unified

> 当前 `API_BASE_URL` 由受控本地配置指定 Unified 地址。FastAPI 仅供 Unified 内部调用，手机不能使用 Mac 的 `localhost`。

---

## 开发环境搭建

### 1. 工具安装

当前签名构建已验证 DevEco Studio 26.0.0 随附工具：Node.js 24.14.1、ohpm 26.0.0.630、hvigor 6.26.8、JBR 25.0.2、HarmonyOS SDK 26.0.0.105（API 26）。工程 target/minimum 均保持 6.0.1(21)。`default/debug` 的 `assembleHap` 和官方 `verify-app` 离线验签通过；未进行设备安装或登录验收。首轮 DevEco 6.0.2 的编译结果保留在 LG-020 历史证据中。

### 2. 导入工程

在 DevEco Studio 中打开选定源码目录。命令行依赖安装见“构建与运行”。本仓不包含 `hvigorw`，使用 DevEco 的绝对路径。

HarmonyOS 构建要求 `DEVECO_SDK_HOME` 指向 DevEco 的 `Contents/sdk`；当前 hvigor 不从 `local.properties` 读取 HarmonyOS SDK 路径。命令见“构建与运行”。

### 3. 配置 API 与应用凭据

创建本地忽略文件 `entry/src/main/ets/local/Secret.dev.ets`，目录权限 `0700`，文件权限 `0600`。使用受控文件交接真实值，不把凭据贴入聊天、日志或 Git。

| 必需导出 | 来源和要求 |
| --- | --- |
| `UNIFIED_BASE_URL_DEV` | 当前 Mac 的局域网 Unified 地址，例如 `http://<LAN_IP>:8080` |
| `APP_KEY_DEV` | 独立本地 Unified 应用记录的 app key |
| `APP_PRIVATE_KEY_DEV` | 与该应用公钥配对的 RSA2048 PKCS#8 PEM 私钥 |
| `PNVS_AUTH_SECRET_DEV` | PNVS HarmonyOS 客户端 SDK 密钥，必须与当前 bundle 和签名方案对应 |

恢复 PNVS 时，将供应商返回的原始 SDK 密钥通过本地编辑器写入 `.local/pnvs-auth-secret.txt`，不包含引号或 `export`，保持目录 `0700`、文件 `0600`。使用同一应用的 bundleName、最终可安装签名 SHA256 和 AppId 核对供应商方案。

通过配置脚本读取已有受保护文件，避免手写密钥字面量：

```bash
python3 tools/configure-local.py --unified-local /absolute/path/to/unified/.local --url http://<LAN_IP>:8080
```

脚本默认在 PNVS 缺失时失败，保留原配置。仅编译检查可显式添加 `--build-only`，此时空 PNVS 会禁用一键登录。脚本核对本地应用编号、文件权限和 RSA 公私钥配对，不输出密钥内容。

四项均声明为 `export const <NAME>: string`。无 PNVS 客户端密钥时可明确设置为空字符串，仅用于构建检查；一键登录拒绝初始化和请求，这不代表真实登录已经恢复。服务端 Aliyun AccessKey 不能代替 PNVS 客户端 SDK 密钥。源码中的默认密钥均为空，不提供占位密钥。

`AUTH_APP_ID` 保持 `1`；本地 Unified 必须在隔离数据库中为该编号登记本地 app key 与公钥，不能冒用旧环境的凭据或关闭验签。`APP_PRIVATE_KEY_DEV` 仅用于当前隔离环境。

### 4. 签名配置

`default` 调试签名使用原应用 `com.lingai.app` / AppId `6917597519602711463`。先在 DevEco 中保存经核验的 `.p12`、证书、debug Profile 和密码配置，再关闭设置窗口，避免 IDE 后续 Apply 覆盖迁移结果。密码由 IDE 生成安全配置，不手工补长、不解密，也不粘贴到终端或聊天。

在已忽略的 `.local/signing/`（目录 `0700`）中保存本地配置：

```bash
python3 tools/configure-signing.py migrate
python3 tools/configure-signing.py check
```

迁移工具仅从当前工程的已保存配置读取 `default`，校验原应用身份、Profile 有效期和批准的证书指纹，将完整对象写入 `.local/signing/default.json`（`0600`），然后清空受版本控制文件中 default 的材料值。已有本地配置不会被覆盖；若遇到并发编辑，保留受保护副本并停止，不覆盖新编辑。证书更新需要重新审阅工具中的公开指纹约束。工具不解密密码、不读取 IDE 日志、不安装设备。

构建时必须显式设置 `LINGAI_LOCAL_SIGNING=1`，仅允许 `default` / `debug`，通过 Hvigor 官方配置接口加载本地对象。普通 IDE Sync 不启用注入；不得把 appstore 改绑到 default。每次构建重新核验受保护文件权限、身份、有效期及材料摘要，校验失败就停止。

迁移保留 `release` 原对象和 `appstore -> release` 原引用及其他文件内容。既有 release 密码字段仍在历史及受控文件中，本工具仅隔离本次新 debug 配置，不能把整份文件或历史仓库称为无凭据。不要直接归档工作树、打印签名配置差异或提交 `.local`、`material`、私钥及任何密码配置。源码交付前单独核对暂存范围。

合成测试不会读取真实密码或私钥：

```bash
python3 -B -m unittest discover -s tools/tests -p 'test_configure_signing.py'
```

### 5. 真机调试

安装前先核实设备已装 bundle、版本、签名覆盖关系与数据保全方案。构建 HAP 不会自动安装到设备；未经单独确认，不卸载旧 App 或覆盖用户数据。设备经局域网访问 Unified，端口可达不等于真实登录、SSE 或音频已验收。

---

## 项目结构

```
lingai-korea-harmony-app/
├── AppScope/                          # 应用级配置
│   └── app.json5                      # bundleName: com.lingai.app, 版本: 1.0.1
├── entry/                             # 主模块
│   └── src/main/
│       ├── ets/                        # 源代码（ArkTS）
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets    # 应用入口 Ability
│       │   ├── entrybackupability/
│       │   │   └── EntryBackupAbility.ets  # 备份扩展 Ability
│       │   ├── pages/                  # 页面（路由注册见 main_pages.json）
│       │   │   ├── Index.ets           # 首页 Tab 容器（4 Tab）
│       │   │   ├── LessonPage.ets      # 关卡学习页
│       │   │   ├── SettingsPage.ets    # 设置页
│       │   │   ├── StatisticsPage.ets  # 学习统计页
│       │   │   └── SSETestPage.ets     # SSE 流式测试页（开发用）
│       │   ├── components/             # UI 组件（13 个）
│       │   │   ├── HomeContent.ets     # 首页内容
│       │   │   ├── StudyContent.ets    # 学习内容（关卡列表）
│       │   │   ├── DictContent.ets     # 词典内容（搜索 + AI 解析）
│       │   │   ├── ProfileContent.ets  # 个人中心
│       │   │   ├── VocabularyContent.ets   # 生词本
│       │   │   ├── FlashCard.ets       # 闪卡组件
│       │   │   ├── QuizCard.ets        # 练习题卡片
│       │   │   ├── WordCard.ets        # 单词卡片
│       │   │   ├── PlayButton.ets      # TTS 播放按钮
│       │   │   ├── SelectableText.ets  # 可选中文本（划词翻译）
│       │   │   ├── FloatingSpirit.ets  # 悬浮 AI 精灵按钮
│       │   │   ├── SpiritChatPanel.ets # AI 精灵对话面板
│       │   │   └── SettingsContent.ets # 设置内容
│       │   ├── services/               # 服务层（8 个）
│       │   │   ├── ApiService.ets      # HTTP 请求封装（单例）
│       │   │   ├── AudioService.ets    # TTS 音频播放（AVPlayer）
│       │   │   ├── DatabaseService.ets # RDB 数据库操作
│       │   │   ├── PreferencesService.ets  # 本地偏好设置
│       │   │   ├── VocabularyService.ets   # 生词本管理与复习算法
│       │   │   ├── StatisticsService.ets   # 学习统计聚合
│       │   │   ├── TaskTrackingService.ets # 每日任务追踪
│       │   │   └── SpiritChatService.ets   # AI 精灵对话
│       │   ├── models/
│       │   │   └── DataModels.ets      # 数据模型定义（20+ class）
│       │   └── utils/
│       │       ├── Constants.ets       # 常量、API 配置、主题色定义
│       │       └── ThemeManager.ets    # 主题管理器（深色/浅色切换）
│       ├── resources/                  # 资源文件
│       │   ├── base/                   # 默认资源（图标、字符串、颜色等）
│       │   └── dark/                   # 深色模式资源
│       └── module.json5               # 模块配置（权限、Ability 声明）
├── build-profile.json5                # 构建配置（签名、目标 SDK）
├── oh-package.json5                   # 依赖声明
├── code-linter.json5                  # 代码检查配置
├── hvigorfile.ts                      # hvigor 构建脚本
└── oh-package-lock.json5              # 依赖锁定
```

---

## 页面与功能模块

### Tab 导航结构（Index.ets）

| Tab    | 组件              | 功能说明                                 |
| ------ | ----------------- | ---------------------------------------- |
| 首页   | `HomeContent`     | 学习概览、今日任务、快速入口             |
| 学习   | `StudyContent`    | TOPIK 等级选择、关卡列表、进度展示       |
| 词典   | `DictContent`     | 韩中双向搜索、AI 解析、生词收藏         |
| 我的   | `ProfileContent`  | 个人信息、设置入口、主题切换、生词本统计 |

### 独立页面（通过 router 跳转）

| 页面                 | 功能说明                                     |
| -------------------- | -------------------------------------------- |
| `LessonPage`         | 关卡学习流程：单词展示 → 闪卡 → 练习题      |
| `SettingsPage`       | 应用设置（通知、下载等偏好配置）             |
| `StatisticsPage`     | 学习统计详情（日历打卡、时长趋势、生词统计） |
| `SSETestPage`        | SSE 流式接口测试（开发调试用）               |

---

## 服务层说明

所有服务采用**单例模式**，通过 `getInstance()` 获取实例。

| 服务                   | 职责                                                         |
| ---------------------- | ------------------------------------------------------------ |
| `ApiService`           | 封装 HTTP GET/POST 请求，统一错误处理，对接后端全部 API 端点 |
| `AudioService`         | TTS 音频下载与播放，使用 AVPlayer + 临时文件方案             |
| `DatabaseService`      | RDB 数据库初始化、词条 CRUD、进度管理、生词本、每日任务      |
| `PreferencesService`   | 用户偏好设置的读写（Preferences API）                        |
| `VocabularyService`    | 生词本的增删改查、间隔复习算法（6 级复习周期）               |
| `StatisticsService`    | 学习数据聚合（概览统计、月度趋势、生词统计）                 |
| `TaskTrackingService`  | 每日学习任务追踪（关卡步骤、复习次数、学习时长）             |
| `SpiritChatService`    | AI 精灵对话，维护消息上下文                                  |

---

## 数据模型

核心数据模型定义在 `entry/src/main/ets/models/DataModels.ets`，全部使用 `class` 定义（ArkTS 严格模式不支持 object literal 方式创建 interface 实例）。

### 主要模型一览

| 模型                 | 说明                                          |
| -------------------- | --------------------------------------------- |
| `WordEntry`          | 词条：韩文、罗马音、词性、释义、例句、TOPIK 等级 |
| `LessonInfo`         | 关卡信息：ID、等级、标题、进度                |
| `LessonProgress`     | 关卡进度：已掌握词、跳过词、正确次数 Map      |
| `Quiz` / `QuizOption` / `QuizStem` | 练习题、选项、题干              |
| `DailyTask`          | 每日任务：日期、关卡步骤、复习数、学习时长    |
| `VocabStats`         | 生词本统计：待复习数、总数                    |
| `LearningOverview`   | 学习概览：学习天数、总时长、完成关卡数        |
| `DailyStats`         | 每日统计：日期、学习时长、关卡数、复习数      |
| `DictSearchResponse` | 词典搜索响应：来源、查询词、结果列表、AI 补充 |
| `DictAIResponse`     | AI 解析：释义、词性、汉字、构词、搭配、例句、近义词、反义词等 |
| `UserSettings`       | 用户设置：通知开关、通知时间、自动下载数量    |

---

## 后端 API 接口列表

当前 App 调用的后端 API 汇总（均基于 `API_BASE_URL`）。

### 词典相关

| 方法   | 路径                          | 说明                               |
| ------ | ----------------------------- | ---------------------------------- |
| `GET`  | `/api/dict/search`            | 词典搜索（含 AI 补充），参数：`query`, `direction` |
| `POST` | `/api/dict/ai`                | 获取词典 AI 详细解析               |
| `GET`  | `/api/dict/quick-translate`   | 快速翻译，参数：`word`, `direction`|

### 学习内容相关

| 方法   | 路径                                            | 说明                                 |
| ------ | ----------------------------------------------- | ------------------------------------ |
| `GET`  | `/api/content/levels`                           | 获取 TOPIK 等级信息                  |
| `GET`  | `/api/content/lesson/{lessonId}`                | 获取关卡内容                         |
| `GET`  | `/api/content/lesson/{lessonId}/quiz-config`    | 获取练习配置                         |
| `GET`  | `/api/content/words/topik/{level}`              | 获取 TOPIK 等级全部词表              |
| `GET`  | `/api/content/words/level/{level}/lesson/{id}`  | 获取指定关卡词表，参数：`words_per_lesson` |

### TTS 语音

| 方法   | 路径              | 说明                                     |
| ------ | ----------------- | ---------------------------------------- |
| `POST` | `/api/tts`        | 获取 TTS 音频 URL                        |
| `GET`  | `/api/tts/play`   | 直接获取 TTS 音频流，参数：`text`, `lang`|

### 统计上报

| 方法   | 路径               | 说明                       |
| ------ | ------------------ | -------------------------- |
| `POST` | `/api/stats/batch` | 批量上报统计事件           |

### AI 精灵

| 方法   | 路径               | 说明                       |
| ------ | ------------------ | -------------------------- |
| `POST` | `/api/spirit/chat` | AI 精灵对话                |

---

## 主题系统

App 支持浅色 / 深色双主题，通过 `ThemeManager`（`utils/ThemeManager.ets`）管理。

### 主题色定义

主题色在 `Constants.ets` 中以静态类方式定义：

| 类名          | 用途             |
| ------------- | ---------------- |
| `LightTheme`  | 浅色主题色值     |
| `DarkTheme`   | 深色主题色值     |
| `ThemeColors` | 动态主题包装类   |
| `AppColors`   | 运行时动态主题（兼容旧代码） |

### 主要色值

| 色值类型    | 浅色模式    | 深色模式       |
| ----------- | ----------- | -------------- |
| 品牌主色    | `#6366f1`   | `#6366f1`      |
| 背景色      | `#f8fafc`   | `#050505`      |
| 卡片表面    | `#ffffff`   | `#1e293b`      |
| 主文字      | `#0f172a`   | `#f8fafc`      |
| 辅助文字    | `#475569`   | `#94a3b8`      |

### 使用方式

```typescript
import { themeManager } from '../utils/ThemeManager';
import { LightTheme, DarkTheme } from '../utils/Constants';

// 在组件中订阅主题变化
@State isDarkMode: boolean = false;

aboutToAppear() {
  themeManager.subscribe((isDark: boolean) => {
    this.isDarkMode = isDark;
  });
}

// 在 build 中使用
.backgroundColor(this.isDarkMode ? DarkTheme.BG_BODY : LightTheme.BG_BODY)
```

---

## 本地数据库

使用鸿蒙 RDB（`@ohos.data.relationalStore`）进行本地数据持久化。

### 数据库信息

- **数据库名**：`LingAI.db`
- **版本**：`1`

### 数据表

| 表名              | 用途                             | 主要字段                                       |
| ----------------- | -------------------------------- | ---------------------------------------------- |
| `word_entry`      | 词条缓存                         | id, hangul, romanization, pos, primary_meaning, topik_level, lesson_id |
| `lesson_progress` | 关卡学习进度                     | lesson_id, level, status, mastered_count, mastered_word_ids, correct_counts |
| `wordbook`        | 生词本                           | word_id, source, created_at, next_review_at, review_stage |
| `daily_task`      | 每日任务                         | date(PK), lesson_step_done, review_count, study_minutes |
| `stat_event`      | 统计事件                         | event_name, event_data, created_at              |

### 生词本复习算法

使用间隔重复（Spaced Repetition）策略，复习间隔为：

```
D0（立即）→ D1 → D3 → D7 → D14 → D30
```

完成所有 6 个复习周期后标记为已掌握。

---

## 构建与运行

### 开发调试

先恢复上述受控文件和本地 Unified 配置，再在工程根目录执行：

```bash
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH="$NODE_HOME/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH"
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install --all --no-save
LINGAI_LOCAL_SIGNING=1 /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon
```

依赖安装会写入 `oh_modules/` 和 ohpm 缓存，构建写入 `.hvigor/`、`build/`、`entry/build/` 等忽略目录。安装后核对锁文件差异，不手改生成的锁文件。调试 HAP 通常位于 `entry/build/default/outputs/default/`；核对当次构建退出码和产物摘要后才能作为该源码的构建证据。

登录请求的 `appVersion` 从已安装应用的 bundle 元信息读取，与 `AppScope/app.json5` 保持一致。无 PNVS 密钥时生成的包只验证构建，不用于宣告一键登录恢复或手机功能验收。

### 构建模式

- **debug**：开发调试使用，包含日志输出
- **release**：生产发布使用

### 应用信息

| 字段        | 值                |
| ----------- | ----------------- |
| bundleName  | `com.lingai.app`  |
| versionName | `1.0.1`           |
| versionCode | `1000001`         |
| 目标设备    | `phone`           |

### 权限声明

| 权限                        | 用途           |
| --------------------------- | -------------- |
| `ohos.permission.INTERNET`  | 访问后端 API   |

---

## 开发规范与注意事项

### ArkTS 严格模式

本工程启用了 ArkTS 严格模式（`build-profile.json5` 中 `strictMode`），需遵守：

- ❌ 不能使用 `any` / `unknown` 类型
- ❌ 不能通过 object literal 创建 interface 实例
- ✅ 必须使用 `class` 定义数据结构并通过 `new` 创建
- ✅ `throw` 必须使用 `Error` 子类
- ✅ 数组需要显式类型声明

### 编码约定

1. **单例模式**：所有 Service 类使用私有构造函数 + `getInstance()` 单例模式
2. **错误处理**：API 调用使用 try-catch + 静默降级（`null` 返回），不阻断用户流程
3. **异步操作**：统一使用 `async / await`，不使用回调方式
4. **组件装饰器**：使用 `@Component` / `@Entry` / `@State` / `@Prop` / `@Builder` 等 ArkUI 装饰器
5. **文件命名**：页面用 `XxxPage.ets`，组件用 `XxxContent.ets` 或 `XxxCard.ets`，服务用 `XxxService.ets`
6. **导出方式**：服务层使用 `export default`，模型和组件使用 `export class` / `export struct`

### 真机调试常见问题

| 问题                     | 解决方案                                         |
| ------------------------ | ------------------------------------------------ |
| API 连接超时             | 确认手机与 Mac 在同一 WiFi，使用 Mac 的局域网 IP |
| 签名错误                 | 先核证书、profile、bundle 和设备授权，不自动更换签名        |
| 白屏或页面不渲染         | 检查 `main_pages.json` 中页面注册是否正确        |
| TTS 无声音               | 确认 `AudioService.setCacheDir()` 已调用         |

---

## 关联工程

LingAI 平台由以下四个工程组成，详细架构参见 `/docs/统一项目架构设计.md`：

| 工程                     | 角色                                | 技术栈              |
| ------------------------ | ----------------------------------- | ------------------- |
| **lingai-korea-harmony-app**（本工程）| 用户端 App（鸿蒙）     | ArkTS / ArkUI       |
| lingai-unified-service   | 统一认证授权与业务网关              | Java / Spring Boot  |
| lingai-fastapi-service   | 内部学习能力服务（词典/TTS/内容/AI）| Python / FastAPI    |
| lingai-admin-web         | 运营管理后台前端                    | Vue / React         |

---

## License

Internal Use Only

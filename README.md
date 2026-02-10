# LingAI HarmonyOS App

韩语学习App - 鸿蒙原生版本

## 技术栈

- HarmonyOS NEXT (API 12+)
- ArkTS / ArkUI
- 本地存储: RDB + Preferences

## 项目创建步骤

1. 打开 DevEco Studio
2. File → New → Create Project
3. 选择 "Application" → "Empty Ability"
4. 配置项目:
   - Project name: `LingAI`
   - Bundle name: `com.lingai.app`
   - Save location: 选择 `app` 目录
   - Language: ArkTS
   - Compatible SDK: API 12

5. 创建完成后，用本目录中的模板代码替换对应文件

## 项目结构

```
app/
├── entry/src/main/
│   ├── ets/
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets      # 应用入口
│   │   ├── pages/
│   │   │   ├── Index.ets             # 首页(Tab容器)
│   │   │   ├── LessonPage.ets        # 关卡学习页
│   │   │   ├── DictPage.ets          # 词典页
│   │   │   └── MinePage.ets          # 我的页
│   │   ├── components/
│   │   │   ├── FlashCard.ets         # 预习闪卡
│   │   │   ├── QuizCard.ets          # 练习题卡
│   │   │   └── WordCard.ets          # 词条卡片
│   │   ├── services/
│   │   │   ├── DatabaseService.ets   # 数据库服务
│   │   │   ├── ApiService.ets        # API调用服务
│   │   │   └── PreferencesService.ets# 偏好设置服务
│   │   ├── models/
│   │   │   └── DataModels.ets        # 数据模型
│   │   └── utils/
│   │       └── Constants.ets         # 常量定义
│   └── resources/
│       ├── base/
│       │   ├── element/
│       │   ├── media/
│       │   └── profile/
│       └── rawfile/                  # 预置词表数据
└── oh-package.json5
```

## 开发命令

```bash
# 构建
hvigorw assembleHap

# 运行（模拟器/真机）
在 DevEco Studio 中点击 Run
```

# LingAI HarmonyOS App

韩语学习App - 鸿蒙原生版本

## 技术栈

- HarmonyOS NEXT (API 12+)
- ArkTS / ArkUI
- 本地存储: RDB + Preferences

## 开发环境

1. 使用 DevEco Studio 5.0+ 打开本工程根目录
2. 首次打开时 DevEco 会自动 Sync 安装依赖 (`oh_modules`)
3. 真机调试: 连接USB后点击 Run

## 后端 API

本工程的后端服务为独立仓库，启动方式：

```bash
cd <backend-repo-path>
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

API 基地址配置见 `entry/src/main/ets/utils/Constants.ets`。

## 项目结构

```
lingai-harmony-app/
├── AppScope/                   # 应用级配置
│   └── app.json5               # bundleName、版本号
├── entry/src/main/
│   ├── ets/
│   │   ├── entryability/
│   │   │   └── EntryAbility.ets      # 应用入口
│   │   ├── pages/
│   │   │   ├── Index.ets             # 首页(Tab容器)
│   │   │   ├── LessonPage.ets        # 关卡学习页
│   │   │   ├── SettingsPage.ets      # 设置页
│   │   │   └── StatisticsPage.ets    # 学习统计页
│   │   ├── components/               # UI组件
│   │   ├── services/                 # 服务层
│   │   ├── models/                   # 数据模型
│   │   └── utils/                    # 工具和常量
│   └── resources/                    # 资源文件
├── build-profile.json5         # 构建配置 & 签名
├── oh-package.json5            # 依赖声明
└── hvigorfile.ts               # 构建脚本
```

## 构建

```bash
# 构建 HAP
hvigorw assembleHap

# 运行（模拟器/真机）
# 在 DevEco Studio 中点击 Run
```

## 注意事项

### ArkTS 严格模式
- 不能使用 `any`/`unknown` 类型
- 对象字面量必须对应明确的 class/interface
- throw 必须使用 Error 子类
- 数组需要显式类型声明

### 真机调试
- 手机需开启开发者模式和USB调试
- Mac和手机需在同一WiFi网络
- API地址使用Mac的局域网IP

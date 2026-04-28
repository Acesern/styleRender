# styleRender 项目结构说明

`styleRender` 是一个 macOS SwiftUI App，用 SceneKit 展示 3D 模型，并通过 `SCNTechnique` + Metal 全屏后处理实现类似《Return of the Obra Dinn》的点阵风格化渲染。

## 目录结构

```text
styleRender/
├── PROJECT_STRUCTURE.md
├── styleRender.xcodeproj/
│   ├── project.pbxproj
│   ├── project.xcworkspace/
│   ├── xcshareddata/xcschemes/styleRender.xcscheme
│   └── xcuserdata/
└── styleRender/
    ├── styleRenderApp.swift
    ├── ContentView.swift
    ├── ObraDinnShaders.metal
    └── Assets.xcassets/
        ├── AccentColor.colorset/
        └── AppIcon.appiconset/
```

## 关键文件

### `styleRender/styleRenderApp.swift`

App 入口文件，创建主窗口并加载 `ContentView`。

### `styleRender/ContentView.swift`

当前主要业务代码都在这个文件里，包含：

- SwiftUI 主界面和左侧控制栏
- 默认模型选择
- 用户模型导入
- SceneKit 视图封装
- SceneKit 场景、相机、灯光、材质设置
- `SCNTechnique` 后处理管线配置
- 默认内置模型生成逻辑

主要类型：

- `ContentView`：主 UI，包含模型选择、导入按钮、色板、抖动密度、对比度、网格开关。
- `ModelSource`：模型来源枚举，目前包含潜水头盔、雕像、罗盘、用户导入模型。
- `RenderPalette`：色板枚举。当前色板只影响点阵/油墨颜色，背景保持纸色。
- `ObraDinnSceneView`：`NSViewRepresentable`，把 `SCNView` 嵌入 SwiftUI。
- `ObraDinnSceneView.Coordinator`：维护 SceneKit 场景、相机、灯光、模型加载和 technique 参数更新。
- `BuiltInModels`：用 SceneKit 几何体程序化生成默认模型。
- `SceneLoader`：加载用户选择的 `scn / dae / obj / usdz / usdc / usd` 模型。

### `styleRender/ObraDinnShaders.metal`

Metal 后处理 shader 文件。

当前渲染不是改模型贴图，而是：

1. SceneKit 先正常渲染 3D 场景到离屏 `sceneColor` 和 `sceneDepth`。
2. `SCNTechnique` 执行全屏 `DRAW_QUAD`。
3. `obraDinnFragment` 读取颜色和深度纹理。
4. 在像素阶段做灰度、色阶量化、点阵抖动、深度边缘描边、色板油墨映射。

主要函数：

- `obraDinnVertex`：全屏 quad 顶点 shader。
- `bayer8`：8x8 Bayer 阈值矩阵。
- `hash21`：用于打散高密度抖动下的周期网格。
- `obraDinnFragment`：主要风格化逻辑。

传入 shader 的参数：

- `ditherScale`：抖动密度。
- `contrast`：对比度。
- `paletteIndex`：色板编号。

这些参数由 `ContentView.swift` 中的 `SCNTechnique` symbol 逐个更新。

### `styleRender/Assets.xcassets`

Xcode 资源目录，目前包含：

- App 图标
- Accent Color

## 渲染流程

当前渲染管线如下：

```text
SwiftUI 控制栏
    ↓
ObraDinnSceneView.updateNSView
    ↓
更新 SCNTechnique symbols
    ↓
SceneKit DRAW_SCENE
    ↓
离屏 sceneColor / sceneDepth
    ↓
Metal DRAW_QUAD
    ↓
obraDinnFragment 像素后处理
    ↓
显示到窗口
```

`SCNTechnique` 定义在 `ContentView.swift` 的 `makeObraDinnTechnique()` 中，包含两个 pass：

- `scene`：渲染完整 SceneKit 场景到离屏颜色和深度 target。
- `stylize`：绘制全屏 quad，调用 Metal shader 输出最终画面。

## UI 控制项

### 模型

默认模型是程序化生成的 SceneKit 几何体：

- 潜水头盔
- 雕像
- 罗盘

用户可以通过“导入模型”选择外部模型文件。导入后会调用 `SCNScene(url:)` 加载，并做归一化缩放和居中。

### 色板

色板当前只影响点阵/油墨颜色：

- 纸张黑白
- 琥珀终端
- 绿色荧光

背景纸色保持固定，不随色板变化。

### 抖动密度

控制点阵颗粒密度。shader 中会根据密度调整采样 cell size，并在高密度时混入噪声来降低明显网格感。

### 对比度

控制后处理阶段灰度值的压缩/扩张，影响明暗分层。

### 显示网格轮廓

当前同时影响：

- SceneKit 材质 `fillMode`
- `SCNView.debugOptions = [.showWireframe]`

这个选项主要用于调试模型网格。

## 构建和运行

在 Xcode 中：

1. 打开 `styleRender.xcodeproj`
2. 选择运行目标 `My Mac`
3. 点击 Run

如果出现 launchd / RunningBoard 启动失败，优先检查：

- `Edit Scheme > Run > Diagnostics` 中关闭 View Debugging
- Debug 阶段临时关闭 Hardened Runtime
- Clean Build Folder 后重试

如果 Metal 编译失败，确认已安装 Metal Toolchain：

```bash
xcodebuild -downloadComponent MetalToolchain
```

## 临时分享 App

临时发给别人测试：

1. Xcode 中执行 `Product > Build`
2. 在 Products 中找到 `styleRender.app`
3. 右键 `Show in Finder`
4. 压缩 `.app` 后发送

对方如果遇到无法验证开发者，可以右键 App 选择“打开”，或执行：

```bash
xattr -dr com.apple.quarantine /path/to/styleRender.app
```

## 后续建议

当前代码集中在 `ContentView.swift`，后续如果功能继续变多，建议拆分：

- `Views/ContentView.swift`
- `Views/ObraDinnSceneView.swift`
- `Rendering/SceneTechnique.swift`
- `Rendering/RenderPalette.swift`
- `Models/BuiltInModels.swift`
- `Models/SceneLoader.swift`

如果未来需要更强控制力，可以从 `SCNTechnique` 迁移到 `MTKView + SCNRenderer + 自定义 Metal render pass`。这样 uniform buffer、后处理 target、debug 输出都能完全自行管理。

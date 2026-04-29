//
//  ContentView.swift
//  styleRender
//
//  Created by 胡凯凡 on 2026/4/26.
//

import AppKit
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedModel: ModelSource = .helmet
    @State private var importedModelURL: URL?
    @State private var palette: RenderPalette = .paper
    @State private var renderStyle: RenderStyle = .obraDinn
    @State private var ditherScale = 72.0
    @State private var hatchSpacing = 8.0
    @State private var contrast = 1.35
    @State private var showsWireframe = false
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack(alignment: .topLeading) {
                ObraDinnSceneView(
                    selectedModel: selectedModel,
                    importedModelURL: importedModelURL,
                    palette: palette,
                    renderStyle: renderStyle,
                    ditherScale: Float(ditherScale),
                    hatchSpacing: Float(hatchSpacing),
                    contrast: Float(contrast),
                    showsWireframe: showsWireframe
                )
                .ignoresSafeArea()

                titleOverlay
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好") {
                importError = nil
            }
        } message: {
            Text(importError ?? "")
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("风格化渲染")
                        .font(.title2.weight(.semibold))
                    Text(renderStyle == .obraDinn
                         ? "单色高反差、棋盘抖动、淡色纸底，模拟《Return of the Obra Dinn》的低位深复古观感。"
                         : "密集交叉阴影线，模拟 Gustave Doré《神曲》铜版画风格。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("渲染风格", selection: $renderStyle) {
                    ForEach(RenderStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("模型", selection: $selectedModel) {
                    ForEach(ModelSource.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.inline)

                Button {
                    chooseModelFile()
                } label: {
                    Label("导入模型", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                if let importedModelURL {
                    Text(importedModelURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Divider()

                Picker("色板", selection: $palette) {
                    ForEach(RenderPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }

                if renderStyle == .obraDinn {
                    VStack(alignment: .leading) {
                        Text("抖动密度 \(Int(ditherScale))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $ditherScale, in: 36...140)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("线条间距 \(hatchSpacing, specifier: "%.1f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $hatchSpacing, in: 3.0...18.0)
                    }
                }

                VStack(alignment: .leading) {
                    Text("对比度 \(contrast, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $contrast, in: 0.85...2.1)
                }

                Toggle("显示网格轮廓", isOn: $showsWireframe)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 62)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.visible)
        .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedModel.title)
                .font(.headline.weight(.semibold))
            Text("拖拽旋转，滚轮缩放")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(18)
    }

    private func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SceneLoader.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard SceneLoader.canTryLoading(url: url) else {
            importError = "暂时支持 scn、dae、obj、usdz、usdc、usd 文件。"
            return
        }

        importedModelURL = url
        selectedModel = .imported
    }
}

enum ModelSource: String, CaseIterable, Identifiable {
    case helmet
    case statue
    case compass
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helmet:
            "默认模型：潜水头盔"
        case .statue:
            "默认模型：雕像"
        case .compass:
            "默认模型：罗盘"
        case .imported:
            "用户导入模型"
        }
    }
}

enum RenderStyle: String, CaseIterable, Identifiable {
    case obraDinn
    case dore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obraDinn:
            "Obra Dinn"
        case .dore:
            "Doré 版画"
        }
    }
}

enum RenderPalette: String, CaseIterable, Identifiable {
    case paper
    case amber
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper:
            "纸张黑白"
        case .amber:
            "琥珀终端"
        case .green:
            "绿色荧光"
        }
    }

    var foreground: NSColor {
        switch self {
        case .paper:
            NSColor(calibratedRed: 0.06, green: 0.055, blue: 0.045, alpha: 1)
        case .amber:
            NSColor(calibratedRed: 0.13, green: 0.075, blue: 0.015, alpha: 1)
        case .green:
            NSColor(calibratedRed: 0.025, green: 0.12, blue: 0.075, alpha: 1)
        }
    }

    var background: NSColor {
        switch self {
        case .paper:
            NSColor(calibratedRed: 0.87, green: 0.82, blue: 0.68, alpha: 1)
        case .amber:
            NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.22, alpha: 1)
        case .green:
            NSColor(calibratedRed: 0.65, green: 0.92, blue: 0.69, alpha: 1)
        }
    }

    var shaderIndex: Float {
        switch self {
        case .paper:
            0
        case .amber:
            1
        case .green:
            2
        }
    }
}

struct ObraDinnSceneView: NSViewRepresentable {
    let selectedModel: ModelSource
    let importedModelURL: URL?
    let palette: RenderPalette
    let renderStyle: RenderStyle
    let ditherScale: Float
    let hatchSpacing: Float
    let contrast: Float
    let showsWireframe: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = true
        view.scene = context.coordinator.scene
        context.coordinator.configureSceneView(view)
        return view
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        context.coordinator.update(
            sceneView: scnView,
            selectedModel: selectedModel,
            importedModelURL: importedModelURL,
            palette: palette,
            renderStyle: renderStyle,
            ditherScale: ditherScale,
            hatchSpacing: hatchSpacing,
            contrast: contrast,
            showsWireframe: showsWireframe
        )
    }

    final class Coordinator {
        let scene = SCNScene()

        private let modelRoot = SCNNode()
        private let cameraNode = SCNNode()
        private var currentModel: ModelSource?
        private var currentURL: URL?
        private var currentRenderStyle: RenderStyle = .obraDinn

        init() {
            scene.rootNode.addChildNode(modelRoot)
            setupCamera()
            setupLighting()
        }

        func configureSceneView(_ view: SCNView) {
            view.backgroundColor = RenderPalette.paper.background
            view.pointOfView = cameraNode
            view.technique = Self.makeObraDinnTechnique()
        }

        func update(
            sceneView: SCNView,
            selectedModel: ModelSource,
            importedModelURL: URL?,
            palette: RenderPalette,
            renderStyle: RenderStyle,
            ditherScale: Float,
            hatchSpacing: Float,
            contrast: Float,
            showsWireframe: Bool
        ) {
            if renderStyle != currentRenderStyle {
                currentRenderStyle = renderStyle
                switch renderStyle {
                case .obraDinn:
                    sceneView.technique = Self.makeObraDinnTechnique()
                case .dore:
                    sceneView.technique = Self.makeDoréTechnique()
                }
            }

            switch renderStyle {
            case .obraDinn:
                sceneView.backgroundColor = RenderPalette.paper.background
                sceneView.technique?.setValue(ditherScale, forKey: "ditherScale")
                sceneView.technique?.setValue(contrast, forKey: "contrast")
                sceneView.technique?.setValue(palette.shaderIndex, forKey: "paletteIndex")
            case .dore:
                sceneView.backgroundColor = NSColor(calibratedRed: 0.867, green: 0.831, blue: 0.690, alpha: 1)
                sceneView.technique?.setValue(hatchSpacing, forKey: "hatchSpacing")
                sceneView.technique?.setValue(contrast, forKey: "contrast")
                sceneView.technique?.setValue(palette.shaderIndex, forKey: "paletteIndex")
            }

            sceneView.debugOptions = showsWireframe ? [.showWireframe] : []
            sceneView.needsDisplay = true

            if currentModel != selectedModel || currentURL != importedModelURL {
                loadModel(selectedModel, importedModelURL: importedModelURL)
                currentModel = selectedModel
                currentURL = importedModelURL
            }

            modelRoot.enumerateChildNodes { node, _ in
                guard node.geometry != nil else {
                    return
                }

                node.geometry?.materials = [Self.sceneMaterial(showsWireframe: showsWireframe)]
            }
        }

        private func setupCamera() {
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.usesOrthographicProjection = true
            cameraNode.camera?.orthographicScale = 4.2
            cameraNode.position = SCNVector3(0, 1.15, 6)
            cameraNode.eulerAngles = SCNVector3(-0.15, 0, 0)
            scene.rootNode.addChildNode(cameraNode)
        }

        private func setupLighting() {
            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .directional
            keyLight.light?.intensity = 950
            keyLight.eulerAngles = SCNVector3(-0.75, 0.65, 0.15)
            scene.rootNode.addChildNode(keyLight)

            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .ambient
            fillLight.light?.intensity = 220
            scene.rootNode.addChildNode(fillLight)
        }

        private func loadModel(_ model: ModelSource, importedModelURL: URL?) {
            modelRoot.childNodes.forEach { $0.removeFromParentNode() }

            let node: SCNNode
            switch model {
            case .helmet:
                node = BuiltInModels.divingHelmet()
            case .statue:
                node = BuiltInModels.statue()
            case .compass:
                node = BuiltInModels.compass()
            case .imported:
                node = SceneLoader.load(url: importedModelURL) ?? BuiltInModels.divingHelmet()
            }

            let container = SCNNode()
            container.addChildNode(node)
            normalize(container)
            modelRoot.addChildNode(container)
        }

        private func normalize(_ node: SCNNode) {
            let bounds = node.boundingBox
            let min = bounds.min
            let maxBounds = bounds.max
            let size = SCNVector3(maxBounds.x - min.x, maxBounds.y - min.y, maxBounds.z - min.z)
            let largest = Swift.max(size.x, Swift.max(size.y, size.z))

            guard largest > 0 else {
                return
            }

            let center = SCNVector3(
                (min.x + maxBounds.x) * 0.5,
                (min.y + maxBounds.y) * 0.5,
                (min.z + maxBounds.z) * 0.5
            )

            node.scale = SCNVector3(2.45 / largest, 2.45 / largest, 2.45 / largest)
            node.position = SCNVector3(-center.x * node.scale.x, -center.y * node.scale.y, -center.z * node.scale.z)
            node.eulerAngles = SCNVector3(-0.18, 0.58, 0)
        }

        private static func sceneMaterial(showsWireframe: Bool) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.isDoubleSided = true
            material.diffuse.contents = NSColor(calibratedWhite: 0.82, alpha: 1)
            material.ambient.contents = NSColor(calibratedWhite: 0.18, alpha: 1)
            material.specular.contents = NSColor.black
            material.emission.contents = NSColor.black
            material.fillMode = showsWireframe ? .lines : .fill
            return material
        }

        private static func makeObraDinnTechnique() -> SCNTechnique? {
            let dictionary: [String: Any] = [
                "sequence": ["scene", "stylize"],
                "targets": [
                    "sceneColor": [
                        "type": "color",
                        "format": "rgba8"
                    ],
                    "sceneDepth": [
                        "type": "depth",
                        "format": "depth32f"
                    ]
                ],
                "symbols": [
                    "ditherScale": [
                        "type": "float"
                    ],
                    "contrast": [
                        "type": "float"
                    ],
                    "paletteIndex": [
                        "type": "float"
                    ]
                ],
                "passes": [
                    "scene": [
                        "draw": "DRAW_SCENE",
                        "outputs": [
                            "color": "sceneColor",
                            "depth": "sceneDepth"
                        ],
                        "colorStates": [
                            "clear": true,
                            "clearColor": "1 1 1 1"
                        ],
                        "depthStates": [
                            "clear": true,
                            "enableWrite": true,
                            "enableRead": true
                        ]
                    ],
                    "stylize": [
                        "draw": "DRAW_QUAD",
                        "metalVertexShader": "obraDinnVertex",
                        "metalFragmentShader": "obraDinnFragment",
                        "inputs": [
                            "colorSampler": [
                                "target": "sceneColor",
                                "minificationFilter": "nearest",
                                "magnificationFilter": "nearest",
                                "mipFilter": "none",
                                "wrapS": "clamp",
                                "wrapT": "clamp"
                            ],
                            "depthSampler": [
                                "target": "sceneDepth",
                                "minificationFilter": "nearest",
                                "magnificationFilter": "nearest",
                                "mipFilter": "none",
                                "wrapS": "clamp",
                                "wrapT": "clamp"
                            ],
                            "ditherScale": "ditherScale",
                            "contrast": "contrast",
                            "paletteIndex": "paletteIndex"
                        ],
                        "outputs": [
                            "color": "COLOR"
                        ],
                        "colorStates": [
                            "clear": true
                        ],
                        "depthStates": [
                            "enableRead": false,
                            "enableWrite": false
                        ]
                    ]
                ]
            ]

            return SCNTechnique(dictionary: dictionary)
        }

        private static func makeDoréTechnique() -> SCNTechnique? {
            let dictionary: [String: Any] = [
                "sequence": ["scene", "stylize"],
                "targets": [
                    "sceneColor": [
                        "type": "color",
                        "format": "rgba8"
                    ],
                    "sceneDepth": [
                        "type": "depth",
                        "format": "depth32f"
                    ]
                ],
                "symbols": [
                    "hatchSpacing": [
                        "type": "float"
                    ],
                    "contrast": [
                        "type": "float"
                    ],
                    "paletteIndex": [
                        "type": "float"
                    ]
                ],
                "passes": [
                    "scene": [
                        "draw": "DRAW_SCENE",
                        "outputs": [
                            "color": "sceneColor",
                            "depth": "sceneDepth"
                        ],
                        "colorStates": [
                            "clear": true,
                            "clearColor": "1 1 1 1"
                        ],
                        "depthStates": [
                            "clear": true,
                            "enableWrite": true,
                            "enableRead": true
                        ]
                    ],
                    "stylize": [
                        "draw": "DRAW_QUAD",
                        "metalVertexShader": "obraDinnVertex",
                        "metalFragmentShader": "doreFragment",
                        "inputs": [
                            "colorSampler": [
                                "target": "sceneColor",
                                "minificationFilter": "nearest",
                                "magnificationFilter": "nearest",
                                "mipFilter": "none",
                                "wrapS": "clamp",
                                "wrapT": "clamp"
                            ],
                            "depthSampler": [
                                "target": "sceneDepth",
                                "minificationFilter": "nearest",
                                "magnificationFilter": "nearest",
                                "mipFilter": "none",
                                "wrapS": "clamp",
                                "wrapT": "clamp"
                            ],
                            "hatchSpacing": "hatchSpacing",
                            "contrast": "contrast",
                            "paletteIndex": "paletteIndex"
                        ],
                        "outputs": [
                            "color": "COLOR"
                        ],
                        "colorStates": [
                            "clear": true
                        ],
                        "depthStates": [
                            "enableRead": false,
                            "enableWrite": false
                        ]
                    ]
                ]
            ]

            return SCNTechnique(dictionary: dictionary)
        }
    }
}

enum BuiltInModels {
    static func divingHelmet() -> SCNNode {
        let root = SCNNode()

        let dome = SCNSphere(radius: 0.9)
        dome.segmentCount = 48
        let domeNode = SCNNode(geometry: dome)
        domeNode.scale = SCNVector3(1.08, 0.9, 1.0)
        root.addChildNode(domeNode)

        let faceRing = SCNTorus(ringRadius: 0.56, pipeRadius: 0.08)
        faceRing.ringSegmentCount = 48
        faceRing.pipeSegmentCount = 12
        let faceRingNode = SCNNode(geometry: faceRing)
        faceRingNode.position = SCNVector3(0, 0.03, 0.78)
        root.addChildNode(faceRingNode)

        let glass = SCNCylinder(radius: 0.46, height: 0.04)
        glass.radialSegmentCount = 48
        let glassNode = SCNNode(geometry: glass)
        glassNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        glassNode.position = SCNVector3(0, 0.03, 0.82)
        root.addChildNode(glassNode)

        for x in [-0.72, 0.72] {
            let port = SCNTorus(ringRadius: 0.18, pipeRadius: 0.045)
            let portNode = SCNNode(geometry: port)
            portNode.position = SCNVector3(Float(x), 0.08, 0.4)
            portNode.eulerAngles = SCNVector3(0, Float.pi / 8 * Float(x < 0 ? -1.0 : 1.0), 0)
            root.addChildNode(portNode)
        }

        let collar = SCNTorus(ringRadius: 0.78, pipeRadius: 0.12)
        let collarNode = SCNNode(geometry: collar)
        collarNode.position = SCNVector3(0, -0.74, 0)
        collarNode.scale = SCNVector3(1.1, 0.2, 1.1)
        root.addChildNode(collarNode)

        return root
    }

    static func statue() -> SCNNode {
        let root = SCNNode()

        let head = SCNSphere(radius: 0.36)
        head.segmentCount = 32
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.86, 0)
        root.addChildNode(headNode)

        let body = SCNCapsule(capRadius: 0.38, height: 1.25)
        body.radialSegmentCount = 32
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.05, 0)
        bodyNode.scale = SCNVector3(0.9, 1.0, 0.7)
        root.addChildNode(bodyNode)

        let pedestal = SCNBox(width: 1.28, height: 0.36, length: 1.0, chamferRadius: 0.05)
        let pedestalNode = SCNNode(geometry: pedestal)
        pedestalNode.position = SCNVector3(0, -0.78, 0)
        root.addChildNode(pedestalNode)

        for x in [-0.48, 0.48] {
            let arm = SCNCapsule(capRadius: 0.11, height: 0.9)
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(Float(x), 0.14, 0)
            armNode.eulerAngles = SCNVector3(0.0, 0.0, Float.pi / 8 * Float(x < 0 ? -1.0 : 1.0))
            root.addChildNode(armNode)
        }

        return root
    }

    static func compass() -> SCNNode {
        let root = SCNNode()

        let caseRing = SCNTorus(ringRadius: 0.82, pipeRadius: 0.075)
        caseRing.ringSegmentCount = 64
        let caseNode = SCNNode(geometry: caseRing)
        caseNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        root.addChildNode(caseNode)

        let face = SCNCylinder(radius: 0.78, height: 0.05)
        face.radialSegmentCount = 64
        let faceNode = SCNNode(geometry: face)
        root.addChildNode(faceNode)

        let needle = SCNBox(width: 0.12, height: 0.05, length: 1.35, chamferRadius: 0.02)
        let needleNode = SCNNode(geometry: needle)
        needleNode.position = SCNVector3(0, 0.06, 0)
        needleNode.eulerAngles = SCNVector3(0, Float.pi / 5, 0)
        root.addChildNode(needleNode)

        let hub = SCNSphere(radius: 0.14)
        let hubNode = SCNNode(geometry: hub)
        hubNode.position = SCNVector3(0, 0.1, 0)
        root.addChildNode(hubNode)

        return root
    }
}

enum SceneLoader {
    static let supportedExtensions = ["scn", "dae", "obj", "usdz", "usdc", "usd"]

    static func canTryLoading(url: URL) -> Bool {
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func load(url: URL?) -> SCNNode? {
        guard let url else {
            return nil
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let scene = try? SCNScene(url: url, options: [
            .checkConsistency: true,
            .convertToYUp: true
        ]) else {
            return nil
        }

        let root = SCNNode()
        scene.rootNode.childNodes.forEach { child in
            root.addChildNode(child.clone())
        }
        return root
    }
}

private extension NSColor {
    var scnVector3: SCNVector3 {
        let converted = usingColorSpace(.deviceRGB) ?? self
        return SCNVector3(
            Float(converted.redComponent),
            Float(converted.greenComponent),
            Float(converted.blueComponent)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

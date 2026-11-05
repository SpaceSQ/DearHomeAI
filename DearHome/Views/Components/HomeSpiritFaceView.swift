import SwiftUI

/// Dear Home AI 暖炉屋灵的五种核心交互神态
public enum HomeSpiritInteractionState: String, CaseIterable, Identifiable {
    case idle = "Idle"           // 静候：屋檐平稳，双窗微光呼吸，壁炉恒温微笑
    case listening = "Listening" // 倾听：屋檐微扬如敞开家门，壁炉化作室内声波涟漪
    case thinking = "Thinking"   // 思考：双窗轻柔交替闪烁，屋内升腾空间记忆星尘
    case talking = "Talking"     // 交谈：壁炉暖弧随语音韵律灵动明暗起伏
    case task = "Task Mode"      // 任务：切入鼠尾草绿与香槟金包豪斯几何网格，执行空间与生活规划
    
    public var id: String { rawValue }
}

/// Dear Home AI 核心视觉组件：暖炉屋灵 (The Hearth Spirit)
public struct HomeSpiritFaceView: View {
    public var state: HomeSpiritInteractionState
    public var size: CGFloat = 220
    
    public init(state: HomeSpiritInteractionState = .idle, size: CGFloat = 220) {
        self.state = state
        self.size = size
    }
    
    // MARK: - 色彩体系 (松木深空 + 琥珀壁炉金 + 鼠尾草绿)
    private var primaryAmber: Color {
        state == .task
            ? Color(red: 0.56, green: 0.82, blue: 0.68) // 任务态：鼠尾草绿 (Sage Green)
            : Color(red: 1.00, green: 0.73, blue: 0.32) // 常规态：壁炉琥珀金 (Hearth Amber)
    }
    
    private var secondaryGlow: Color {
        state == .task
            ? Color(red: 0.92, green: 0.84, blue: 0.58) // 香槟金几何光
            : Color(red: 0.98, green: 0.48, blue: 0.20) // 暖炉深橘光
    }
    
    private var sageAccent: Color {
        Color(red: 0.52, green: 0.78, blue: 0.65)
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            
            ZStack {
                // 1. 底层空间暖雾背景光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                primaryAmber.opacity(state == .listening ? 0.28 : 0.18),
                                sageAccent.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: size * 0.08,
                            endRadius: size * 0.56
                        )
                    )
                    .scaleEffect(1.0 + 0.05 * sin(t * 2.0))
                
                // 2. 任务态专属：包豪斯空间建筑几何网格环
                if state == .task {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: [primaryAmber.opacity(0.6), secondaryGlow.opacity(0.2), primaryAmber.opacity(0.6)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                        .frame(width: size * 0.78, height: size * 0.78)
                        .rotationEffect(.degrees(t * 14))
                        .transition(.scale.combined(with: .opacity))
                }
                
                // 3. 屋内升腾的微光星尘 (温度、空气与记忆粒子)
                hearthStardustLayer(time: t)
                
                // 4. 守护双眉：黄金比例 A 字北欧屋檐 (Protective A-Frame Roofline)
                roofEyebrowLayer(time: t)
                
                // 5. 温柔双眼：两扇亮起暖光的圆角小窗 (Warm Glowing Windows)
                windowEyesLayer(time: t)
                
                // 6. 治愈微笑：底部新月形壁炉暖弧 (Hearth Smile Arc)
                hearthSmileLayer(time: t)
            }
            .frame(width: size, height: size)
            .animation(.spring(response: 0.6, dampingFraction: 0.78), value: state)
        }
    }
    
    // MARK: - 子图层 1：A字守护屋檐 (双眉)
    @ViewBuilder
    private func roofEyebrowLayer(time: Double) -> some View {
        let liftOffset: CGFloat = {
            switch state {
            case .idle:      return CGFloat(sin(time * 1.6)) * (size * 0.01)
            case .listening: return -size * 0.032 // 倾听时屋檐上扬，如同敞开大门欢迎
            case .thinking:  return -size * 0.015
            case .talking:   return CGFloat(sin(time * 5.0)) * (size * 0.012)
            case .task:      return -size * 0.022
            }
        }()
        
        let roofPitchAngle: Double = state == .listening ? -3.0 : (state == .thinking ? 2.0 : 0.0)
        
        HearthRoofShape()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.72),
                        primaryAmber,
                        secondaryGlow
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: size * 0.048, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size * 0.64, height: size * 0.28)
            .shadow(color: primaryAmber.opacity(0.55), radius: size * 0.05)
            .rotationEffect(.degrees(roofPitchAngle))
            .offset(y: -size * 0.14 + liftOffset)
    }
    
    // MARK: - 子图层 2：双窗微光眼眸 (双眼)
    @ViewBuilder
    private func windowEyesLayer(time: Double) -> some View {
        let leftWindowOpacity: Double = state == .thinking
            ? (0.55 + 0.45 * sin(time * 5.5))
            : (0.88 + 0.12 * sin(time * 2.2))
        let rightWindowOpacity: Double = state == .thinking
            ? (0.55 + 0.45 * cos(time * 5.5))
            : (0.88 + 0.12 * sin(time * 2.2))
        
        let eyeScaleY: CGFloat = state == .listening ? 1.15 : (state == .talking ? 0.92 + 0.12 * CGFloat( abs(sin(time * 6.0)) ) : 1.0)
        
        HStack(spacing: size * 0.13) {
            // 左窗眼
            RoundedRectangle(cornerRadius: size * 0.028, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), primaryAmber],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.088, height: size * 0.105)
                .scaleEffect(x: 1.0, y: eyeScaleY)
                .opacity(leftWindowOpacity)
                .shadow(color: primaryAmber.opacity(0.8), radius: size * 0.04)
            
            // 右窗眼
            RoundedRectangle(cornerRadius: size * 0.028, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), primaryAmber],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.088, height: size * 0.105)
                .scaleEffect(x: 1.0, y: eyeScaleY)
                .opacity(rightWindowOpacity)
                .shadow(color: primaryAmber.opacity(0.8), radius: size * 0.04)
        }
        .offset(y: size * 0.02)
    }
    
    // MARK: - 子图层 3：壁炉微笑暖弧 (嘴部与炉火)
    @ViewBuilder
    private func hearthSmileLayer(time: Double) -> some View {
        let talkPulse: CGFloat = state == .talking
            ? (1.0 + 0.22 * CGFloat(abs(sin(time * 8.5))))
            : (state == .listening ? 1.08 + 0.06 * CGFloat(sin(time * 4.0)) : 1.0)
        
        ZStack {
            // 倾听态专属：室内声波同心暖弧涟漪
            if state == .listening {
                HearthSmileArcShape(curvature: 0.85)
                    .stroke(primaryAmber.opacity(0.35), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                    .frame(width: size * 0.44, height: size * 0.13)
                    .scaleEffect(1.08 + 0.08 * CGFloat(sin(time * 4.5)))
                    .offset(y: size * 0.23)
            }
            
            // 主壁炉微笑暖弧
            HearthSmileArcShape(curvature: state == .talking ? 1.05 : 0.88)
                .stroke(
                    LinearGradient(
                        colors: [
                            secondaryGlow,
                            primaryAmber,
                            Color(red: 1.0, green: 0.94, blue: 0.78),
                            primaryAmber,
                            secondaryGlow
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.042, lineCap: .round)
                )
                .frame(width: size * 0.36, height: size * 0.11)
                .scaleEffect(x: 1.0, y: talkPulse)
                .shadow(color: primaryAmber.opacity(0.75), radius: size * 0.045)
                .offset(y: size * 0.20)
        }
    }
    
    // MARK: - 子图层 4：室内升腾的微光星尘与鼠尾草绿粒子
    @ViewBuilder
    private func hearthStardustLayer(time: Double) -> some View {
        let speedMultiplier: Double = (state == .thinking || state == .task) ? 2.2 : 1.0
        ForEach(0..<8, id: \.self) { idx in
            let phase = (time * 0.45 * speedMultiplier + Double(idx) * 0.37).truncatingRemainder(dividingBy: 1.0)
            let horizontalSpread = sin(Double(idx) * 1.9 + time * 1.2) * Double(size * 0.18)
            let verticalTravel = Double(size * 0.18) - phase * Double(size * 0.38)
            let isSageParticle = idx % 3 == 0
            
            Circle()
                .fill(isSageParticle ? sageAccent : primaryAmber)
                .frame(width: size * (isSageParticle ? 0.022 : 0.018),
                       height: size * (isSageParticle ? 0.022 : 0.018))
                .offset(x: CGFloat(horizontalSpread), y: CGFloat(verticalTravel))
                .opacity((1.0 - phase) * 0.75)
                .blur(radius: 0.6)
        }
    }
}

// MARK: - 自定义几何路径：北欧黄金比例 A 字屋檐
private struct HearthRoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leftEave = CGPoint(x: rect.minX, y: rect.maxY)
        let ridgePeak = CGPoint(x: rect.midX, y: rect.minY)
        let rightEave = CGPoint(x: rect.maxX, y: rect.maxY)
        
        path.move(to: leftEave)
        // 带有轻微温润弧度的建筑斜屋顶
        path.addQuadCurve(
            to: ridgePeak,
            control: CGPoint(x: rect.width * 0.26, y: rect.height * 0.42)
        )
        path.addQuadCurve(
            to: rightEave,
            control: CGPoint(x: rect.width * 0.74, y: rect.height * 0.42)
        )
        return path
    }
}

// MARK: - 自定义几何路径：壁炉微笑暖弧
private struct HearthSmileArcShape: Shape {
    var curvature: CGFloat
    
    var animatableData: CGFloat {
        get { curvature }
        set { curvature = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.minY)
        let end = CGPoint(x: rect.maxX, y: rect.minY)
        let control = CGPoint(x: rect.midX, y: rect.maxY * curvature)
        
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}
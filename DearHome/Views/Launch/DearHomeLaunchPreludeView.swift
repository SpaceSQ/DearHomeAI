import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Dear Home AI 3秒多幕进入动画：《晚归亮灯 · 炉火生温 (Coming Home)》
public struct DearHomeLaunchPreludeView: View {
    public var onFinished: () -> Void
    
    // 三幕动画状态控制
    @State private var roofTrimProgress: CGFloat = 0.0      // 1.0s: 屋檐流光绘制进度
    @State private var leftWindowLit: Bool = false          // 1.45s: 左窗亮灯
    @State private var rightWindowLit: Bool = false         // 1.65s: 右窗亮灯
    @State private var hearthSmileLit: Bool = false         // 2.1s: 壁炉微笑点亮
    @State private var showBrandTitle: Bool = false         // 2.2s: 标题与空间暖光绽放
    @State private var overallOpacity: Double = 1.0
    @State private var hasCompleted: Bool = false
    
    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }
    
    public var body: some View {
        ZStack {
            // 1. 松木深空与午夜岩板底色 (#0F171E -> #1A2630)
            LinearGradient(
                colors: [
                    Color(red: 0.059, green: 0.090, blue: 0.118),
                    Color(red: 0.102, green: 0.149, blue: 0.188)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 2. 室内壁炉点燃后的全局环境暖光晕
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.72, blue: 0.30).opacity(hearthSmileLit ? 0.24 : 0.03),
                    Color(red: 0.52, green: 0.78, blue: 0.65).opacity(hearthSmileLit ? 0.08 : 0.0),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 340
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.9), value: hearthSmileLit)
            
            VStack(spacing: 36) {
                Spacer()
                
                // 3. 中央暖炉屋灵多幕构建舞台
                ZStack {
                    // 幕一 & 幕三：漂浮的夜空微尘 -> 转化为室内温暖星尘
                    ForEach(0..<10, id: \.self) { i in
                        Circle()
                            .fill(
                                i % 3 == 0
                                    ? Color(red: 0.52, green: 0.78, blue: 0.65)
                                    : Color(red: 1.0, green: 0.78, blue: 0.42)
                            )
                            .frame(width: CGFloat(3 + (i % 3) * 2), height: CGFloat(3 + (i % 3) * 2))
                            .offset(
                                x: CGFloat((i - 5) * 22),
                                y: hearthSmileLit ? CGFloat(-45 - (i % 4) * 18) : CGFloat(35 + (i % 4) * 14)
                            )
                            .opacity(hearthSmileLit ? 0.75 : 0.25)
                            .animation(.easeInOut(duration: 1.6).delay(Double(i) * 0.05), value: hearthSmileLit)
                    }
                    
                    // 幕二 (1.0s)：流金画笔勾勒 A 字守护屋檐
                    PreludeRoofShape()
                        .trim(from: 0.5 - roofTrimProgress * 0.5, to: 0.5 + roofTrimProgress * 0.5)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.93, blue: 0.75),
                                    Color(red: 1.0, green: 0.73, blue: 0.32),
                                    Color(red: 0.96, green: 0.50, blue: 0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 156, height: 68)
                        .shadow(color: Color(red: 1.0, green: 0.73, blue: 0.32).opacity(0.6), radius: 14)
                        .offset(y: -34)
                    
                    // 幕二 (1.45s & 1.65s)：晚归亮灯 —— 两扇暖窗次第点亮
                    HStack(spacing: 32) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(red: 1.0, green: 0.75, blue: 0.34)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 21, height: 25)
                            .scaleEffect(leftWindowLit ? 1.0 : 0.2)
                            .opacity(leftWindowLit ? 1.0 : 0.0)
                            .shadow(color: Color(red: 1.0, green: 0.73, blue: 0.32).opacity(0.9), radius: 12)
                        
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(red: 1.0, green: 0.75, blue: 0.34)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 21, height: 25)
                            .scaleEffect(rightWindowLit ? 1.0 : 0.2)
                            .opacity(rightWindowLit ? 1.0 : 0.0)
                            .shadow(color: Color(red: 1.0, green: 0.73, blue: 0.32).opacity(0.9), radius: 12)
                    }
                    .offset(y: 6)
                    
                    // 幕三 (2.1s)：壁炉暖弧点亮并上扬为治愈微笑
                    PreludeSmileShape()
                        .trim(from: 0.0, to: hearthSmileLit ? 1.0 : 0.0)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.50, blue: 0.20),
                                    Color(red: 1.0, green: 0.85, blue: 0.52),
                                    Color(red: 0.96, green: 0.50, blue: 0.20)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 88, height: 26)
                        .shadow(color: Color(red: 1.0, green: 0.68, blue: 0.28).opacity(0.8), radius: 12)
                        .offset(y: 48)
                }
                .frame(width: 240, height: 240)
                
                // 4. 品牌主副标题淡入
                VStack(spacing: 10) {
                    Text("Dear Home AI")
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 1.0, green: 0.86, blue: 0.62)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .tracking(1.2)
                    
                    Text("Your Mindful Home Spirit · Warmth On-Device")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.68))
                        .tracking(0.6)
                }
                .opacity(showBrandTitle ? 1.0 : 0.0)
                .offset(y: showBrandTitle ? 0 : 12)
                
                Spacer()
            }
            
            // 5. 右上角 Skip 快捷跳过按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        completePreludeImmediately()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
        }
        .opacity(overallOpacity)
        .onAppear(perform: runThreeSecondChoreography)
    }
    
    // MARK: - 3.0 秒精准时间轴与触觉反馈编排
    private func runThreeSecondChoreography() {
        // 0.1s：第一幕开始，轻柔夜空触感
        triggerImpactHaptic(.soft)
        
        // 0.8s ~ 1.4s：A 字守护屋檐从屋脊向两侧流光展开
        withAnimation(.easeInOut(duration: 0.65).delay(0.65)) {
            roofTrimProgress = 1.0
        }
        
        // 1.35s：左窗亮起琥珀暖光 + 清脆触感
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard !hasCompleted else { return }
            triggerImpactHaptic(.light)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                leftWindowLit = true
            }
        }
        
        // 1.55s：右窗亮起琥珀暖光 + 清脆触感
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            guard !hasCompleted else { return }
            triggerImpactHaptic(.light)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                rightWindowLit = true
            }
        }
        
        // 1.95s：壁炉微笑点燃 + 标题浮现 + 温暖完成震动
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
            guard !hasCompleted else { return }
            triggerNotificationHaptic(.success)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                hearthSmileLit = true
                showBrandTitle = true
            }
        }
        
        // 2.75s ~ 3.0s：整体丝滑淡出，进入主对话界面
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
            guard !hasCompleted else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                overallOpacity = 0.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            completePreludeImmediately()
        }
    }
    
    private func completePreludeImmediately() {
        guard !hasCompleted else { return }
        hasCompleted = true
        onFinished()
    }
    
    private func triggerImpactHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        #endif
    }
}

private struct PreludeRoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.width * 0.26, y: rect.height * 0.42)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.74, y: rect.height * 0.42)
        )
        return path
    }
}

private struct PreludeSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 0.92)
        )
        return path
    }
}
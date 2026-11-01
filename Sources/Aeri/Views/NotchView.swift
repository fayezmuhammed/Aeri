import AppKit
import SwiftUI

/// Order matches the tab bar, so switching knows which way to slide.
enum NotchTab: Int { case nowPlaying, shelf, clipboard, weather }

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published private(set) var tab: NotchTab = .nowPlaying
    /// Direction of the last switch: content slides in from the right when moving right.
    private(set) var movingForward = true
    /// True while a drag hovers over the notch.
    @Published var dropTargeted = false

    func select(_ new: NotchTab) {
        guard new != tab else { return }
        movingForward = new.rawValue > tab.rawValue
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { tab = new }
    }
}

struct NotchView: View {
    static let expandedSize = CGSize(width: 420, height: 170)

    @ObservedObject var state: NotchState
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var shelf: Shelf
    let clipboard: ClipboardHistory
    let weather: Weather
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(radius: state.expanded ? 24 : 10)
                    .fill(.black)
                    .shadow(color: .black.opacity(state.expanded ? 0.35 : 0), radius: 12, y: 4)
                if state.expanded {
                    ExpandedContent(state: state, nowPlaying: nowPlaying, shelf: shelf,
                                    clipboard: clipboard, weather: weather)
                        .padding(.top, notchSize.height + 6)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        // Content arrives just after the shape grows, and leaves quickly.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8))
                                .animation(.easeOut(duration: 0.25).delay(0.08)),
                            removal: .opacity.animation(.easeIn(duration: 0.1))))
                }
            }
            .frame(width: state.expanded ? Self.expandedSize.width : notchSize.width,
                   height: state.expanded ? Self.expandedSize.height : notchSize.height)
            // Files can be dropped anywhere on the notch.
            .onDrop(of: ["public.file-url"],
                    isTargeted: Binding(get: { state.dropTargeted }, set: { state.dropTargeted = $0 })) { providers in
                state.select(.shelf)
                return shelf.accept(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: state.expanded) { _, expanded in
            nowPlaying.setActive(expanded)
            if expanded {
                shelf.prune()
                weather.refreshIfStale()
            }
        }
    }
}

struct ExpandedContent: View {
    @ObservedObject var state: NotchState
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var shelf: Shelf
    let clipboard: ClipboardHistory
    let weather: Weather
    @Namespace private var tabHighlight

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    tabButton(.nowPlaying, icon: "music.note")
                    tabButton(.shelf, icon: shelf.items.isEmpty ? "tray" : "tray.full.fill")
                    tabButton(.clipboard, icon: "doc.on.clipboard")
                    tabButton(.weather, icon: "cloud.sun")
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 14))
                }.buttonStyle(PressableButtonStyle())
            }
            ZStack {
                tabContent
                    .id(state.tab)
                    .transition(slide)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var tabContent: some View {
        switch state.tab {
        case .nowPlaying: NowPlayingView(model: nowPlaying)
        case .shelf: ShelfView(shelf: shelf, state: state)
        case .clipboard: ClipboardView(history: clipboard)
        case .weather: WeatherView(weather: weather)
        }
    }

    /// Small horizontal slide plus fade, in the direction of travel.
    private var slide: AnyTransition {
        let d: CGFloat = state.movingForward ? 28 : -28
        return .asymmetric(
            insertion: .offset(x: d).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
            removal: .offset(x: -d).combined(with: .opacity))
    }

    private func tabButton(_ tab: NotchTab, icon: String) -> some View {
        let selected = state.tab == tab
        return Button { state.select(tab) } label: {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.4))
                .scaleEffect(selected ? 1.12 : 1)
                .frame(width: 30, height: 24)
                .background {
                    // One pill that glides between tabs.
                    if selected {
                        Capsule().fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "pill", in: tabHighlight)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Flat top, rounded bottom corners — blends into the hardware notch.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

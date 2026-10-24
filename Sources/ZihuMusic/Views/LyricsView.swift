import SwiftUI

struct LyricsView: View {
    var lines: [LyricsLine]
    var currentTime: TimeInterval
    private let service = LyricsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歌词")
                .font(.headline)

            if lines.isEmpty {
                ContentUnavailableView("未找到歌词", systemImage: "text.quote", description: Text("支持同名 .lrc、作者 - 标题 .lrc，以及 FLAC 内嵌歌词标签。"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let current = service.currentIndex(in: lines, time: currentTime)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                Text(line.text)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(index == current ? .primary : .secondary)
                                    .id(line.id)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .frame(minHeight: 220, maxHeight: 320)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onChange(of: current) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(lines[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

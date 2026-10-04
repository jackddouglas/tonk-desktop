import MarkdownUI
import SwiftUI

struct MessageMarkdown: View {
  let text: String

  var body: some View {
    Markdown(text)
      .markdownTheme(.gitHub)
      .markdownTextStyle {
        FontSize(NSFont.systemFontSize)
        ForegroundColor(.primary)
        BackgroundColor(.clear)
      }
      .markdownBlockStyle(\.table) { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .fixedSize(horizontal: true, vertical: false)
            .markdownTableBorderStyle(.init(color: Color(nsColor: .separatorColor)))
            .markdownTableBackgroundStyle(
              .alternatingRows(.clear, Color(nsColor: .quaternaryLabelColor).opacity(0.25)))
        }
        .markdownMargin(top: 0, bottom: 16)
      }
      .textSelection(.enabled)
  }
}

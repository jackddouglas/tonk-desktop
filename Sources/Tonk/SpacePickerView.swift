import HarnessCore
import SwiftUI

struct SpacePickerView: View {
  @ObservedObject var runtime: RuntimeModel
  @Binding var search: String
  var onOpen: (TonkSpace) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let error = runtime.catalogError {
        VStack(alignment: .leading, spacing: 8) {
          Text("Couldn’t load spaces: \(error)").font(.callout).textSelection(.enabled)
          Button("Try again") { Task { await runtime.refreshSpaces() } }
        }.padding(.horizontal, 20)
      }
      if runtime.catalogLoading || (!runtime.catalogLoaded && runtime.catalogError == nil) {
        ProgressView("Loading spaces…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if runtime.spaces.isEmpty && runtime.catalogError != nil {
        ContentUnavailableView(
          "Spaces unavailable", systemImage: "exclamationmark.circle",
          description: Text("Use refresh to try again."))
      } else if runtime.spaces.isEmpty {
        ContentUnavailableView(
          "No spaces yet", systemImage: "square.grid.2x2",
          description: Text("Create a space in Tonk, then refresh to see it here."))
      } else {
        let matching = runtime.spaces.filter {
          search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        }
        if matching.isEmpty {
          VStack(spacing: 12) {
            ContentUnavailableView.search(text: search)
            Button("Clear search") { search = "" }.nativeControl()
          }
        } else {
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
              ForEach(matching) { space in
                Button {
                  onOpen(space)
                } label: {
                  VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "square.grid.2x2").font(.title).foregroundStyle(.secondary)
                    Text(space.title).font(.headline).lineLimit(2).help(space.title)
                    HStack {
                      Text("Open space").font(.callout).foregroundStyle(.secondary)
                      Spacer()
                      Image(systemName: "chevron.right").font(.caption)
                    }
                  }
                  .padding(20).frame(maxWidth: .infinity, minHeight: 135, alignment: .leading)
                  .background(
                    Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(
                      Color(nsColor: .separatorColor), lineWidth: 0.5)
                  }
                  .contentShape(RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(SpaceCardStyle()).accessibilityLabel(
                  "Open \(space.title), \(space.id.suffix(8))")
              }
            }.padding(24)
          }

        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)

  }
}

private struct SpaceCardStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.isFocused) private var focused
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : (hovered ? 0.035 : 0)))
          .allowsHitTesting(false)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2)
          .allowsHitTesting(false)
      }
      .opacity(enabled ? 1 : 0.5)
      .onHover { hovered = $0 }
  }
}

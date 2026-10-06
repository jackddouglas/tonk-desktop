import HarnessCore
import SwiftUI

struct SpacePickerView: View {
  @ObservedObject var runtime: RuntimeModel
  var onOpen: (TonkSpace) -> Void
  @State private var search = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Find a space", text: $search).textFieldStyle(.plain)
          .accessibilityLabel("Find a space")
        if !search.isEmpty {
          Button {
            search = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain).accessibilityLabel("Clear search")
        }
      }.padding(12)
        .controlSurface(radius: 20)
        .overlay {
          RoundedRectangle(cornerRadius: 20)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 20).padding(.top, 8)
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
          description: Text("Sign in to Tonk to load your spaces, or create one in your browser."))
      } else {
        let matching = runtime.spaces.filter {
          search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        }
        if matching.isEmpty {
          ContentUnavailableView.search(text: search)
        } else {
          ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
              ForEach(matching) { space in
                Button {
                  onOpen(space)
                } label: {
                  VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "square.grid.2x2").font(.title).foregroundStyle(.secondary)
                    Text(space.title).font(.headline).lineLimit(2).help(space.title)
                    HStack {
                      Text("Open space").font(.caption).foregroundStyle(.secondary)
                      Spacer()
                      Image(systemName: "arrow.up.right").font(.caption)
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
                }.buttonStyle(.plain).accessibilityLabel(
                  "Open \(space.title), \(space.id.suffix(8))")
              }
            }.padding(20)
          }

        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
  }
}

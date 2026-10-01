import SwiftUI

struct SpacePickerView: View {
  @ObservedObject var runtime: RuntimeModel
  @State private var search = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("Find a space", text: $search).textFieldStyle(.roundedBorder)
        Button {
          Task { await runtime.refreshSpaces() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }.accessibilityLabel("Refresh spaces").disabled(runtime.catalogLoading || runtime.loading)
      }.padding(.horizontal, 20).padding(.top, 16)
      if let error = runtime.catalogError {
        Text("Couldn’t load spaces: \(error)").font(.callout).foregroundStyle(.secondary)
          .textSelection(.enabled).padding(.horizontal, 20)
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
          List(matching) { space in
            Button {
              runtime.openSpace(space)
            } label: {
              HStack {
                Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                  Text(space.title).font(.body.weight(.medium))
                  Text(String(space.id.suffix(8))).font(.caption.monospaced()).foregroundStyle(
                    .secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(space.title), \(space.id.suffix(8))")
          }.listStyle(.inset)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
  }
}

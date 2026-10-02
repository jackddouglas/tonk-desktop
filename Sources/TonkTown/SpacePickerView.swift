import SwiftUI

struct SpacePickerView: View {
  @ObservedObject var runtime: RuntimeModel
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
          List(matching) { space in
            Button {
              runtime.openSpace(space)
            } label: {
              HStack {
                Image(systemName: "square.grid.2x2")
                  .font(.title3).foregroundStyle(.secondary)
                  .frame(width: 36, height: 36)
                  .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                  Text(space.title).font(.body.weight(.medium)).lineLimit(2).help(space.title)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
              }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).listRowSeparator(.hidden).accessibilityLabel(
              "Open \(space.title), \(space.id.suffix(8))")
          }.listStyle(.inset).scrollContentBackground(.hidden)
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
  }
}

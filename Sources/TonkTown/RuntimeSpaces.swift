import Foundation
import HarnessCore

@MainActor
extension RuntimeModel {
  func refreshSpaces() async {
    guard !catalogLoading else { return }
    catalogLoading = true
    catalogError = nil
    defer { catalogLoading = false }
    do {
      let result = try await accountScript(
        """
        const variable = name => ({'?': {name}});
        const field = (the, as) => ({the, as, cardinality: 'one'});
        const meta = '/api/profile/branch/meta/query';
        const active = await api(meta, {
          predicate: {with: {branch: field('tonk.dialog.replica/active-branch', 'Entity')}},
          terms: {this: variable('this'), branch: variable('branch')}
        });
        let branch = 'main';
        if (active[0]?.fields?.branch) {
          const names = await api(meta, {
            predicate: {with: {name: field('xyz.tonk.branch/name', 'Text')}},
            terms: {this: active[0].fields.branch, name: variable('name')}
          });
          if (!names[0]?.fields?.name) throw new Error('Cannot resolve the active account branch.');
          branch = names[0].fields.name;
        }
        const rows = await api('/api/profile/branch/' + encodeURIComponent(branch) + '/query', {
          predicate: {with: {
            subject: field('xyz.tonk.space/subject', 'Entity'),
            name: {...field('xyz.tonk.space/name', 'Text'), optional: true}
          }},
          terms: {this: variable('this'), subject: variable('subject'), name: variable('name')}
        });
        if (!Array.isArray(rows)) throw new Error('Invalid space catalog response.');
        return {branch, spaces: rows.map(row => ({subject: row.fields.subject, name: row.fields.name || null}))};
        """)
      guard let rows = result["spaces"] else {
        throw CallbackError("The runtime returned no space catalog.")
      }
      spaces = try TonkSpace.decodeCatalog(JSONSerialization.data(withJSONObject: rows))
      if let selectedSpace {
        self.selectedSpace = spaces.first(where: { $0.id == selectedSpace.id })
      }
      catalogBranch = result["branch"] as? String
      catalogLoaded = true
    } catch {
      catalogError =
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
        ?? error.localizedDescription
    }
  }

  func openSpace(_ space: TonkSpace) {
    selectedSpace = space
    error = nil
    webView.load(URLRequest(url: space.url))
  }

  func showSpaces() {
    selectedSpace = nil
    Task { await refreshSpaces() }
  }
}

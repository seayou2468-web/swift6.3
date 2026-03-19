import SwiftUI

@main
struct EmbeddedCompilerIDEApp: App {
  @StateObject private var viewModel = EmbeddedCompilerIDEViewModel()

  var body: some Scene {
    WindowGroup {
      EmbeddedCompilerIDEView(viewModel: viewModel)
    }
  }
}

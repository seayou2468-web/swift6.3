import SwiftUI

struct EmbeddedCompilerIDEView: View {
  @ObservedObject var viewModel: EmbeddedCompilerIDEViewModel

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("Embedded Swift IDE Demo")
          .font(.title2.bold())

        TextEditor(text: $viewModel.sourceCode)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 180)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))

        Button("Compile & Run Hello World") {
          viewModel.compileAndRun()
        }
        .buttonStyle(.borderedProminent)

        Text(viewModel.statusMessage)
          .font(.footnote)
          .foregroundStyle(.secondary)

        GroupBox("LLVM IR") {
          ScrollView {
            Text(viewModel.llvmIR.isEmpty ? "No IR yet" : viewModel.llvmIR)
              .frame(maxWidth: .infinity, alignment: .leading)
              .font(.system(.footnote, design: .monospaced))
          }
          .frame(minHeight: 140)
        }

        GroupBox("Execution Output") {
          Text(viewModel.executionOutput.isEmpty ? "No output yet" : viewModel.executionOutput)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(.body, design: .monospaced))
        }

        if !viewModel.diagnostics.isEmpty {
          GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(viewModel.diagnostics, id: \.self) { diagnostic in
                Text(diagnostic)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      }
      .padding()
      .navigationTitle("Compiler IDE")
    }
  }
}
